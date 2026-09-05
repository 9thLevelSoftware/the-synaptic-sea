#!/usr/bin/env python3
"""Create immutable, review-only Meshy promotion proposal leaves.

The proposal boundary consumes only a governed task whose candidate review has
already been independently verified as ``promotion_ready``.  It writes no
runtime asset, catalog, wrapper, index, or imported sidecar.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Tuple, Union
from urllib.parse import parse_qsl, urlsplit

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools import meshy_candidate_review as candidate_review  # noqa: E402
from tools import meshy_governance as governance  # noqa: E402
from tools.meshy_asset_contract import canonical_json_bytes, load_contract  # noqa: E402


PROP_OVERLAY_NAME = "sidecar-overlay.json"
THREAT_PATCH_NAME = "threat_visual_catalog.patch.json"
ASSET_PROVENANCE_NAME = "asset-provenance.json"
BIOMASS_CATALOG_PATCH_NAME = "biomass_part_catalog.patch.json"
BIOMASS_WRAPPER_PROPOSAL_NAME = "biomass_wrapper.proposal.json"
PROP_DOCUMENT_KIND = "meshy_sidecar_overlay"
THREAT_DOCUMENT_KIND = "meshy_threat_promotion_proposal"
THREAT_PATCH_DOCUMENT_KIND = "threat_visual_catalog_patch"
ASSET_PROVENANCE_DOCUMENT_KIND = "asset_provenance"
BIOMASS_CATALOG_PATCH_DOCUMENT_KIND = "biomass_part_catalog_patch_v1"
BIOMASS_WRAPPER_DOCUMENT_KIND = "biomass_wrapper_proposal_v1"
BIOMASS_CATALOG_RELATIVE = Path("data/combat/biomass_part_catalog.json")
BIOMASS_MASTER_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source")
BIOMASS_EVIDENCE_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot")
BIOMASS_CATEGORIES = frozenset(
    (
        "biomass_core",
        "biomass_limb",
        "biomass_head",
        "biomass_connector",
        "biomass_appendage",
    )
)
IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
RIGHTS_STATES = frozenset(("paid-private", "free-cc-by-4.0"))
FORBIDDEN_SECRET_FIELD_RE = re.compile(
    r"(?:api[_-]?key|authorization|access[_-]?token|client[_-]?secret|password|private[_-]?key|secret)",
    re.IGNORECASE,
)
API_KEY_VALUE_RE = re.compile(
    r"(?:\b(?:sk|pk)[_-][A-Za-z0-9_-]{8,}\b|\bBearer\s+[A-Za-z0-9._~+/=-]{12,})",
    re.IGNORECASE,
)
SIGNED_QUERY_KEYS = {
    "sig",
    "signature",
    "x-amz-algorithm",
    "x-amz-credential",
    "x-amz-date",
    "x-amz-expires",
    "x-amz-signature",
    "x-amz-signedheaders",
    "se",
    "sp",
    "sr",
    "st",
    "sv",
    "token",
}

# Test-only fault-injection seam. Normal operation leaves this as None.
_BIOMASS_AFTER_LEAF_HOOK: Callable[[Path, int], None] | None = None

PathLike = Union[str, Path]


class PromotionPacketError(ValueError):
    """Raised when a promotion proposal cannot pass its safety gates."""


def _security_diagnostics(value: object, label: str = "") -> List[str]:
    diagnostics: List[str] = []
    stack: List[Tuple[object, str]] = [(value, label)]
    seen: set[int] = set()
    while stack:
        current, current_label = stack.pop()
        if isinstance(current, dict):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            for key, child in current.items():
                path = "{0}.{1}".format(current_label, key) if current_label else str(key)
                if isinstance(key, str) and FORBIDDEN_SECRET_FIELD_RE.search(key):
                    diagnostics.append("API key or secret field is not allowed: {0}".format(path))
                stack.append((child, path))
        elif isinstance(current, (list, tuple)):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            for index in range(len(current) - 1, -1, -1):
                stack.append((current[index], "{0}[{1}]".format(current_label, index)))
        elif isinstance(current, str):
            parsed = urlsplit(current)
            if parsed.scheme.lower() in ("http", "https"):
                query_keys = {
                    key.lower() for key, _value in parse_qsl(parsed.query, keep_blank_values=True)
                }
                if query_keys.intersection(SIGNED_QUERY_KEYS) or "signed" in parsed.path.lower():
                    diagnostics.append("signed URL is not allowed: {0}".format(current_label))
            if API_KEY_VALUE_RE.search(current):
                diagnostics.append("API key or bearer token is not allowed: {0}".format(current_label))
    return sorted(set(diagnostics))


def _hash_diagnostic(value: object, label: str, errors: List[str]) -> None:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        errors.append("{0} must be 64 lowercase hexadecimal characters".format(label))


def validate_ai_provenance(value: object) -> List[str]:
    """Return deterministic diagnostics for the proposal provenance envelope."""
    errors = _security_diagnostics(value)
    if not isinstance(value, dict):
        return errors + ["provenance envelope must be an object"]

    if set(value) != {"provenance", "extensions"}:
        errors.extend(
            "unknown or missing provenance envelope field: {0}".format(key)
            for key in sorted(set(value) ^ {"provenance", "extensions"})
        )

    provenance = value.get("provenance")
    if not isinstance(provenance, dict):
        errors.append("provenance must be an object")
    else:
        if set(provenance) != {"provider", "license_state"}:
            errors.extend(
                "unknown or missing provenance field: {0}".format(key)
                for key in sorted(set(provenance) ^ {"provider", "license_state"})
            )
        if provenance.get("provider") != "meshy":
            errors.append("provenance.provider must be meshy")
        if provenance.get("license_state") not in RIGHTS_STATES:
            errors.append("provenance.license_state is not an approved rights state")

    extensions = value.get("extensions")
    if not isinstance(extensions, dict):
        errors.append("extensions must be an object")
    else:
        if set(extensions) != {"ai_generated", "ai_generation"}:
            errors.extend(
                "unknown or missing extensions field: {0}".format(key)
                for key in sorted(set(extensions) ^ {"ai_generated", "ai_generation"})
            )
        if extensions.get("ai_generated") is not True:
            errors.append("extensions.ai_generated must be true")
        ai_generation = extensions.get("ai_generation")
        required = {
            "provider",
            "task_id",
            "model",
            "input_sha256",
            "raw_output_sha256",
            "cleaned_output_sha256",
            "contract_sha256",
            "human_cleanup",
            "reviewer",
        }
        if not isinstance(ai_generation, dict):
            errors.append("extensions.ai_generation must be an object")
        else:
            if set(ai_generation) != required:
                errors.extend(
                    "unknown or missing ai_generation field: {0}".format(key)
                    for key in sorted(set(ai_generation) ^ required)
                )
            if ai_generation.get("provider") != "meshy":
                errors.append("extensions.ai_generation.provider must be meshy")
            task_id = ai_generation.get("task_id")
            if not isinstance(task_id, str) or TASK_ID_RE.fullmatch(task_id) is None:
                errors.append("extensions.ai_generation.task_id must be a safe identifier")
            if not isinstance(ai_generation.get("model"), str) or not ai_generation.get("model"):
                errors.append("extensions.ai_generation.model is required")
            inputs = ai_generation.get("input_sha256")
            if not isinstance(inputs, list) or not inputs:
                errors.append("extensions.ai_generation.input_sha256 must be a non-empty list")
            else:
                if any(not isinstance(item, str) for item in inputs):
                    errors.append("extensions.ai_generation.input_sha256 must contain hashes")
                string_inputs = [item for item in inputs if isinstance(item, str)]
                if len(string_inputs) != len(set(string_inputs)):
                    errors.append("extensions.ai_generation.input_sha256 must contain unique hashes")
                for index, item in enumerate(inputs):
                    _hash_diagnostic(item, "extensions.ai_generation.input_sha256[{0}]".format(index), errors)
            for field in ("raw_output_sha256", "cleaned_output_sha256", "contract_sha256"):
                _hash_diagnostic(
                    ai_generation.get(field), "extensions.ai_generation." + field, errors
                )
            if ai_generation.get("human_cleanup") is not True:
                errors.append("extensions.ai_generation.human_cleanup must be true")
            if not isinstance(ai_generation.get("reviewer"), str) or not ai_generation.get("reviewer", "").strip():
                errors.append("extensions.ai_generation.reviewer is required")
    return sorted(set(errors))


def _copy_json(value: object) -> object:
    try:
        return json.loads(canonical_json_bytes(value).decode("utf-8"))
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise PromotionPacketError("proposal fields must be JSON serializable") from exc


def _validated_envelope(value: object) -> Dict[str, Any]:
    errors = validate_ai_provenance(value)
    if errors:
        raise PromotionPacketError("invalid AI provenance: " + "; ".join(errors))
    copied = _copy_json(value)
    assert isinstance(copied, dict)
    return copied


def _hash_file(path: Path, label: str) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise PromotionPacketError("missing {0}".format(label)) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_size <= 0:
        raise PromotionPacketError("{0} must be a non-empty regular file".format(label))
    try:
        return governance.file_sha256(path)
    except (OSError, ValueError) as exc:
        raise PromotionPacketError("could not hash {0}".format(label)) from exc


def _verified_task(
    project_root: PathLike, task_dir: PathLike
) -> Tuple[Path, Path, str, str, Dict[str, Any], Dict[str, Any]]:
    """Return only task data authenticated by the candidate/runtime authority."""
    try:
        root, resolved_task, asset_root, asset_id, task_id = candidate_review._task_layout(
            project_root, task_dir
        )
        review = candidate_review.verify_review(root, resolved_task)
        if review.get("state") != "promotion_ready":
            raise PromotionPacketError("promotion proposal requires promotion_ready evidence")
        _review_path, canonical_review, generation, root, _asset_root = candidate_review._load_task_record(
            root, resolved_task
        )
        if canonical_review != review:
            raise PromotionPacketError("canonical promotion review changed during verification")
        if generation.get("status") != "SUCCEEDED":
            raise PromotionPacketError("promotion proposal requires SUCCEEDED generation evidence")
        if generation.get("asset_id") != asset_id or generation.get("task_id") != task_id:
            raise PromotionPacketError("generation identity does not match task directory")
        generation_provenance = generation.get("provenance")
        if not isinstance(generation_provenance, dict) or set(generation_provenance) != {
            "provider",
            "model",
            "license_state",
        }:
            raise PromotionPacketError("generation provenance is incomplete")
        output_license = generation.get("output_license")
        if output_license not in RIGHTS_STATES:
            raise PromotionPacketError("generation output license is not approved")
        if (
            generation_provenance.get("provider") != "meshy"
            or generation_provenance.get("license_state") != output_license
            or not isinstance(generation_provenance.get("model"), str)
            or not generation_provenance.get("model")
        ):
            raise PromotionPacketError("generation provenance and output license disagree")
        inputs = generation.get("input_image_hashes")
        if not isinstance(inputs, dict) or not inputs:
            raise PromotionPacketError("generation input_image_hashes are missing")
        input_hashes = [inputs[key] for key in sorted(inputs)]
        for index, value in enumerate(input_hashes):
            if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
                raise PromotionPacketError("generation input hash is invalid at index {0}".format(index))
        outputs = generation.get("outputs")
        raw_output = outputs.get("raw.glb") if isinstance(outputs, dict) else None
        raw_hash = raw_output.get("sha256") if isinstance(raw_output, dict) else None
        if not isinstance(raw_hash, str) or SHA256_RE.fullmatch(raw_hash) is None:
            raise PromotionPacketError("generation raw.glb hash is missing")
        contract_hash = generation.get("contract_sha256")
        if not isinstance(contract_hash, str) or SHA256_RE.fullmatch(contract_hash) is None:
            raise PromotionPacketError("generation contract hash is invalid")
        reviewer = canonical_review.get("reviewer")
        if not isinstance(reviewer, str) or not reviewer.strip():
            raise PromotionPacketError("promotion review reviewer is missing")
        cleaned = candidate_review._governed_artifact(root, resolved_task, "cleaned.glb")
        cleaned_hash = _hash_file(cleaned, "cleaned.glb")
        envelope = {
            "provenance": {"provider": "meshy", "license_state": output_license},
            "extensions": {
                "ai_generated": True,
                "ai_generation": {
                    "provider": "meshy",
                    "task_id": task_id,
                    "model": generation_provenance["model"],
                    "input_sha256": input_hashes,
                    "raw_output_sha256": raw_hash,
                    "cleaned_output_sha256": cleaned_hash,
                    "contract_sha256": contract_hash,
                    "human_cleanup": True,
                    "reviewer": reviewer,
                },
            },
        }
        _validated_envelope(envelope)
        return root, resolved_task, asset_id, task_id, envelope, generation
    except PromotionPacketError:
        raise
    except (candidate_review.ReviewError, OSError, TypeError, ValueError, RuntimeError, RecursionError) as exc:
        raise PromotionPacketError("canonical promotion evidence is not valid: {0}".format(exc)) from exc


def _target_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PromotionPacketError("{0} must be a non-empty path".format(label))
    if "\x00" in value or value.startswith("http://") or value.startswith("https://"):
        raise PromotionPacketError("{0} must not be a URL".format(label))
    if not value.startswith("res://"):
        raise PromotionPacketError("{0} must be a res:// path".format(label))
    relative = value[6:]
    parts = relative.split("/")
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise PromotionPacketError("{0} must not contain traversal".format(label))
    return value


def _default_prop_target(asset_id: str, prop_kind: str) -> str:
    group = {
        "component": "components",
        "dressing": "dressing",
        "objective": "objectives",
    }[prop_kind]
    return "res://assets/imported/props/{0}/{1}.sidecar.json".format(group, asset_id)


def _validate_prop_target(value: object) -> str:
    target = _target_path(value, "target path")
    if not target.startswith("res://assets/imported/props/") or not target.endswith(".sidecar.json"):
        raise PromotionPacketError("target path must be an imported prop sidecar path")
    return target


def _archetype_for(asset_id: str, archetype: Optional[str]) -> str:
    value = archetype or re.sub(r"_v[0-9]+$", "", asset_id)
    if not value or IDENTIFIER_RE.fullmatch(value) is None:
        raise PromotionPacketError("threat archetype must be a safe identifier")
    return value


def _logical_cleaned_path(root: Path, task_dir: Path) -> str:
    cleaned = candidate_review._governed_artifact(root, task_dir, "cleaned.glb")
    return "res://" + cleaned.relative_to(root).as_posix()


def _validate_threat_mesh_path(
    root: Path, task_dir: Path, mesh_path: Optional[PathLike]
) -> str:
    expected = _logical_cleaned_path(root, task_dir)
    if mesh_path is None:
        return expected
    if isinstance(mesh_path, (Path, os.PathLike)) and not isinstance(mesh_path, str):
        try:
            candidate = governance.governed_task_path(
                root, mesh_path, "threat mesh path", allow_missing=False
            )
        except (OSError, TypeError, ValueError) as exc:
            raise PromotionPacketError("threat mesh path is not governed") from exc
        if candidate != task_dir / "cleaned.glb":
            raise PromotionPacketError("threat mesh path must be the fixed cleaned.glb leaf")
        return expected
    if not isinstance(mesh_path, str) or mesh_path != expected:
        raise PromotionPacketError("threat mesh path must be the fixed cleaned.glb leaf")
    return expected


def _load_task_category(root: Path, task_dir: Path) -> str:
    try:
        contract_path = candidate_review._governed_artifact(root, task_dir, "contract.json")
        contract = load_contract(contract_path)
    except (OSError, TypeError, ValueError, candidate_review.ReviewError) as exc:
        raise PromotionPacketError("task-local contract is not valid") from exc
    category = contract.document.get("category")
    if not isinstance(category, str) or IDENTIFIER_RE.fullmatch(category) is None:
        raise PromotionPacketError("task-local contract category is invalid")
    return category


def _require_packet_category(category: str, packet: str) -> None:
    if packet == "prop":
        if category == "gameplay_prop" or category.startswith("prop"):
            return
        raise PromotionPacketError(
            "prop promotion is incompatible with contract category {0}".format(category)
        )
    if packet == "threat":
        if category.startswith("threat"):
            return
        raise PromotionPacketError(
            "threat promotion is incompatible with contract category {0}".format(category)
        )
    raise PromotionPacketError("unknown promotion packet type")


def build_prop_promotion_proposal(
    project_root: PathLike,
    task_dir: PathLike,
    *,
    target_path: Optional[str] = None,
    prop_kind: str = "dressing",
) -> Dict[str, Any]:
    """Build a sidecar overlay from verified evidence without writing it."""
    if prop_kind not in ("component", "dressing", "objective"):
        raise PromotionPacketError("prop_kind must be component, dressing, or objective")
    root, resolved_task, asset_id, task_id, envelope, _generation = _verified_task(
        project_root, task_dir
    )
    _require_packet_category(_load_task_category(root, resolved_task), "prop")
    target = _validate_prop_target(target_path or _default_prop_target(asset_id, prop_kind))
    document: Dict[str, Any] = {
        "asset_id": asset_id,
        "document_kind": PROP_DOCUMENT_KIND,
        "extensions": envelope["extensions"],
        "prop_kind": prop_kind,
        "proposal_only": True,
        "provenance": envelope["provenance"],
        "target_path": target,
        "task_id": task_id,
    }
    security_errors = _security_diagnostics(document)
    if security_errors:
        raise PromotionPacketError("unsafe promotion proposal: " + "; ".join(security_errors))
    _copy_json(document)
    return document


def build_threat_promotion_proposal(
    project_root: PathLike,
    task_dir: PathLike,
    *,
    mesh_path: Optional[PathLike] = None,
    archetype: Optional[str] = None,
) -> Dict[str, Any]:
    """Build a threat catalog patch and provenance record without writing them."""
    root, resolved_task, asset_id, task_id, envelope, _generation = _verified_task(
        project_root, task_dir
    )
    _require_packet_category(_load_task_category(root, resolved_task), "threat")
    logical_mesh_path = _validate_threat_mesh_path(root, resolved_task, mesh_path)
    archetype_id = _archetype_for(asset_id, archetype)
    patch = {
        "archetype": archetype_id,
        "document_kind": THREAT_PATCH_DOCUMENT_KIND,
        "operations": [
            {
                "op": "add",
                "path": "/archetypes/{0}/mesh_path".format(archetype_id),
                "value": logical_mesh_path,
            }
        ],
        "proposal_only": True,
        "target_path": "data/combat/threat_visual_catalog.json",
        "task_id": task_id,
    }
    asset_provenance = {
        "asset_id": asset_id,
        "document_kind": ASSET_PROVENANCE_DOCUMENT_KIND,
        "extensions": envelope["extensions"],
        "proposal_only": True,
        "provenance": envelope["provenance"],
        "task_id": task_id,
    }
    wrapper = {
        "asset_id": asset_id,
        "catalog_patch": patch,
        "document_kind": THREAT_DOCUMENT_KIND,
        "extensions": envelope["extensions"],
        "proposal_only": True,
        "provenance": envelope["provenance"],
        "asset_provenance": asset_provenance,
        "task_id": task_id,
    }
    for value in (patch, asset_provenance, wrapper):
        security_errors = _security_diagnostics(value)
        if security_errors:
            raise PromotionPacketError("unsafe promotion proposal: " + "; ".join(security_errors))
        _copy_json(value)
    return wrapper


def _layout_for_publication(
    project_root: PathLike, task_dir: PathLike
) -> Tuple[Path, Path]:
    try:
        root, resolved_task, _asset_root, _asset_id, _task_id = candidate_review._task_layout(
            project_root, task_dir
        )
        return root, resolved_task
    except (candidate_review.ReviewError, OSError, TypeError, ValueError, RuntimeError) as exc:
        raise PromotionPacketError("task directory is not governed") from exc


def _fixed_leaf(root: Path, task_dir: Path, name: str) -> Path:
    try:
        return governance.governed_task_path(
            root, task_dir / name, "Meshy fixed proposal " + name, allow_missing=True
        )
    except (OSError, TypeError, ValueError, RuntimeError) as exc:
        raise PromotionPacketError("fixed proposal leaf is not governed: " + name) from exc


def _preflight_leaf(path: Path, expected: bytes, label: str) -> bool:
    if not os.path.lexists(path):
        return False
    try:
        info = path.lstat()
    except OSError as exc:
        raise PromotionPacketError("cannot inspect existing {0}".format(label)) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise PromotionPacketError("existing {0} must be a regular non-symlink file".format(label))
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise PromotionPacketError("existing {0} must use mode 0600".format(label))
    try:
        actual = path.read_bytes()
    except (OSError, UnicodeError) as exc:
        raise PromotionPacketError("existing {0} cannot be read".format(label)) from exc
    if actual != expected:
        raise PromotionPacketError("existing {0} is not the exact canonical proposal".format(label))
    return True


def _publish_missing_leaf(
    root: Path, task_dir: Path, path: Path, value: object, expected: bytes, label: str
) -> None:
    try:
        governance.atomic_write_json(
            path, value, project_root=root, allowed_root=task_dir, mode=0o600
        )
        _preflight_leaf(path, expected, label)
    except PromotionPacketError:
        raise
    except (OSError, TypeError, ValueError, RuntimeError) as exc:
        raise PromotionPacketError("proposal publication failed for {0}".format(label)) from exc


def write_prop_promotion_proposal(
    project_root: PathLike,
    task_dir: PathLike,
    *,
    target_path: Optional[str] = None,
    prop_kind: str = "dressing",
) -> Dict[str, Any]:
    """Build and publish only the fixed task-local prop proposal leaf."""
    proposal = build_prop_promotion_proposal(
        project_root, task_dir, target_path=target_path, prop_kind=prop_kind
    )
    root, resolved_task = _layout_for_publication(project_root, task_dir)
    leaf = _fixed_leaf(root, resolved_task, PROP_OVERLAY_NAME)
    expected = canonical_json_bytes(proposal)
    if not _preflight_leaf(leaf, expected, PROP_OVERLAY_NAME):
        _publish_missing_leaf(root, resolved_task, leaf, proposal, expected, PROP_OVERLAY_NAME)
    return proposal


def write_threat_promotion_proposal(
    project_root: PathLike,
    task_dir: PathLike,
    *,
    mesh_path: Optional[PathLike] = None,
    archetype: Optional[str] = None,
) -> Dict[str, Any]:
    """Build and publish provenance first, then the authoritative catalog patch."""
    proposal = build_threat_promotion_proposal(
        project_root, task_dir, mesh_path=mesh_path, archetype=archetype
    )
    root, resolved_task = _layout_for_publication(project_root, task_dir)
    provenance_leaf = _fixed_leaf(root, resolved_task, ASSET_PROVENANCE_NAME)
    patch_leaf = _fixed_leaf(root, resolved_task, THREAT_PATCH_NAME)
    provenance_bytes = canonical_json_bytes(proposal["asset_provenance"])
    patch_bytes = canonical_json_bytes(proposal["catalog_patch"])

    # Both leaves are checked before either is created or changed.
    provenance_exists = _preflight_leaf(
        provenance_leaf, provenance_bytes, ASSET_PROVENANCE_NAME
    )
    patch_exists = _preflight_leaf(patch_leaf, patch_bytes, THREAT_PATCH_NAME)
    if not provenance_exists:
        _publish_missing_leaf(
            root,
            resolved_task,
            provenance_leaf,
            proposal["asset_provenance"],
            provenance_bytes,
            ASSET_PROVENANCE_NAME,
        )
    if not patch_exists:
        _publish_missing_leaf(
            root,
            resolved_task,
            patch_leaf,
            proposal["catalog_patch"],
            patch_bytes,
            THREAT_PATCH_NAME,
        )
    return proposal


# Biomass part promotion ---------------------------------------------------


def _biomass_lexical(path: PathLike, base: Optional[Path] = None) -> Path:
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = (base or Path.cwd()) / candidate
    return Path(os.path.abspath(os.fspath(candidate)))


def _biomass_contained(root: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def _biomass_reject_symlink_components(path: Path, label: str) -> None:
    absolute = _biomass_lexical(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise PromotionPacketError(f"{label} could not be inspected") from exc
        if stat.S_ISLNK(info.st_mode):
            raise PromotionPacketError(f"{label} contains a symlink component")


def _biomass_regular_file(path: Path, label: str, *, private: bool = False) -> os.stat_result:
    try:
        info = path.lstat()
    except OSError as exc:
        raise PromotionPacketError(f"missing {label}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_size <= 0:
        raise PromotionPacketError(f"{label} must be a non-empty regular file")
    if private and stat.S_IMODE(info.st_mode) != 0o600:
        raise PromotionPacketError(f"{label} must use mode 0600")
    return info


def _biomass_private_directory(path: Path, label: str) -> Path:
    _biomass_reject_symlink_components(path, label)
    try:
        info = path.lstat()
    except OSError as exc:
        raise PromotionPacketError(f"missing {label}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise PromotionPacketError(f"{label} must be a regular directory")
    if stat.S_IMODE(info.st_mode) != 0o700:
        raise PromotionPacketError(f"{label} must use mode 0700")
    return path


def _biomass_project_file(
    root: Path, value: PathLike, label: str, *, expected: Optional[Path] = None
) -> Path:
    candidate = _biomass_lexical(value, root)
    if not _biomass_contained(root, candidate):
        raise PromotionPacketError(f"{label} must be inside the project root")
    _biomass_reject_symlink_components(candidate, label)
    if expected is not None and candidate != expected:
        raise PromotionPacketError(f"{label} is not the repository-authoritative path")
    _biomass_regular_file(candidate, label)
    return candidate


def _biomass_external_file(path: Path, label: str) -> Path:
    _biomass_reject_symlink_components(path, label)
    _biomass_regular_file(path, label)
    return path


def _biomass_canonical_document(path: Path, label: str) -> Tuple[Dict[str, Any], bytes]:
    try:
        document, raw = governance.strict_load_json_bytes(path, label, 4 * 1024 * 1024)
        if raw != canonical_json_bytes(document):
            raise PromotionPacketError(f"{label} is not canonical JSON")
    except PromotionPacketError:
        raise
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError(f"{label} is not valid canonical JSON") from exc
    return document, raw


def _biomass_validate_artifact(
    value: object, path: Path, label: str, *, private: bool = True
) -> Tuple[str, int]:
    if not isinstance(value, Mapping) or set(value) != {"path", "sha256", "byte_size"}:
        raise PromotionPacketError(f"{label} artifact record is not closed")
    declared_path = value.get("path")
    declared_hash = value.get("sha256")
    declared_size = value.get("byte_size")
    if declared_path != str(path):
        raise PromotionPacketError(f"{label} path is not canonical")
    if not isinstance(declared_hash, str) or SHA256_RE.fullmatch(declared_hash) is None:
        raise PromotionPacketError(f"{label} hash is invalid")
    if not isinstance(declared_size, int) or isinstance(declared_size, bool) or declared_size <= 0:
        raise PromotionPacketError(f"{label} byte size is invalid")
    _biomass_regular_file(path, label, private=private)
    actual_hash = _hash_file(path, label)
    actual_size = path.stat().st_size
    if declared_hash != actual_hash or declared_size != actual_size:
        raise PromotionPacketError(f"{label} does not match its artifact record")
    return actual_hash, actual_size


def _biomass_validate_render(value: object, path: Path, label: str) -> Tuple[str, int]:
    if not isinstance(value, Mapping) or set(value) != {"sha256", "byte_size", "width", "height"}:
        raise PromotionPacketError(f"{label} record is not closed")
    declared_hash = value.get("sha256")
    declared_size = value.get("byte_size")
    if not isinstance(declared_hash, str) or SHA256_RE.fullmatch(declared_hash) is None:
        raise PromotionPacketError(f"{label} hash is invalid")
    if not isinstance(declared_size, int) or isinstance(declared_size, bool) or declared_size <= 0:
        raise PromotionPacketError(f"{label} byte size is invalid")
    for field in ("width", "height"):
        dimension = value.get(field)
        if not isinstance(dimension, int) or isinstance(dimension, bool) or dimension <= 0:
            raise PromotionPacketError(f"{label} {field} is invalid")
    _biomass_regular_file(path, label, private=True)
    actual_hash = _hash_file(path, label)
    actual_size = path.stat().st_size
    if declared_hash != actual_hash or declared_size != actual_size:
        raise PromotionPacketError(f"{label} does not match its artifact record")
    return actual_hash, actual_size


def _biomass_expected_evidence(asset_id: str, task_id: str) -> Path:
    return _biomass_lexical(BIOMASS_EVIDENCE_ROOT) / asset_id / task_id


def _biomass_expected_master(asset_id: str) -> Path:
    return _biomass_lexical(BIOMASS_MASTER_ROOT) / asset_id / f"{asset_id}_master.blend"


def _biomass_socket_catalog_entry(entry: Mapping[str, Any]) -> Dict[str, Any]:
    sockets = entry.get("sockets")
    if not isinstance(sockets, list):
        raise PromotionPacketError("biomass catalog sockets are invalid")
    result: List[Dict[str, Any]] = []
    names: set[str] = set()
    for index, socket in enumerate(sockets):
        if not isinstance(socket, Mapping):
            raise PromotionPacketError(f"biomass catalog socket {index} is invalid")
        required = {"name", "kind", "accepts_categories", "position_m", "rotation_deg"}
        if set(socket) != required:
            raise PromotionPacketError(f"biomass catalog socket {index} is not closed")
        name = socket.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise PromotionPacketError("biomass catalog socket names are invalid")
        names.add(name)
        result.append(
            {
                "name": name,
                "kind": socket["kind"],
                "position_m": copy.deepcopy(socket["position_m"]),
                "rotation_deg": copy.deepcopy(socket["rotation_deg"]),
            }
        )
    result.sort(key=lambda value: value["name"])
    return {
        "category": entry.get("category"),
        "assembly_roles": copy.deepcopy(entry.get("assembly_roles")),
        "sockets": result,
    }


def _biomass_load_catalog(
    root: Path, part_catalog_path: PathLike, expected_hash: str, asset_id: str
) -> Tuple[Path, Dict[str, Any], Dict[str, Any]]:
    if SHA256_RE.fullmatch(expected_hash) is None:
        raise PromotionPacketError("expected part catalog hash is invalid")
    expected_path = root / BIOMASS_CATALOG_RELATIVE
    catalog_path = _biomass_project_file(
        root, part_catalog_path, "part catalog", expected=expected_path
    )
    actual_hash = _hash_file(catalog_path, "part catalog")
    if actual_hash != expected_hash:
        raise PromotionPacketError("part catalog hash does not match expected hash")
    try:
        document, _raw = governance.strict_load_json_bytes(
            catalog_path, "part catalog", 4 * 1024 * 1024
        )
        from tools import biomass_catalog_validate

        errors = biomass_catalog_validate.validate_part_catalog(document, root)
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("part catalog is not a valid biomass catalog") from exc
    if errors:
        raise PromotionPacketError("part catalog is not repository-authoritative: " + "; ".join(errors))
    parts = document.get("parts")
    if not isinstance(parts, dict) or asset_id not in parts or not isinstance(parts[asset_id], dict):
        raise PromotionPacketError("part catalog lacks the exact contract asset entry")
    return catalog_path, copy.deepcopy(document), copy.deepcopy(parts[asset_id])


def _biomass_validate_contract_binding(
    root: Path,
    resolved_task: Path,
    contract_path: PathLike,
    generation: Mapping[str, Any],
) -> Tuple[Path, Path, Any, Dict[str, Any], bytes]:
    task_contract_path = candidate_review._governed_artifact(
        root, resolved_task, "contract.json"
    )
    task_contract_document, task_contract_raw = _biomass_canonical_document(
        task_contract_path, "task contract"
    )
    try:
        task_contract = load_contract(task_contract_path)
        caller_path = _biomass_project_file(root, contract_path, "caller contract")
        caller_contract = load_contract(caller_path)
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("caller contract is not valid") from exc
    if caller_contract.snapshot_bytes() != task_contract.snapshot_bytes():
        raise PromotionPacketError("caller contract does not match task-local contract")
    contract_artifact_hash = hashlib.sha256(task_contract_raw).hexdigest()
    if generation.get("contract_artifact_sha256") != contract_artifact_hash:
        raise PromotionPacketError("generation contract artifact is not bound")
    if generation.get("contract_sha256") != caller_contract.sha256:
        raise PromotionPacketError("generation contract hash is not bound to caller contract")
    if task_contract_document != task_contract.document:
        raise PromotionPacketError("task contract snapshot changed during verification")
    return task_contract_path, caller_path, caller_contract, task_contract_document, task_contract_raw


def _biomass_validate_task_records(
    root: Path,
    resolved_task: Path,
    asset_id: str,
    task_id: str,
    contract_path: PathLike,
    generation: Mapping[str, Any],
) -> Dict[str, Any]:
    task_contract_path, caller_path, contract, contract_document, task_contract_raw = _biomass_validate_contract_binding(
        root, resolved_task, contract_path, generation
    )
    category = contract_document.get("category")
    if category not in BIOMASS_CATEGORIES:
        raise PromotionPacketError("contract category is not one of the five biomass categories")
    if contract.asset_id != asset_id:
        raise PromotionPacketError("contract asset_id does not match task directory")
    generation_path = candidate_review._governed_artifact(root, resolved_task, "generation.json")
    _biomass_regular_file(generation_path, "generation.json", private=True)
    generation_hash = _hash_file(generation_path, "generation.json")
    outputs = generation.get("outputs")
    raw_output = outputs.get("raw.glb") if isinstance(outputs, Mapping) else None
    if not isinstance(raw_output, Mapping):
        raise PromotionPacketError("generation raw.glb output is missing")
    raw_hash = raw_output.get("sha256")
    raw_size = raw_output.get("byte_size")
    if not isinstance(raw_hash, str) or SHA256_RE.fullmatch(raw_hash) is None:
        raise PromotionPacketError("generation raw.glb hash is invalid")
    if not isinstance(raw_size, int) or isinstance(raw_size, bool) or raw_size <= 0:
        raise PromotionPacketError("generation raw.glb byte size is invalid")
    raw_path = resolved_task / "raw.glb"
    _biomass_regular_file(raw_path, "raw.glb", private=True)
    if _hash_file(raw_path, "raw.glb") != raw_hash or raw_path.stat().st_size != raw_size:
        raise PromotionPacketError("raw.glb does not match generation evidence")
    return {
        "task_contract_path": task_contract_path,
        "caller_contract_path": caller_path,
        "contract": contract,
        "contract_document": contract_document,
        "task_contract_raw": task_contract_raw,
        "generation_path": generation_path,
        "generation_sha256": generation_hash,
        "raw_path": raw_path,
        "raw_sha256": raw_hash,
        "raw_byte_size": raw_size,
    }


def _biomass_validate_external_evidence(
    root: Path,
    resolved_task: Path,
    asset_id: str,
    task_id: str,
    contract: Any,
    task_records: Mapping[str, Any],
) -> Dict[str, Any]:
    evidence_dir = _biomass_expected_evidence(asset_id, task_id)
    _biomass_private_directory(evidence_dir, "biomass evidence directory")
    source_path = evidence_dir / "source-raw-manifest.json"
    source, source_raw = _biomass_canonical_document(source_path, "source-raw-manifest.json")
    try:
        from tools import meshy_biomass_part_recipe as recipe

        source = dict(recipe.load_source_raw_manifest(source_path))
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("source-raw-manifest.json is not canonical Task 10 evidence") from exc
    if (
        source.get("asset_id") != asset_id
        or source.get("task_id") != task_id
        or source.get("contract_sha256") != contract.sha256
        or source.get("generation_sha256") != task_records["generation_sha256"]
    ):
        raise PromotionPacketError("source raw manifest is not bound to the selected task")
    raw_path = task_records["raw_path"]
    archive_path = evidence_dir / "source.raw.glb"
    raw_hash, raw_size = _biomass_validate_artifact(
        source.get("raw_source"), raw_path, "source raw output"
    )
    archive_hash, archive_size = _biomass_validate_artifact(
        source.get("archive"), archive_path, "source raw archive"
    )
    if (raw_hash, raw_size) != (archive_hash, archive_size) != (
        task_records["raw_sha256"],
        task_records["raw_byte_size"],
    ):
        raise PromotionPacketError("source raw manifest does not match generation raw output")

    preview_manifest_path = evidence_dir / "biomass-part-preview.json"
    approval_path = evidence_dir / "biomass-part-preview-approval.json"
    preview_path = evidence_dir / "cleaned.preview.glb"
    preview, preview_raw = _biomass_canonical_document(
        preview_manifest_path, "biomass-part-preview.json"
    )
    approval, approval_raw = _biomass_canonical_document(
        approval_path, "biomass-part-preview-approval.json"
    )
    try:
        preview = dict(recipe.load_preview_manifest(preview_manifest_path))
        approval = dict(recipe.load_preview_approval(approval_path))
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("Task 10 preview evidence is not canonical") from exc
    _biomass_regular_file(preview_path, "cleaned.preview.glb", private=True)
    preview_hash = hashlib.sha256(preview_raw).hexdigest()
    approval_hash = hashlib.sha256(approval_raw).hexdigest()
    if approval.get("preview_manifest_sha256") != preview_hash:
        raise PromotionPacketError("preview approval does not bind preview manifest")
    if (
        preview.get("asset_id") != asset_id
        or preview.get("task_id") != task_id
        or preview.get("contract_sha256") != contract.sha256
        or preview.get("generation_sha256") != task_records["generation_sha256"]
        or preview.get("source_raw_manifest_sha256") != hashlib.sha256(source_raw).hexdigest()
        or preview.get("raw_sha256") != task_records["raw_sha256"]
        or preview.get("archive_sha256") != task_records["raw_sha256"]
        or preview.get("preview_glb", {}).get("path") != str(preview_path)
    ):
        raise PromotionPacketError("preview manifest is not bound to the selected task")
    preview_artifact_hash, preview_artifact_size = _biomass_validate_artifact(
        preview.get("preview_glb"), preview_path, "cleaned preview GLB"
    )
    if approval.get("preview_glb_sha256") != preview_artifact_hash:
        raise PromotionPacketError("preview approval GLB hash does not match preview")
    renders = preview.get("renders")
    render_hashes = approval.get("render_hashes")
    if not isinstance(renders, Mapping) or not isinstance(render_hashes, Mapping):
        raise PromotionPacketError("preview render evidence is missing")
    for name, record in renders.items():
        if not isinstance(record, Mapping):
            raise PromotionPacketError("preview render record is invalid")
        render_path = evidence_dir / name
        _biomass_validate_render(record, render_path, "preview render " + name)
        if render_hashes.get(name) != record.get("sha256"):
            raise PromotionPacketError("preview approval render hash does not match preview")
    if approval.get("asset_id") != asset_id or approval.get("task_id") != task_id:
        raise PromotionPacketError("preview approval identity is not bound")
    if approval.get("contract_sha256") != contract.sha256:
        raise PromotionPacketError("preview approval contract hash is not bound")
    if approval.get("generation_sha256") != task_records["generation_sha256"]:
        raise PromotionPacketError("preview approval generation hash is not bound")
    return {
        "evidence_dir": evidence_dir,
        "source": source,
        "source_sha256": hashlib.sha256(source_raw).hexdigest(),
        "preview": preview,
        "preview_sha256": preview_hash,
        "preview_glb_sha256": preview_artifact_hash,
        "preview_glb_byte_size": preview_artifact_size,
        "approval": approval,
        "approval_sha256": approval_hash,
    }


def _biomass_validate_recipe_and_reports(
    root: Path,
    resolved_task: Path,
    asset_id: str,
    task_id: str,
    contract: Any,
    task_records: Mapping[str, Any],
    evidence: Mapping[str, Any],
    catalog_hash: str,
    catalog_entry: Mapping[str, Any],
) -> Dict[str, Any]:
    recipe_path = resolved_task / "biomass-part-recipe.json"
    recipe_manifest, recipe_raw = _biomass_canonical_document(
        recipe_path, "biomass-part-recipe.json"
    )
    try:
        from tools import meshy_biomass_part_recipe as recipe_module

        recipe_manifest = dict(recipe_module.load_recipe_manifest(recipe_path))
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("biomass-part-recipe.json is not canonical Task 10 evidence") from exc
    master_path = _biomass_expected_master(asset_id)
    _biomass_external_file(master_path, "canonical Blender master")
    master_hash = _hash_file(master_path, "canonical Blender master")
    cleaned_path = resolved_task / "cleaned.glb"
    cleaned_info = _biomass_regular_file(cleaned_path, "cleaned.glb", private=True)
    cleaned_hash = _hash_file(cleaned_path, "cleaned.glb")
    source_hash = evidence["source_sha256"]
    preview = evidence["preview"]
    approval = evidence["approval"]
    common_bindings = {
        "asset_id": asset_id,
        "task_id": task_id,
        "contract_sha256": contract.sha256,
        "part_catalog_sha256": catalog_hash,
        "generation_sha256": task_records["generation_sha256"],
        "source_raw_manifest_sha256": source_hash,
        "raw_sha256": task_records["raw_sha256"],
        "archive_sha256": task_records["raw_sha256"],
        "master_path": str(master_path),
        "master_sha256": master_hash,
    }
    for field, value in common_bindings.items():
        if preview.get(field) != value:
            raise PromotionPacketError(f"preview {field} is not bound to the selected evidence")
        if approval.get(field) != value:
            raise PromotionPacketError(f"preview approval {field} is not bound to the selected evidence")
    if (
        approval.get("preview_manifest_sha256") != evidence["preview_sha256"]
        or approval.get("preview_glb_sha256") != preview.get("preview_glb", {}).get("sha256")
        or approval.get("render_hashes")
        != {
            name: record["sha256"]
            for name, record in preview.get("renders", {}).items()
        }
    ):
        raise PromotionPacketError("preview approval does not bind the approved preview evidence")
    expected = {
        **common_bindings,
        "preview_approval_sha256": evidence["approval_sha256"],
    }
    for field, value in expected.items():
        if recipe_manifest.get(field) != value:
            raise PromotionPacketError(f"recipe {field} is not bound to the selected evidence")
    for field in (
        "dimensions_m",
        "low_poly_target",
        "material_names",
        "material_slot_count",
        "uvs_present",
        "socket_guides",
        "socket_guides_exported",
        "source_raw_preserved",
        "runtime_promoted",
    ):
        if recipe_manifest.get(field) != preview.get(field):
            raise PromotionPacketError(f"recipe {field} differs from the approved preview")
    _biomass_validate_artifact(recipe_manifest.get("cleaned_glb"), cleaned_path, "recipe cleaned GLB")
    if recipe_manifest["cleaned_glb"]["sha256"] != cleaned_hash:
        raise PromotionPacketError("recipe cleaned GLB hash does not match cleaned.glb")
    try:
        from tools.meshy_biomass_part_recipe import build_socket_guides, triangle_limits

        expected_guides = [
            {"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)}
            for guide in build_socket_guides(catalog_entry)
        ]
        target, hard_max = triangle_limits(contract)
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise PromotionPacketError("catalog socket or contract limits are invalid") from exc
    low_poly = recipe_manifest.get("low_poly_target")
    if not isinstance(low_poly, Mapping) or low_poly.get("target_triangles") != target or low_poly.get("hard_max") != hard_max:
        raise PromotionPacketError("recipe triangle limits do not match the contract")
    measured = low_poly.get("measured_triangles")
    expected_status = "met" if isinstance(measured, int) and measured <= target else "review_required"
    if low_poly.get("status") != expected_status or not isinstance(measured, int) or measured > hard_max:
        raise PromotionPacketError("recipe triangle evidence is invalid")
    if recipe_manifest.get("socket_guides") != expected_guides:
        raise PromotionPacketError("recipe socket inventory does not match the catalog")
    if (
        recipe_manifest.get("socket_guides_exported") is not False
        or recipe_manifest.get("source_raw_preserved") is not True
        or recipe_manifest.get("runtime_promoted") is not False
        or recipe_manifest.get("uvs_present") is not True
    ):
        raise PromotionPacketError("recipe visual-only policy flags are invalid")

    report_path = resolved_task / "blender-validation.json"
    report, report_raw = _biomass_canonical_document(report_path, "blender-validation.json")
    _biomass_regular_file(report_path, "blender-validation.json", private=True)
    if report.get("master_provenance") is not None:
        raise PromotionPacketError("blender-validation.json master_provenance must be null")
    try:
        from tools import meshy_blender_validate as blender_validate

        blender_validate._validate_report_record(report)
        expected_report = blender_validate.verify_validation_report(
            cleaned_path,
            task_records["task_contract_path"],
            report,
            task_id=task_id,
            expected_contract_sha256=contract.sha256,
        )
    except Exception as exc:
        raise PromotionPacketError("Blender validation evidence is not bound to cleaned.glb") from exc
    if (
        report.get("task_id") != task_id
        or report.get("asset_id") != asset_id
        or report.get("contract_sha256") != contract.sha256
        or report.get("sha256") != cleaned_hash
        or report.get("byte_size") != cleaned_info.st_size
        or recipe_manifest["low_poly_target"]["measured_triangles"]
        != report.get("triangle_count")
        or recipe_manifest.get("uvs_present") != report.get("uvs_present")
        or not isinstance(expected_report, Mapping)
        or expected_report.get("master_provenance") is not None
    ):
        raise PromotionPacketError("Blender validation identity or visual-only policy is invalid")
    runtime_path = root / "artifacts/validation-previews/meshy" / asset_id / "runtime-review.json"
    runtime_report = None
    try:
        from tools import meshy_runtime_review

        runtime_report = meshy_runtime_review.verify_evidence_chain(root, resolved_task)
    except Exception as exc:
        raise PromotionPacketError("runtime review evidence is not fully bound") from exc
    if not isinstance(runtime_report, Mapping):
        raise PromotionPacketError("runtime review report is invalid")
    runtime_hash = _hash_file(runtime_path, "runtime-review.json")
    if (
        runtime_report.get("asset_id") != asset_id
        or runtime_report.get("task_id") != task_id
        or runtime_report.get("contract_sha256") != contract.sha256
        or runtime_report.get("cleaned_glb_sha256") != cleaned_hash
        or runtime_report.get("blender_validation_sha256") != hashlib.sha256(report_raw).hexdigest()
    ):
        raise PromotionPacketError("runtime review cross-record binding is invalid")
    if recipe_manifest.get("dimensions_m") != report.get("bounds", {}).get("dimensions"):
        raise PromotionPacketError("recipe dimensions do not match Blender validation")
    if recipe_manifest.get("material_names") != report.get("material_names") or recipe_manifest.get("material_slot_count") != len(report.get("material_names", [])):
        raise PromotionPacketError("recipe material evidence does not match Blender validation")
    return {
        "recipe": recipe_manifest,
        "recipe_sha256": hashlib.sha256(recipe_raw).hexdigest(),
        "master_path": master_path,
        "master_sha256": master_hash,
        "cleaned_path": cleaned_path,
        "cleaned_sha256": cleaned_hash,
        "validation_path": report_path,
        "validation_sha256": hashlib.sha256(report_raw).hexdigest(),
        "runtime_path": runtime_path,
        "runtime_sha256": runtime_hash,
        "report": report,
    }


def build_biomass_part_promotion_proposal(
    project_root: PathLike,
    contract_path: PathLike,
    task_dir: PathLike,
    evidence_dir: PathLike,
    part_catalog_path: PathLike,
    expected_part_catalog_sha256: str,
) -> dict[str, dict[str, Any]]:
    """Build three review-only biomass packet documents without writing them."""
    root, resolved_task, asset_id, task_id, envelope, generation = _verified_task(
        project_root, task_dir
    )
    requested_evidence = _biomass_lexical(evidence_dir)
    expected_evidence = _biomass_expected_evidence(asset_id, task_id)
    if requested_evidence != expected_evidence:
        raise PromotionPacketError("evidence directory must be the exact asset/task evidence leaf")
    _biomass_reject_symlink_components(requested_evidence, "evidence directory")
    task_records = _biomass_validate_task_records(
        root, resolved_task, asset_id, task_id, contract_path, generation
    )
    contract = task_records["contract"]
    catalog_path, _catalog_document, catalog_entry = _biomass_load_catalog(
        root, part_catalog_path, expected_part_catalog_sha256, asset_id
    )
    if catalog_entry.get("category") != contract.document.get("category"):
        raise PromotionPacketError("catalog category does not match the biomass contract")
    evidence = _biomass_validate_external_evidence(
        root, resolved_task, asset_id, task_id, contract, task_records
    )
    records = _biomass_validate_recipe_and_reports(
        root,
        resolved_task,
        asset_id,
        task_id,
        contract,
        task_records,
        evidence,
        expected_part_catalog_sha256,
        catalog_entry,
    )
    wrapper_target = f"res://scenes/wrappers/biomass/{asset_id}.tscn"
    import_target = f"res://assets/imported/threats/biomass/{asset_id}.glb"
    catalog_target = "res://data/combat/biomass_part_catalog.json"
    updated_entry = copy.deepcopy(catalog_entry)
    updated_entry["wrapper_scene_path"] = wrapper_target
    wrapper_catalog_entry = _biomass_socket_catalog_entry(catalog_entry)
    patch = {
        "schema_version": "1.0.0",
        "document_kind": BIOMASS_CATALOG_PATCH_DOCUMENT_KIND,
        "asset_id": asset_id,
        "catalog_target": catalog_target,
        "catalog_entry": updated_entry,
        "operations": [
            {
                "op": "replace",
                "path": f"/parts/{asset_id}/wrapper_scene_path",
                "value": wrapper_target,
            }
        ],
        "proposal_only": True,
        "task_id": task_id,
    }
    wrapper = {
        "schema_version": "1.0.0",
        "document_kind": BIOMASS_WRAPPER_DOCUMENT_KIND,
        "asset_id": asset_id,
        "import_target": import_target,
        "wrapper_target": wrapper_target,
        "catalog_target": catalog_target,
        "catalog_entry": wrapper_catalog_entry,
        "proposal_only": True,
        "task_id": task_id,
        "evidence": {
            "contract": {"path": str(task_records["caller_contract_path"]), "sha256": contract.sha256},
            "part_catalog": {"path": str(catalog_path), "sha256": expected_part_catalog_sha256},
            "generation": {"path": str(task_records["generation_path"]), "sha256": task_records["generation_sha256"]},
            "source_raw_manifest": {"path": str(evidence["evidence_dir"] / "source-raw-manifest.json"), "sha256": evidence["source_sha256"]},
            "raw": {"path": str(task_records["raw_path"]), "sha256": task_records["raw_sha256"]},
            "archive": {"path": str(evidence["evidence_dir"] / "source.raw.glb"), "sha256": task_records["raw_sha256"]},
            "cleaned_glb": {"path": str(records["cleaned_path"]), "sha256": records["cleaned_sha256"]},
            "blender_validation": {"path": str(records["validation_path"]), "sha256": records["validation_sha256"]},
            "runtime_review": {"path": str(records["runtime_path"]), "sha256": records["runtime_sha256"]},
            "recipe": {"path": str(resolved_task / "biomass-part-recipe.json"), "sha256": records["recipe_sha256"]},
            "master": {"path": str(records["master_path"]), "sha256": records["master_sha256"]},
        },
    }
    provenance = {
        "asset_id": asset_id,
        "document_kind": ASSET_PROVENANCE_DOCUMENT_KIND,
        "extensions": envelope["extensions"],
        "proposal_only": True,
        "provenance": envelope["provenance"],
        "task_id": task_id,
    }
    documents = {
        BIOMASS_CATALOG_PATCH_NAME: patch,
        BIOMASS_WRAPPER_PROPOSAL_NAME: wrapper,
        ASSET_PROVENANCE_NAME: provenance,
    }
    for name, value in documents.items():
        if _security_diagnostics(value):
            raise PromotionPacketError("unsafe biomass promotion proposal")
        try:
            canonical_json_bytes(value)
        except (TypeError, ValueError, RecursionError) as exc:
            raise PromotionPacketError(f"{name} is not canonical JSON") from exc
    return copy.deepcopy(documents)


def _biomass_preflight_leaf(path: Path, expected: bytes, label: str) -> bool:
    _biomass_reject_symlink_components(path, label)
    if not os.path.lexists(path):
        return False
    _biomass_regular_file(path, label, private=True)
    try:
        actual = path.read_bytes()
    except OSError as exc:
        raise PromotionPacketError(f"existing {label} cannot be read") from exc
    if actual != expected:
        raise PromotionPacketError(f"existing {label} is not the exact canonical proposal")
    return True


def _biomass_publish_bundle(
    root: Path,
    task_dir: Path,
    leaves: List[Tuple[Path, bytes, str]],
) -> None:
    prepared = [
        (path, payload, label, _biomass_preflight_leaf(path, payload, label))
        for path, payload, label in leaves
    ]
    created: List[Tuple[Path, bytes]] = []
    try:
        for index, (path, payload, label, existing) in enumerate(prepared, start=1):
            if existing:
                continue
            governance.atomic_create_bytes(
                path, payload, project_root=root, allowed_root=task_dir, mode=0o600
            )
            _biomass_preflight_leaf(path, payload, label)
            created.append((path, payload))
            if _BIOMASS_AFTER_LEAF_HOOK is not None:
                _BIOMASS_AFTER_LEAF_HOOK(path, index)
    except Exception as exc:
        for path, payload in reversed(created):
            try:
                if path.is_file() and not path.is_symlink() and path.read_bytes() == payload:
                    path.unlink()
            except OSError:
                pass
        if isinstance(exc, PromotionPacketError):
            raise
        raise PromotionPacketError("biomass proposal publication failed") from exc


def write_biomass_part_promotion_proposal(
    project_root: PathLike,
    contract_path: PathLike,
    task_dir: PathLike,
    evidence_dir: PathLike,
    part_catalog_path: PathLike,
    expected_part_catalog_sha256: str,
) -> dict[str, dict[str, Any]]:
    """Publish exactly three immutable task-local biomass proposal leaves."""
    proposal = build_biomass_part_promotion_proposal(
        project_root,
        contract_path,
        task_dir,
        evidence_dir,
        part_catalog_path,
        expected_part_catalog_sha256,
    )
    root, resolved_task = _layout_for_publication(project_root, task_dir)
    leaves = [
        (
            _fixed_leaf(root, resolved_task, name),
            canonical_json_bytes(proposal[name]),
            name,
        )
        for name in (
            BIOMASS_CATALOG_PATCH_NAME,
            BIOMASS_WRAPPER_PROPOSAL_NAME,
            ASSET_PROVENANCE_NAME,
        )
    ]
    _biomass_publish_bundle(root, resolved_task, leaves)
    return proposal


# Names used by callers that refer to the output as an overlay/packet.
build_sidecar_overlay = build_prop_promotion_proposal
write_sidecar_overlay = write_prop_promotion_proposal
build_catalog_promotion_proposal = build_threat_promotion_proposal
write_catalog_promotion_proposal = write_threat_promotion_proposal
validate_provenance = validate_ai_provenance


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prop = subparsers.add_parser("prop", help="write a staged prop sidecar overlay")
    prop.add_argument("--project-root", type=Path, required=True)
    prop.add_argument("--task-dir", type=Path, required=True)
    prop.add_argument("--target-path")
    prop.add_argument("--prop-kind", choices=("component", "dressing", "objective"), default="dressing")
    threat = subparsers.add_parser("threat", help="write staged threat catalog/provenance proposals")
    threat.add_argument("--project-root", type=Path, required=True)
    threat.add_argument("--task-dir", type=Path, required=True)
    threat.add_argument("--mesh-path")
    threat.add_argument("--archetype")
    biomass = subparsers.add_parser(
        "biomass-part", help="write a review-only biomass part proposal"
    )
    biomass.add_argument("--project-root", type=Path, required=True)
    biomass.add_argument("--contract", type=Path, required=True)
    biomass.add_argument("--task-dir", type=Path, required=True)
    biomass.add_argument("--evidence-dir", type=Path, required=True)
    biomass.add_argument("--part-catalog", type=Path, required=True)
    biomass.add_argument("--expected-part-catalog-sha256", required=True)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "prop":
            result = write_prop_promotion_proposal(
                args.project_root,
                args.task_dir,
                target_path=args.target_path,
                prop_kind=args.prop_kind,
            )
            print("MESHY PROP PROMOTION PROPOSAL PASS asset={0}".format(result["asset_id"]))
        elif args.command == "threat":
            result = write_threat_promotion_proposal(
                args.project_root,
                args.task_dir,
                mesh_path=args.mesh_path,
                archetype=args.archetype,
            )
            print("MESHY THREAT PROMOTION PROPOSAL PASS asset={0}".format(result["asset_id"]))
        elif args.command == "biomass-part":
            result = write_biomass_part_promotion_proposal(
                args.project_root,
                args.contract,
                args.task_dir,
                args.evidence_dir,
                args.part_catalog,
                args.expected_part_catalog_sha256,
            )
            wrapper = result[BIOMASS_WRAPPER_PROPOSAL_NAME]
            print(
                "MESHY BIOMASS PART PROMOTION PROPOSAL PASS asset={0}".format(
                    wrapper["asset_id"]
                )
            )
        else:  # pragma: no cover - argparse owns command choices
            return 2
    except (OSError, PromotionPacketError, TypeError, ValueError) as exc:
        print("error: {0}".format(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "ASSET_PROVENANCE_NAME",
    "ASSET_PROVENANCE_DOCUMENT_KIND",
    "BIOMASS_CATALOG_PATCH_DOCUMENT_KIND",
    "BIOMASS_CATALOG_PATCH_NAME",
    "BIOMASS_WRAPPER_DOCUMENT_KIND",
    "BIOMASS_WRAPPER_PROPOSAL_NAME",
    "PROP_DOCUMENT_KIND",
    "PROP_OVERLAY_NAME",
    "PromotionPacketError",
    "THREAT_DOCUMENT_KIND",
    "THREAT_PATCH_DOCUMENT_KIND",
    "THREAT_PATCH_NAME",
    "build_catalog_promotion_proposal",
    "build_biomass_part_promotion_proposal",
    "build_prop_promotion_proposal",
    "build_sidecar_overlay",
    "build_threat_promotion_proposal",
    "main",
    "validate_ai_provenance",
    "validate_provenance",
    "write_catalog_promotion_proposal",
    "write_biomass_part_promotion_proposal",
    "write_prop_promotion_proposal",
    "write_sidecar_overlay",
    "write_threat_promotion_proposal",
]
