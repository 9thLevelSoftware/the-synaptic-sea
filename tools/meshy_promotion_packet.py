#!/usr/bin/env python3
"""Create review-only Meshy promotion proposals with complete provenance.

This module deliberately writes only proposal records beneath
``assets/_staging/meshy``.  It never applies a sidecar, generated index,
threat catalog, wrapper, or imported asset change.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple, Union
from urllib.parse import parse_qsl, urlsplit

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import canonical_json_bytes  # noqa: E402


STAGING_RELATIVE = Path("assets/_staging/meshy")
PROP_OVERLAY_NAME = "sidecar-overlay.json"
THREAT_PATCH_NAME = "threat_visual_catalog.patch.json"
ASSET_PROVENANCE_NAME = "asset-provenance.json"
PROP_DOCUMENT_KIND = "meshy_sidecar_overlay"
THREAT_DOCUMENT_KIND = "meshy_threat_promotion_proposal"
THREAT_PATCH_DOCUMENT_KIND = "threat_visual_catalog_patch"
ASSET_PROVENANCE_DOCUMENT_KIND = "asset_provenance"
IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
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
    "sig",
    "sp",
    "sr",
    "st",
    "sv",
    "token",
}
RIGHTS_STATES = {"paid-private", "free-cc-by-4.0", "project-owned"}

PathLike = Union[str, Path]


class PromotionPacketError(ValueError):
    """Raised when a promotion proposal cannot pass its safety gates."""


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _project_path(project_root: Path, value: PathLike) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path(project_root) / path
    return path.resolve(strict=False)


def _reject_symlink_components(path: Path, label: str) -> None:
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        except OSError as exc:
            raise PromotionPacketError("cannot inspect {0}".format(label)) from exc
        if stat.S_ISLNK(mode) and current not in (Path("/tmp"), Path("/var")):
            raise PromotionPacketError("{0} contains symlink component".format(label))


def _staging_path(project_root: Path, value: PathLike, label: str) -> Path:
    root = Path(project_root).expanduser().resolve(strict=False)
    staging = root / STAGING_RELATIVE
    path = _project_path(root, value)
    staging_resolved = staging.resolve(strict=False)
    if not _contained(staging_resolved, path):
        raise PromotionPacketError(
            "{0} must be inside {1}".format(label, STAGING_RELATIVE.as_posix())
        )
    _reject_symlink_components(path, label)
    return path


def _read_json(path: Path, label: str) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise PromotionPacketError("invalid JSON in {0}".format(label)) from exc


def _copy_json(value: object) -> object:
    try:
        return json.loads(canonical_json_bytes(value).decode("utf-8"))
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise PromotionPacketError("proposal fields must be JSON serializable") from exc


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
                query_keys = {key.lower() for key, _value in parse_qsl(parsed.query, keep_blank_values=True)}
                if query_keys.intersection(SIGNED_QUERY_KEYS) or "signed" in parsed.path.lower():
                    diagnostics.append("signed URL is not allowed: {0}".format(current_label))
            if API_KEY_VALUE_RE.search(current):
                diagnostics.append("API key or bearer token is not allowed: {0}".format(current_label))
    return sorted(set(diagnostics))


def _hash_diagnostic(value: object, label: str, errors: List[str]) -> None:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        errors.append("{0} must be 64 lowercase hexadecimal characters".format(label))


def validate_ai_provenance(value: object) -> List[str]:
    """Return deterministic diagnostics for the ADR-0052 AI provenance envelope."""
    errors = _security_diagnostics(value)
    if not isinstance(value, dict):
        errors.append("provenance envelope must be an object")
        return sorted(set(errors))

    unknown = sorted(set(value) - {"provenance", "extensions"})
    errors.extend("unknown provenance envelope field: {0}".format(key) for key in unknown)

    provenance = value.get("provenance")
    if not isinstance(provenance, dict):
        errors.append("provenance must be an object")
    else:
        unknown_provenance = sorted(set(provenance) - {"license_state", "source_platform"})
        errors.extend("unknown provenance field: {0}".format(key) for key in unknown_provenance)
        license_state = provenance.get("license_state")
        if not isinstance(license_state, str) or not license_state:
            errors.append("provenance.license_state is required")
        elif license_state not in RIGHTS_STATES:
            errors.append("provenance.license_state is not an approved rights state")
        source_platform = provenance.get("source_platform")
        if source_platform != "meshy":
            errors.append("provenance.source_platform must be meshy")

    extensions = value.get("extensions")
    if not isinstance(extensions, dict):
        errors.append("extensions must be an object")
    else:
        unknown_extensions = sorted(set(extensions) - {"ai_generation"})
        errors.extend("unknown extensions field: {0}".format(key) for key in unknown_extensions)
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
            unknown_ai = sorted(set(ai_generation) - required)
            errors.extend("unknown ai_generation field: {0}".format(key) for key in unknown_ai)
            for field in sorted(required):
                if field not in ai_generation:
                    if field.endswith("sha256"):
                        errors.append("extensions.ai_generation missing hash field: {0}".format(field))
                    else:
                        errors.append("extensions.ai_generation missing field: {0}".format(field))

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
                if len(inputs) != len(set(item for item in inputs if isinstance(item, str))):
                    errors.append("extensions.ai_generation.input_sha256 must contain unique hashes")
                for index, item in enumerate(inputs):
                    _hash_diagnostic(item, "extensions.ai_generation.input_sha256[{0}]".format(index), errors)

            for field in ("raw_output_sha256", "cleaned_output_sha256", "contract_sha256"):
                _hash_diagnostic(ai_generation.get(field), "extensions.ai_generation." + field, errors)
            if ai_generation.get("human_cleanup") is not True:
                errors.append("extensions.ai_generation.human_cleanup must be true")
            if not isinstance(ai_generation.get("reviewer"), str) or not ai_generation.get("reviewer", "").strip():
                errors.append("extensions.ai_generation.reviewer is required")

    return sorted(set(errors))


def _validated_envelope(value: object) -> Dict[str, Any]:
    errors = validate_ai_provenance(value)
    if errors:
        raise PromotionPacketError("invalid AI provenance: " + "; ".join(errors))
    copied = _copy_json(value)
    assert isinstance(copied, dict)
    return copied


def _validate_task_dir(project_root: Path, task_dir: PathLike) -> Tuple[Path, str, str]:
    root = Path(project_root).expanduser().resolve(strict=False)
    resolved = _staging_path(root, task_dir, "task directory")
    if not resolved.exists() or not resolved.is_dir() or resolved.is_symlink():
        raise PromotionPacketError("task directory must be an existing directory")
    try:
        relative = resolved.relative_to((root / STAGING_RELATIVE).resolve(strict=False))
    except ValueError as exc:
        raise PromotionPacketError("task directory must be inside Meshy staging") from exc
    parts = relative.parts
    if len(parts) < 2:
        raise PromotionPacketError("task directory must include asset and task identifiers")
    asset_id, task_id = parts[0], parts[-1]
    if IDENTIFIER_RE.fullmatch(asset_id) is None:
        raise PromotionPacketError("staged asset id is not a safe identifier")
    if TASK_ID_RE.fullmatch(task_id) is None:
        raise PromotionPacketError("staged task id is not a safe identifier")
    return resolved, asset_id, task_id


def _hash_file(path: Path, label: str) -> str:
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise PromotionPacketError("missing {0}".format(label)) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or path.stat().st_size <= 0:
        raise PromotionPacketError("{0} must be a non-empty regular file".format(label))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _logical_staging_path(project_root: Path, path: PathLike, label: str) -> str:
    resolved = _staging_path(project_root, path, label)
    root = Path(project_root).expanduser().resolve(strict=False)
    return "res://" + resolved.relative_to(root).as_posix()


def _default_asset_id(task_dir: Path) -> str:
    return task_dir.parent.name


def _default_prop_target(asset_id: str, prop_kind: str) -> str:
    group = {"component": "components", "dressing": "dressing", "objective": "objectives"}.get(prop_kind, "dressing")
    return "res://assets/imported/props/{0}/{1}.sidecar.json".format(group, asset_id)


def _target_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PromotionPacketError("{0} must be a non-empty path".format(label))
    if "\x00" in value or value.startswith("http://") or value.startswith("https://"):
        raise PromotionPacketError("{0} must not be a URL".format(label))
    return value


def _provenance_from_task(task_dir: Path, cleaned_output: Path) -> Dict[str, Any]:
    generation = _read_json(task_dir / "generation.json", "generation.json")
    review = _read_json(task_dir / "review.json", "review.json")
    if not isinstance(generation, dict):
        raise PromotionPacketError("generation.json must be an object")
    if not isinstance(review, dict):
        raise PromotionPacketError("review.json must be an object")
    generation_provenance = generation.get("provenance")
    if not isinstance(generation_provenance, dict):
        raise PromotionPacketError("generation provenance is missing")
    outputs = generation.get("outputs")
    if not isinstance(outputs, dict) or not isinstance(outputs.get("raw.glb"), dict):
        raise PromotionPacketError("generation raw output hash is missing")
    raw_output = outputs["raw.glb"].get("sha256")
    input_hashes = generation.get("input_sha256")
    if input_hashes is None:
        input_hashes = generation.get("input_image_hashes")
    if isinstance(input_hashes, dict):
        input_hashes = [input_hashes[key] for key in sorted(input_hashes)]
    ai_generation = {
        "provider": generation_provenance.get("provider"),
        "task_id": generation.get("task_id"),
        "model": generation_provenance.get("model"),
        "input_sha256": input_hashes,
        "raw_output_sha256": raw_output,
        "cleaned_output_sha256": _hash_file(cleaned_output, "cleaned.glb"),
        "contract_sha256": generation.get("contract_sha256"),
        "human_cleanup": generation.get("human_cleanup", False),
        "reviewer": review.get("reviewer"),
    }
    return {
        "provenance": {
            "license_state": generation_provenance.get("license_state"),
            "source_platform": generation_provenance.get("source_platform", generation_provenance.get("provider")),
        },
        "extensions": {"ai_generation": ai_generation},
    }


def _resolve_envelope(
    provenance: Optional[Mapping[str, Any]], task_dir: Path, cleaned_output: Path
) -> Dict[str, Any]:
    if provenance is None:
        return _validated_envelope(_provenance_from_task(task_dir, cleaned_output))
    return _validated_envelope(provenance)


def build_prop_promotion_proposal(
    project_root: Path,
    task_dir: PathLike,
    *,
    provenance: Optional[Mapping[str, Any]] = None,
    target_path: Optional[str] = None,
    output_path: Optional[PathLike] = None,
    cleaned_output: Optional[PathLike] = None,
    prop_kind: str = "dressing",
) -> Dict[str, Any]:
    """Build a sidecar overlay without writing it or touching live paths."""
    root = Path(project_root).expanduser().resolve(strict=False)
    resolved_task, asset_id, task_id = _validate_task_dir(root, task_dir)
    if prop_kind not in ("component", "dressing", "objective"):
        raise PromotionPacketError("prop_kind must be component, dressing, or objective")
    cleaned = _staging_path(root, cleaned_output or (resolved_task / "cleaned.glb"), "cleaned output path")
    envelope = _resolve_envelope(provenance, resolved_task, cleaned)
    ai_generation = envelope["extensions"]["ai_generation"]
    if ai_generation["task_id"] != task_id:
        raise PromotionPacketError("AI provenance task_id does not match task directory")
    destination = _staging_path(root, output_path or (resolved_task / PROP_OVERLAY_NAME), "proposal output path")
    if destination == cleaned:
        raise PromotionPacketError("proposal output path must not replace cleaned output")
    target = _target_path(target_path or _default_prop_target(asset_id, prop_kind), "target path")
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
    # Scan the complete serialized proposal so no caller-supplied field can
    # smuggle a URL or credential around the provenance validator.
    security_errors = _security_diagnostics(document)
    if security_errors:
        raise PromotionPacketError("unsafe promotion proposal: " + "; ".join(security_errors))
    _copy_json(document)
    return document


def _archetype_for(asset_id: str, archetype: Optional[str]) -> str:
    value = archetype or re.sub(r"_v[0-9]+$", "", asset_id)
    if not value or IDENTIFIER_RE.fullmatch(value) is None:
        raise PromotionPacketError("threat archetype must be a safe identifier")
    return value


def build_threat_promotion_proposal(
    project_root: Path,
    task_dir: PathLike,
    *,
    provenance: Optional[Mapping[str, Any]] = None,
    mesh_path: Optional[PathLike] = None,
    output_path: Optional[PathLike] = None,
    provenance_output_path: Optional[PathLike] = None,
    cleaned_output: Optional[PathLike] = None,
    archetype: Optional[str] = None,
) -> Dict[str, Any]:
    """Build a threat catalog patch and generic provenance record."""
    root = Path(project_root).expanduser().resolve(strict=False)
    resolved_task, asset_id, task_id = _validate_task_dir(root, task_dir)
    cleaned = _staging_path(root, cleaned_output or (resolved_task / "cleaned.glb"), "cleaned output path")
    envelope = _resolve_envelope(provenance, resolved_task, cleaned)
    ai_generation = envelope["extensions"]["ai_generation"]
    if ai_generation["task_id"] != task_id:
        raise PromotionPacketError("AI provenance task_id does not match task directory")
    if mesh_path is None:
        logical_mesh_path = _logical_staging_path(root, cleaned, "cleaned output path")
    elif isinstance(mesh_path, Path):
        logical_mesh_path = _logical_staging_path(root, mesh_path, "threat mesh output path")
    else:
        logical_mesh_path = _target_path(mesh_path, "threat mesh path")
        if not logical_mesh_path.startswith("res://"):
            raise PromotionPacketError("threat mesh path must be a contained res:// path")
        relative = logical_mesh_path[6:]
        if not relative or any(part in ("", ".", "..") for part in relative.split("/")):
            raise PromotionPacketError("threat mesh path must be a contained res:// path")
        _staging_path(root, root / Path(relative), "threat mesh output path")

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

    _staging_path(root, output_path or (resolved_task / THREAT_PATCH_NAME), "catalog patch output path")
    _staging_path(root, provenance_output_path or (resolved_task / ASSET_PROVENANCE_NAME), "asset provenance output path")
    return wrapper


def _atomic_write(path: Path, value: object) -> None:
    destination = Path(path)
    if destination.exists() and (destination.is_symlink() or not destination.is_file()):
        raise PromotionPacketError("proposal output must be a regular file")
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="." + destination.name + ".", suffix=".tmp", dir=str(destination.parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(canonical_json_bytes(value))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))
    finally:
        if descriptor != -1:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def write_prop_promotion_proposal(
    project_root: Path,
    task_dir: PathLike,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Build and write only the staged ``sidecar-overlay.json`` proposal."""
    proposal = build_prop_promotion_proposal(project_root, task_dir, **kwargs)
    root = Path(project_root).expanduser().resolve(strict=False)
    destination = _staging_path(root, kwargs.get("output_path") or (Path(task_dir) / PROP_OVERLAY_NAME), "proposal output path")
    _atomic_write(destination, proposal)
    return proposal


def write_threat_promotion_proposal(
    project_root: Path,
    task_dir: PathLike,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Build and write only staged threat patch/provenance proposal files."""
    proposal = build_threat_promotion_proposal(project_root, task_dir, **kwargs)
    root = Path(project_root).expanduser().resolve(strict=False)
    patch_destination = _staging_path(root, kwargs.get("output_path") or (Path(task_dir) / THREAT_PATCH_NAME), "catalog patch output path")
    provenance_destination = _staging_path(root, kwargs.get("provenance_output_path") or (Path(task_dir) / ASSET_PROVENANCE_NAME), "asset provenance output path")
    _atomic_write(patch_destination, proposal["catalog_patch"])
    _atomic_write(provenance_destination, proposal["asset_provenance"])
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
    prop.add_argument("--output-path", type=Path)
    threat = subparsers.add_parser("threat", help="write staged threat catalog/provenance proposals")
    threat.add_argument("--project-root", type=Path, required=True)
    threat.add_argument("--task-dir", type=Path, required=True)
    threat.add_argument("--mesh-path")
    threat.add_argument("--output-path", type=Path)
    threat.add_argument("--provenance-output-path", type=Path)
    threat.add_argument("--archetype")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "prop":
            result = write_prop_promotion_proposal(
                args.project_root,
                args.task_dir,
                target_path=args.target_path,
                output_path=args.output_path,
            )
            print("MESHY PROP PROMOTION PROPOSAL PASS asset={0}".format(result["asset_id"]))
        elif args.command == "threat":
            result = write_threat_promotion_proposal(
                args.project_root,
                args.task_dir,
                mesh_path=args.mesh_path,
                output_path=args.output_path,
                provenance_output_path=args.provenance_output_path,
                archetype=args.archetype,
            )
            print("MESHY THREAT PROMOTION PROPOSAL PASS asset={0}".format(result["asset_id"]))
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
    "PROP_DOCUMENT_KIND",
    "PROP_OVERLAY_NAME",
    "PromotionPacketError",
    "THREAT_DOCUMENT_KIND",
    "THREAT_PATCH_DOCUMENT_KIND",
    "THREAT_PATCH_NAME",
    "build_catalog_promotion_proposal",
    "build_prop_promotion_proposal",
    "build_sidecar_overlay",
    "build_threat_promotion_proposal",
    "main",
    "validate_ai_provenance",
    "validate_provenance",
    "write_catalog_promotion_proposal",
    "write_prop_promotion_proposal",
    "write_sidecar_overlay",
    "write_threat_promotion_proposal",
]
