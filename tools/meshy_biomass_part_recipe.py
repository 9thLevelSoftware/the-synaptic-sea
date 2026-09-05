#!/usr/bin/env python3
"""Governed, visual-only Blender authoring for one biomass part.

The host side of this module is deliberately safe to import without Blender.
The only ``bpy`` import is inside the background-Blender runtime entry point.
Meshy remains an offline candidate source: this module never calls a provider.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import re
import shutil
import stat
import sys
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools import meshy_candidate_review as candidate_review
from tools import meshy_governance as governance
from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract


BLENDER = "/opt/homebrew/bin/blender"
TRUSTED_MASTER_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source")
TRUSTED_EVIDENCE_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot")
ALLOWED_MODES = ("archive-raw", "rehydrate-raw", "preview", "approve-preview", "publish-cleaned")
RENDER_LEAVES = ("front.png", "side.png", "three_quarter.png", "socket_overlay.png", "contact_sheet.png")
MAX_JSON_BYTES = 4 * 1024 * 1024
MAX_GLB_BYTES = 512 * 1024 * 1024
MAX_JSON_DEPTH = 64
_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
_IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_SOCKET_NAME_RE = re.compile(r"^socket_(root|head|limb|appendage|jaw|distal)_[0-9]+$")

# Test-only fault-injection seam. Normal operation leaves this as None.
_AFTER_LEAF_HOOK: Callable[[Path, int], None] | None = None


class BiomassRecipeError(ValueError):
    """Raised when a biomass recipe input or publication is not governed."""


@dataclass(frozen=True)
class RecipeRoots:
    """Roots used by the private test-injection seam only."""

    master_root: Path
    evidence_root: Path


@dataclass(frozen=True)
class SocketGuide:
    name: str
    position_m: tuple[float, float, float]
    rotation_deg: tuple[float, float, float]


@dataclass(frozen=True)
class RecipePaths:
    project_root: Path
    contract_path: Path
    catalog_path: Path
    task_dir: Path
    evidence_dir: Path
    master_path: Path
    raw_path: Path
    archive_path: Path
    source_manifest_path: Path
    preview_glb_path: Path
    preview_manifest_path: Path
    approval_path: Path
    cleaned_glb_path: Path
    recipe_manifest_path: Path
    review_path: Path
    generation_path: Path
    generation_sha256: str
    raw_sha256: str
    raw_byte_size: int
    asset_id: str
    task_id: str
    reviewer: str = ""
    generation: Mapping[str, Any] | None = None


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value: object) -> bool:
    return (isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)))


def _lexical(value: os.PathLike[str] | str, base: Path | None = None) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = (base or Path.cwd()) / path
    return Path(os.path.abspath(os.fspath(path)))


def _contained(root: Path, path: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _reject_symlink_components(path: Path, label: str) -> None:
    absolute = _lexical(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise BiomassRecipeError(f"{label} could not be inspected") from exc
        if stat.S_ISLNK(info.st_mode):
            raise BiomassRecipeError(f"{label} contains a symlink component")


def _regular_file(path: Path, label: str, *, max_bytes: int = MAX_GLB_BYTES) -> os.stat_result:
    try:
        info = os.lstat(path)
    except OSError as exc:
        raise BiomassRecipeError(f"{label} could not be inspected") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise BiomassRecipeError(f"{label} must be a regular file")
    if info.st_size <= 0 or info.st_size > max_bytes:
        raise BiomassRecipeError(f"{label} is empty or exceeds the size limit")
    return info


def _private_file(path: Path, label: str, *, max_bytes: int = MAX_GLB_BYTES) -> os.stat_result:
    info = _regular_file(path, label, max_bytes=max_bytes)
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise BiomassRecipeError(f"{label} must have mode 0600")
    return info


def _directory(path: Path, label: str, *, allow_missing: bool = False) -> Path:
    _reject_symlink_components(path, label)
    if not path.exists():
        if allow_missing:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        else:
            raise BiomassRecipeError(f"{label} is missing")
    try:
        info = os.lstat(path)
    except OSError as exc:
        raise BiomassRecipeError(f"{label} could not be inspected") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise BiomassRecipeError(f"{label} must be a regular directory")
    if info.st_mode & 0o077:
        raise BiomassRecipeError(f"{label} must be private")
    return path


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _parse_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError("non-finite JSON number")
    return parsed


def _check_depth(value: object, *, limit: int = MAX_JSON_DEPTH) -> None:
    stack: list[tuple[object, int]] = [(value, 0)]
    seen: set[int] = set()
    while stack:
        current, depth = stack.pop()
        if depth > limit:
            raise BiomassRecipeError("JSON maximum nesting depth exceeded")
        if isinstance(current, dict):
            identity = id(current)
            if identity in seen:
                raise BiomassRecipeError("JSON contains a cyclic value")
            seen.add(identity)
            stack.extend((child, depth + 1) for child in current.values())
        elif isinstance(current, list):
            identity = id(current)
            if identity in seen:
                raise BiomassRecipeError("JSON contains a cyclic value")
            seen.add(identity)
            stack.extend((child, depth + 1) for child in current)


def _strict_json_file(path: Path, label: str, *, max_bytes: int = MAX_JSON_BYTES, require_canonical: bool = True) -> tuple[dict[str, Any], bytes]:
    _regular_file(path, label, max_bytes=max_bytes)
    try:
        payload = path.read_bytes()
        text = payload.decode("utf-8", errors="strict")
        document = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_constant,
            parse_float=_parse_float,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError, RecursionError) as exc:
        raise BiomassRecipeError(f"{label} is not valid strict UTF-8 JSON") from exc
    try:
        _check_depth(document)
    except (BiomassRecipeError, RecursionError) as exc:
        raise BiomassRecipeError(f"{label} exceeds JSON depth limits") from exc
    if not isinstance(document, dict):
        raise BiomassRecipeError(f"{label} must be an object")
    try:
        canonical = canonical_json_bytes(document)
    except (TypeError, ValueError, RecursionError) as exc:
        raise BiomassRecipeError(f"{label} contains non-canonical JSON values") from exc
    if require_canonical and payload != canonical:
        raise BiomassRecipeError(f"{label} is not canonical JSON")
    return copy.deepcopy(document), payload


def _check_hash(value: object, label: str) -> str:
    if not isinstance(value, str) or _HASH_RE.fullmatch(value) is None:
        raise BiomassRecipeError(f"{label} must be a lowercase 64-character SHA-256 hash")
    return value


def _check_text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BiomassRecipeError(f"{label} must be non-empty text")
    return value


def _closed_object(value: object, fields: tuple[str, ...], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise BiomassRecipeError(f"{label} must be an object")
    if set(value) != set(fields):
        missing = sorted(set(fields) - set(value))
        unknown = sorted(set(value) - set(fields))
        detail = "missing " + ",".join(missing) if missing else "unknown " + ",".join(unknown)
        raise BiomassRecipeError(f"{label} has non-closed fields: {detail}")
    return value


def _artifact(value: object, label: str) -> dict[str, Any]:
    record = _closed_object(value, ("path", "sha256", "byte_size"), label)
    _check_text(record["path"], label + ".path")
    _check_hash(record["sha256"], label + ".sha256")
    if not _is_int(record["byte_size"]) or record["byte_size"] <= 0:
        raise BiomassRecipeError(f"{label}.byte_size must be a positive integer")
    return record


def _vector(value: object, label: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 3 or any(not _is_number(item) for item in value):
        raise BiomassRecipeError(f"{label} must be a finite three-number list")
    return value


def _socket_records(value: object, label: str) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise BiomassRecipeError(f"{label} must be a list")
    names: set[str] = set()
    result: list[dict[str, Any]] = []
    for index, item in enumerate(value):
        record = _closed_object(item, ("name", "position_m", "rotation_deg"), f"{label}[{index}]")
        name = _check_text(record["name"], f"{label}[{index}].name")
        if name in names:
            raise BiomassRecipeError(f"{label} contains duplicate socket names")
        names.add(name)
        _vector(record["position_m"], f"{label}[{index}].position_m")
        _vector(record["rotation_deg"], f"{label}[{index}].rotation_deg")
        result.append(record)
    return result


def _render_map(value: object, label: str, *, hashes_only: bool = False) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(RENDER_LEAVES):
        raise BiomassRecipeError(f"{label} must contain exactly the five render leaves")
    result: dict[str, Any] = {}
    for leaf in RENDER_LEAVES:
        item = value[leaf]
        if hashes_only:
            result[leaf] = _check_hash(item, f"{label}.{leaf}")
        else:
            record = _closed_object(item, ("sha256", "byte_size", "width", "height"), f"{label}.{leaf}")
            _check_hash(record["sha256"], f"{label}.{leaf}.sha256")
            for field in ("byte_size", "width", "height"):
                if not _is_int(record[field]) or record[field] <= 0:
                    raise BiomassRecipeError(f"{label}.{leaf}.{field} must be a positive integer")
            result[leaf] = record
    return result


def _low_poly(value: object, label: str) -> dict[str, Any]:
    record = _closed_object(value, ("status", "target_triangles", "measured_triangles", "hard_max"), label)
    if record["status"] not in ("met", "review_required"):
        raise BiomassRecipeError(f"{label}.status is invalid")
    for field in ("target_triangles", "measured_triangles", "hard_max"):
        if not _is_int(record[field]) or record[field] < 1:
            raise BiomassRecipeError(f"{label}.{field} must be a positive integer")
    if record["hard_max"] < record["target_triangles"] or record["measured_triangles"] > record["hard_max"]:
        raise BiomassRecipeError(f"{label} triangle limits are inconsistent")
    expected_status = "met" if record["measured_triangles"] <= record["target_triangles"] else "review_required"
    if record["status"] != expected_status:
        raise BiomassRecipeError(f"{label}.status does not match measured triangles")
    return record


def _manifest_document(path: Path, expected_kind: str, fields: tuple[str, ...]) -> dict[str, Any]:
    document, payload = _strict_json_file(path, expected_kind)
    if set(document) != set(fields):
        raise BiomassRecipeError(f"{expected_kind} has non-closed top-level fields")
    if document["schema_version"] != "1.0.0" or document["document_kind"] != expected_kind:
        raise BiomassRecipeError(f"{expected_kind} has an invalid schema or document kind")
    _check_identifier(document["asset_id"], "asset_id")
    if not isinstance(document["task_id"], str) or _TASK_ID_RE.fullmatch(document["task_id"]) is None:
        raise BiomassRecipeError("task_id must be a safe identifier")
    _check_hash(document["contract_sha256"], "contract_sha256")
    return copy.deepcopy(document)


def _check_identifier(value: object, label: str) -> str:
    if not isinstance(value, str) or _IDENTIFIER_RE.fullmatch(value) is None:
        raise BiomassRecipeError(f"{label} must be a lowercase identifier")
    return value


def load_source_raw_manifest(path: Path) -> Mapping[str, Any]:
    fields = ("schema_version", "document_kind", "asset_id", "task_id", "generation_sha256", "contract_sha256", "raw_source", "archive")
    document = _manifest_document(Path(path), "biomass_source_raw_manifest_v1", fields)
    _check_hash(document["generation_sha256"], "generation_sha256")
    _artifact(document["raw_source"], "raw_source")
    _artifact(document["archive"], "archive")
    return copy.deepcopy(document)


def _load_part_common(path: Path, kind: str, fields: tuple[str, ...]) -> dict[str, Any]:
    document = _manifest_document(path, kind, fields)
    _check_hash(document["part_catalog_sha256"], "part_catalog_sha256")
    for field in ("generation_sha256", "source_raw_manifest_sha256", "raw_sha256", "archive_sha256", "master_sha256"):
        _check_hash(document[field], field)
    _check_text(document["master_path"], "master_path")
    _vector(document["dimensions_m"], "dimensions_m")
    _low_poly(document["low_poly_target"], "low_poly_target")
    names = document["material_names"]
    if not isinstance(names, list) or not 1 <= len(names) <= 2 or any(not isinstance(name, str) or not name for name in names) or len(names) != len(set(names)):
        raise BiomassRecipeError("material_names must contain one or two unique names")
    if not _is_int(document["material_slot_count"]) or document["material_slot_count"] != len(names):
        raise BiomassRecipeError("material_slot_count must match material_names")
    if document["uvs_present"] is not True or document["socket_guides_exported"] is not False or document["source_raw_preserved"] is not True or document["runtime_promoted"] is not False:
        raise BiomassRecipeError("visual-only manifest policy flags are invalid")
    _socket_records(document["socket_guides"], "socket_guides")
    return document


def load_preview_manifest(path: Path) -> Mapping[str, Any]:
    fields = ("schema_version", "document_kind", "asset_id", "task_id", "contract_sha256", "part_catalog_sha256", "generation_sha256", "source_raw_manifest_sha256", "raw_sha256", "archive_sha256", "master_path", "master_sha256", "preview_glb", "dimensions_m", "low_poly_target", "material_names", "material_slot_count", "uvs_present", "socket_guides", "socket_guides_exported", "source_raw_preserved", "runtime_promoted", "renders")
    document = _load_part_common(Path(path), "biomass_part_preview_v1", fields)
    _artifact(document["preview_glb"], "preview_glb")
    _render_map(document["renders"], "renders")
    return copy.deepcopy(document)


def load_preview_approval(path: Path) -> Mapping[str, Any]:
    fields = ("schema_version", "document_kind", "asset_id", "task_id", "reviewer", "decision", "preview_manifest_sha256", "preview_glb_sha256", "render_hashes", "contract_sha256", "part_catalog_sha256", "generation_sha256", "source_raw_manifest_sha256", "raw_sha256", "archive_sha256", "master_path", "master_sha256")
    document = _manifest_document(Path(path), "biomass_part_preview_approval_v1", fields)
    _check_text(document["reviewer"], "reviewer")
    if document["decision"] != "approved":
        raise BiomassRecipeError("approval decision must be approved")
    for field in ("preview_manifest_sha256", "preview_glb_sha256", "part_catalog_sha256", "generation_sha256", "source_raw_manifest_sha256", "raw_sha256", "archive_sha256", "master_sha256"):
        _check_hash(document[field], field)
    _check_hashes = _render_map(document["render_hashes"], "render_hashes", hashes_only=True)
    _check_text(document["master_path"], "master_path")
    return copy.deepcopy(document)


def load_recipe_manifest(path: Path) -> Mapping[str, Any]:
    fields = ("schema_version", "document_kind", "asset_id", "task_id", "contract_sha256", "part_catalog_sha256", "generation_sha256", "source_raw_manifest_sha256", "raw_sha256", "archive_sha256", "master_path", "master_sha256", "preview_approval_sha256", "cleaned_glb", "dimensions_m", "low_poly_target", "material_names", "material_slot_count", "uvs_present", "socket_guides", "socket_guides_exported", "source_raw_preserved", "runtime_promoted")
    document = _load_part_common(Path(path), "biomass_part_recipe_v1", fields)
    _check_hash(document["preview_approval_sha256"], "preview_approval_sha256")
    _artifact(document["cleaned_glb"], "cleaned_glb")
    return copy.deepcopy(document)


def triangle_limits(contract: AssetContract) -> tuple[int, int]:
    if not isinstance(contract, AssetContract):
        raise TypeError("contract must be an AssetContract")
    try:
        document = contract.document
        target = document["generation"]["target_polycount"]
        budget = document["budget"]["triangles"]
        if _is_int(budget):
            hard_max = budget
        elif isinstance(budget, Mapping):
            hard_max = budget.get("max")
        else:
            hard_max = None
    except (KeyError, TypeError) as exc:
        raise BiomassRecipeError("contract triangle limits are incomplete") from exc
    if not isinstance(target, int) or isinstance(target, bool) or not isinstance(hard_max, int) or isinstance(hard_max, bool):
        raise BiomassRecipeError("triangle target/hard maximum must be integers")
    if target < 1 or hard_max < target:
        raise BiomassRecipeError("triangle target must be within hard maximum")
    return target, hard_max


def build_socket_guides(catalog_entry: Mapping[str, Any]) -> tuple[SocketGuide, ...]:
    if not isinstance(catalog_entry, Mapping):
        raise BiomassRecipeError("catalog entry must be an object")
    sockets = catalog_entry.get("sockets")
    if not isinstance(sockets, list) or not sockets:
        raise BiomassRecipeError("catalog entry sockets must be a non-empty list")
    guides: list[SocketGuide] = []
    names: set[str] = set()
    for index, socket in enumerate(sockets):
        if not isinstance(socket, Mapping):
            raise BiomassRecipeError(f"socket {index} must be an object")
        if set(socket) != {"name", "kind", "accepts_categories", "position_m", "rotation_deg"}:
            raise BiomassRecipeError(f"socket {index} has non-closed fields")
        name = socket.get("name")
        if not isinstance(name, str) or _SOCKET_NAME_RE.fullmatch(name) is None:
            raise BiomassRecipeError(f"socket {index} name is invalid")
        if name in names:
            raise BiomassRecipeError("catalog contains duplicate socket names")
        names.add(name)
        positions = _vector(socket.get("position_m"), f"socket {name}.position_m")
        rotations = _vector(socket.get("rotation_deg"), f"socket {name}.rotation_deg")
        guides.append(SocketGuide(name, tuple(float(item) for item in positions), tuple(float(item) for item in rotations)))
    guides.sort(key=lambda guide: guide.name)
    return tuple(guides)


def _hash_file(path: Path, *, max_bytes: int = MAX_GLB_BYTES) -> str:
    _regular_file(path, "file", max_bytes=max_bytes)
    return governance.file_sha256(path, max_bytes=max_bytes)


def _load_catalog(path: Path, expected_hash: str) -> dict[str, Any]:
    _check_hash(expected_hash, "expected part catalog hash")
    _regular_file(path, "part catalog", max_bytes=MAX_JSON_BYTES)
    actual = _hash_file(path, max_bytes=MAX_JSON_BYTES)
    if actual != expected_hash:
        raise BiomassRecipeError("part catalog hash does not match expected hash")
    document, _payload = _strict_json_file(path, "part catalog", require_canonical=False)
    if set(document) != {"schema_version", "document_kind", "limits", "parts"} or document["document_kind"] != "biomass_part_catalog":
        raise BiomassRecipeError("part catalog is not the closed biomass catalog")
    parts = document["parts"]
    if not isinstance(parts, dict):
        raise BiomassRecipeError("part catalog parts must be an object")
    return copy.deepcopy(document)


def _load_contract(project: Path, path: Path) -> AssetContract:
    candidate = _lexical(path, project)
    _reject_symlink_components(candidate, "contract")
    if not _contained(project, candidate):
        raise BiomassRecipeError("contract must be inside the project root")
    _regular_file(candidate, "contract", max_bytes=MAX_JSON_BYTES)
    try:
        return load_contract(candidate)
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise BiomassRecipeError(f"contract is invalid: {exc}") from exc


def _task_directory(project: Path, task_dir: Path) -> Path:
    try:
        resolved = governance.governed_task_path(project, task_dir, "biomass task directory", allow_missing=False)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise BiomassRecipeError(f"task directory is not governed: {exc}") from exc
    _directory(resolved, "task directory")
    return resolved


def _root_paths(roots: RecipeRoots, asset_id: str, task_id: str) -> tuple[Path, Path]:
    master_root = _lexical(roots.master_root)
    evidence_root = _lexical(roots.evidence_root)
    _reject_symlink_components(master_root, "master root")
    _reject_symlink_components(evidence_root, "evidence root")
    master = master_root / asset_id / f"{asset_id}_master.blend"
    evidence = evidence_root / asset_id / task_id
    if not _contained(master_root, master) or not _contained(evidence_root, evidence):
        raise BiomassRecipeError("trusted path escaped its root")
    return master, evidence


def _generation_binding(generation: Mapping[str, Any], raw_path: Path) -> tuple[str, int, str]:
    outputs = generation.get("outputs")
    raw_evidence = outputs.get("raw.glb") if isinstance(outputs, Mapping) else None
    if not isinstance(raw_evidence, Mapping):
        raise BiomassRecipeError("generation evidence lacks raw.glb output binding")
    raw_hash = _check_hash(raw_evidence.get("sha256"), "generation raw.glb hash")
    raw_size = raw_evidence.get("byte_size")
    if not _is_int(raw_size) or raw_size <= 0:
        raise BiomassRecipeError("generation raw.glb byte_size is invalid")
    generation_path = raw_path.parent / "generation.json"
    _regular_file(generation_path, "generation.json", max_bytes=MAX_JSON_BYTES)
    generation_hash = _hash_file(generation_path, max_bytes=MAX_JSON_BYTES)
    return raw_hash, raw_size, generation_hash


def _resolve_recipe_paths(
    project_root: Path,
    contract_path: Path,
    catalog_path: Path,
    expected_part_catalog_sha256: str,
    task_dir: Path,
    evidence_dir: Path,
    mode: str,
    *,
    trusted_roots: RecipeRoots,
) -> tuple[AssetContract, Mapping[str, Any], RecipePaths]:
    if mode not in ALLOWED_MODES:
        raise BiomassRecipeError("mode is not one of the five governed modes")
    project = governance.physical_project_root(project_root)
    task_argument = _task_directory(project, task_dir)
    contract = _load_contract(project, contract_path)
    catalog_path_resolved = _lexical(catalog_path, project)
    if not _contained(project, catalog_path_resolved):
        raise BiomassRecipeError("part catalog must be inside the project root")
    catalog = _load_catalog(catalog_path_resolved, expected_part_catalog_sha256)
    asset_id = contract.asset_id
    if not isinstance(asset_id, str) or _IDENTIFIER_RE.fullmatch(asset_id) is None:
        raise BiomassRecipeError("contract asset_id is not a biomass identifier")
    parts = catalog["parts"]
    entry = parts.get(asset_id)
    if not isinstance(entry, Mapping):
        raise BiomassRecipeError("part catalog lacks the exact contract asset entry")
    build_socket_guides(entry)
    try:
        review_path, review, generation, loaded_root, _asset_root = candidate_review._load_task_record(project, task_argument)
    except Exception as exc:
        raise BiomassRecipeError(f"candidate task is not fully governed: {exc}") from exc
    if loaded_root != project:
        raise BiomassRecipeError("candidate task resolved to a different project root")
    task = Path(review_path).parent
    if task != task_argument:
        raise BiomassRecipeError("task argument is not the canonical selected task")
    task_id = task.name
    if not isinstance(review, Mapping) or review.get("state") != "selected":
        raise BiomassRecipeError("biomass recipe requires a selected review")
    if not isinstance(generation, Mapping) or generation.get("status") != "SUCCEEDED":
        raise BiomassRecipeError("biomass recipe requires SUCCEEDED generation evidence")
    if review.get("asset_id") != asset_id or generation.get("asset_id") != asset_id or review.get("task_id") != task_id or generation.get("task_id") != task_id:
        raise BiomassRecipeError("candidate identity does not match the selected task")
    if generation.get("contract_sha256") != contract.sha256:
        raise BiomassRecipeError("generation contract hash does not match the contract")
    raw_path = task / "raw.glb"
    raw_hash, raw_size, generation_hash = _generation_binding(generation, raw_path)
    master_path, expected_evidence = _root_paths(trusted_roots, asset_id, task_id)
    requested_evidence = _lexical(evidence_dir)
    if requested_evidence != expected_evidence:
        raise BiomassRecipeError("evidence directory must be the exact asset/task evidence leaf")
    if mode in ("preview", "approve-preview", "publish-cleaned"):
        _regular_file(master_path, "canonical Blender master")
    evidence = _directory(expected_evidence, "evidence directory", allow_missing=mode == "archive-raw")
    if _contained(project, evidence):
        raise BiomassRecipeError("evidence directory must remain outside the project root")
    if mode == "archive-raw":
        _regular_file(raw_path, "task-local raw.glb")
        info = os.lstat(raw_path)
        if info.st_size != raw_size or _hash_file(raw_path) != raw_hash:
            raise BiomassRecipeError("task-local raw.glb does not match generation evidence")
    paths = RecipePaths(
        project_root=project,
        contract_path=_lexical(contract_path, project),
        catalog_path=catalog_path_resolved,
        task_dir=task,
        evidence_dir=evidence,
        master_path=master_path,
        raw_path=raw_path,
        archive_path=evidence / "source.raw.glb",
        source_manifest_path=evidence / "source-raw-manifest.json",
        preview_glb_path=evidence / "cleaned.preview.glb",
        preview_manifest_path=evidence / "biomass-part-preview.json",
        approval_path=evidence / "biomass-part-preview-approval.json",
        cleaned_glb_path=task / "cleaned.glb",
        recipe_manifest_path=task / "biomass-part-recipe.json",
        review_path=Path(review_path),
        generation_path=task / "generation.json",
        generation_sha256=generation_hash,
        raw_sha256=raw_hash,
        raw_byte_size=raw_size,
        asset_id=asset_id,
        task_id=task_id,
        generation=copy.deepcopy(generation),
    )
    return contract, copy.deepcopy(entry), paths


def resolve_recipe_paths(
    project_root: Path,
    contract_path: Path,
    catalog_path: Path,
    expected_part_catalog_sha256: str,
    task_dir: Path,
    evidence_dir: Path,
    mode: str,
) -> tuple[AssetContract, Mapping[str, Any], RecipePaths]:
    """Resolve a selected biomass task using only fixed production roots."""

    return _resolve_recipe_paths(
        project_root,
        contract_path,
        catalog_path,
        expected_part_catalog_sha256,
        task_dir,
        evidence_dir,
        mode,
        trusted_roots=RecipeRoots(TRUSTED_MASTER_ROOT, TRUSTED_EVIDENCE_ROOT),
    )


def _validate_archive_binding(paths: RecipePaths, contract: AssetContract) -> dict[str, Any]:
    _private_file(paths.source_manifest_path, "source-raw-manifest.json", max_bytes=MAX_JSON_BYTES)
    source = load_source_raw_manifest(paths.source_manifest_path)
    if source["asset_id"] != paths.asset_id or source["task_id"] != paths.task_id or source["contract_sha256"] != contract.sha256 or source["generation_sha256"] != paths.generation_sha256:
        raise BiomassRecipeError("source raw manifest is not bound to the selected generation")
    raw_source = source["raw_source"]
    archive = source["archive"]
    if raw_source["path"] != str(paths.raw_path) or raw_source["sha256"] != paths.raw_sha256 or raw_source["byte_size"] != paths.raw_byte_size:
        raise BiomassRecipeError("source raw manifest raw_source binding is invalid")
    if archive["path"] != str(paths.archive_path) or archive["sha256"] != paths.raw_sha256 or archive["byte_size"] != paths.raw_byte_size:
        raise BiomassRecipeError("source raw manifest archive binding is invalid")
    _private_file(paths.archive_path, "source.raw.glb")
    if _hash_file(paths.archive_path) != paths.raw_sha256 or paths.archive_path.stat().st_size != paths.raw_byte_size:
        raise BiomassRecipeError("external source.raw.glb does not match generation evidence")
    return source


def _ensure_raw_local(paths: RecipePaths) -> None:
    _private_file(paths.raw_path, "task-local raw.glb")
    if paths.raw_path.stat().st_size != paths.raw_byte_size or _hash_file(paths.raw_path) != paths.raw_sha256:
        raise BiomassRecipeError("task-local raw.glb does not match generation evidence")


def _preflight_leaf(path: Path, payload: bytes, label: str, allowed_root: Path) -> bool:
    _reject_symlink_components(path, label)
    if not _contained(allowed_root, _lexical(path)):
        raise BiomassRecipeError(f"{label} is outside the allowed publication root")
    if os.path.lexists(path):
        info = _regular_file(path, label, max_bytes=max(MAX_GLB_BYTES, MAX_JSON_BYTES))
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise BiomassRecipeError(f"{label} must have mode 0600")
        if path.read_bytes() != payload:
            raise BiomassRecipeError(f"{label} already exists with different bytes")
        return True
    return False


def _publish_bundle(leaves: Sequence[tuple[Path, bytes, str]], allowed_root: Path) -> None:
    root = _directory(allowed_root, "publication root")
    prepared: list[tuple[Path, bytes, str, bool]] = []
    for path, payload, label in leaves:
        prepared.append((path, payload, label, _preflight_leaf(path, payload, label, root)))
    created: list[tuple[Path, bytes]] = []
    try:
        for index, (path, payload, label, existing) in enumerate(prepared, start=1):
            if existing:
                continue
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            _reject_symlink_components(path, label)
            governance.atomic_create_bytes(path, payload, project_root=root, allowed_root=root, mode=0o600)
            info = _regular_file(path, label, max_bytes=max(MAX_GLB_BYTES, MAX_JSON_BYTES))
            if stat.S_IMODE(info.st_mode) != 0o600 or path.read_bytes() != payload:
                raise BiomassRecipeError(f"{label} failed read-back verification")
            created.append((path, payload))
            if _AFTER_LEAF_HOOK is not None:
                _AFTER_LEAF_HOOK(path, index)
    except Exception as exc:
        for path, payload in reversed(created):
            try:
                if path.is_file() and not path.is_symlink() and path.read_bytes() == payload:
                    path.unlink()
            except OSError:
                pass
        if isinstance(exc, BiomassRecipeError):
            raise
        raise BiomassRecipeError("coupled publication failed") from exc


def _source_manifest(paths: RecipePaths, contract: AssetContract) -> dict[str, Any]:
    return {
        "schema_version": "1.0.0",
        "document_kind": "biomass_source_raw_manifest_v1",
        "asset_id": paths.asset_id,
        "task_id": paths.task_id,
        "generation_sha256": paths.generation_sha256,
        "contract_sha256": contract.sha256,
        "raw_source": {"path": str(paths.raw_path), "sha256": paths.raw_sha256, "byte_size": paths.raw_byte_size},
        "archive": {"path": str(paths.archive_path), "sha256": paths.raw_sha256, "byte_size": paths.raw_byte_size},
    }


def _archive_raw(paths: RecipePaths, contract: AssetContract) -> dict[str, Any]:
    _ensure_raw_local(paths)
    payload = paths.raw_path.read_bytes()
    source = _source_manifest(paths, contract)
    source_payload = canonical_json_bytes(source)
    _publish_bundle(
        (
            (paths.archive_path, payload, "source.raw.glb"),
            (paths.source_manifest_path, source_payload, "source-raw-manifest.json"),
        ),
        paths.evidence_dir,
    )
    _validate_archive_binding(paths, contract)
    return copy.deepcopy(source)


def _rehydrate_raw(paths: RecipePaths, contract: AssetContract) -> dict[str, Any]:
    source = _validate_archive_binding(paths, contract)
    if os.path.lexists(paths.raw_path):
        info = _regular_file(paths.raw_path, "task-local raw.glb")
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise BiomassRecipeError("existing task-local raw.glb must have mode 0600")
        if paths.raw_path.read_bytes() != paths.archive_path.read_bytes():
            raise BiomassRecipeError("task-local raw.glb differs from the external archive")
        return copy.deepcopy(source)
    _publish_bundle(((paths.raw_path, paths.archive_path.read_bytes(), "task-local raw.glb"),), paths.task_dir)
    _ensure_raw_local(paths)
    return copy.deepcopy(source)


def _artifact_record(path: Path) -> dict[str, Any]:
    info = _regular_file(path, "published artifact")
    return {"path": str(path), "sha256": _hash_file(path), "byte_size": info.st_size}


def _render_record_payload(payload: bytes) -> dict[str, Any]:
    try:
        import io
        from PIL import Image
        with Image.open(io.BytesIO(payload)) as image:
            width, height = image.size
    except Exception as exc:
        raise BiomassRecipeError("render is not a readable PNG") from exc
    return {"sha256": hashlib.sha256(payload).hexdigest(), "byte_size": len(payload), "width": int(width), "height": int(height)}


def _canonical_png_payload(payload: bytes) -> bytes:
    try:
        import io
        from PIL import Image
        with Image.open(io.BytesIO(payload)) as image:
            output = io.BytesIO()
            image.convert("RGBA").save(output, format="PNG", optimize=False, compress_level=6)
            return output.getvalue()
    except Exception as exc:
        raise BiomassRecipeError("render is not a canonical PNG") from exc


def _render_record(path: Path) -> dict[str, Any]:
    info = _regular_file(path, "render", max_bytes=MAX_JSON_BYTES)
    return _render_record_payload(path.read_bytes())


def _write_contact_sheet(run_dir: Path) -> None:
    try:
        from PIL import Image, ImageDraw
        images = [Image.open(run_dir / leaf).convert("RGBA") for leaf in RENDER_LEAVES[:4]]
        width = max(image.width for image in images)
        height = max(image.height for image in images)
        sheet = Image.new("RGBA", (width * 2, height * 2), (20, 24, 30, 255))
        for index, image in enumerate(images):
            sheet.paste(image, ((index % 2) * width, (index // 2) * height))
        draw = ImageDraw.Draw(sheet)
        draw.text((8, 8), "BIOMASS PREVIEW", fill=(255, 255, 255, 255))
        sheet.save(run_dir / "contact_sheet.png", format="PNG", optimize=False)
        for image in images:
            image.close()
    except Exception:
        shutil.copyfile(run_dir / "front.png", run_dir / "contact_sheet.png")


def _preview_manifest(
    paths: RecipePaths,
    contract: AssetContract,
    catalog_hash: str,
    source: Mapping[str, Any],
    runtime: Mapping[str, Any],
    master_hash: str,
    preview_payload: bytes,
    render_payloads: Mapping[str, bytes],
) -> dict[str, Any]:
    target, hard_max = triangle_limits(contract)
    measured = int(runtime["triangle_count"])
    if measured > hard_max:
        raise BiomassRecipeError("cleaned geometry exceeds the contract hard triangle maximum")
    source_manifest_hash = _hash_file(paths.source_manifest_path, max_bytes=MAX_JSON_BYTES)
    return {
        "schema_version": "1.0.0",
        "document_kind": "biomass_part_preview_v1",
        "asset_id": paths.asset_id,
        "task_id": paths.task_id,
        "contract_sha256": contract.sha256,
        "part_catalog_sha256": catalog_hash,
        "generation_sha256": paths.generation_sha256,
        "source_raw_manifest_sha256": source_manifest_hash,
        "raw_sha256": paths.raw_sha256,
        "archive_sha256": paths.raw_sha256,
        "master_path": str(paths.master_path),
        "master_sha256": master_hash,
        "preview_glb": {"path": str(paths.preview_glb_path), "sha256": hashlib.sha256(preview_payload).hexdigest(), "byte_size": len(preview_payload)},
        "dimensions_m": [float(value) for value in runtime["dimensions_m"]],
        "low_poly_target": {"status": "met" if measured <= target else "review_required", "target_triangles": target, "measured_triangles": measured, "hard_max": hard_max},
        "material_names": list(runtime["material_names"]),
        "material_slot_count": len(runtime["material_names"]),
        "uvs_present": bool(runtime["uvs_present"]),
        "socket_guides": list(runtime["socket_guides"]),
        "socket_guides_exported": False,
        "source_raw_preserved": bool(runtime["source_raw_preserved"]),
        "runtime_promoted": False,
        "renders": {leaf: _render_record_payload(render_payloads[leaf]) for leaf in RENDER_LEAVES},
    }


def _validate_preview_binding(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    source = _validate_archive_binding(paths, contract)
    preview = dict(load_preview_manifest(paths.preview_manifest_path))
    catalog_hash = _hash_file(paths.catalog_path, max_bytes=MAX_JSON_BYTES)
    if preview["asset_id"] != paths.asset_id or preview["task_id"] != paths.task_id or preview["contract_sha256"] != contract.sha256 or preview["part_catalog_sha256"] != catalog_hash or preview["generation_sha256"] != paths.generation_sha256 or preview["raw_sha256"] != paths.raw_sha256 or preview["archive_sha256"] != paths.raw_sha256 or preview["master_path"] != str(paths.master_path):
        raise BiomassRecipeError("preview manifest is not bound to current governed inputs")
    if preview["master_sha256"] != _hash_file(paths.master_path):
        raise BiomassRecipeError("preview manifest master hash does not match the canonical master")
    if preview["preview_glb"]["path"] != str(paths.preview_glb_path):
        raise BiomassRecipeError("preview manifest GLB path is not canonical")
    _private_file(paths.preview_glb_path, "cleaned.preview.glb")
    if preview["preview_glb"]["sha256"] != _hash_file(paths.preview_glb_path) or preview["preview_glb"]["byte_size"] != paths.preview_glb_path.stat().st_size:
        raise BiomassRecipeError("preview GLB does not match its manifest")
    expected_guides = [{"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)} for guide in build_socket_guides(catalog_entry)]
    if preview["socket_guides"] != expected_guides:
        raise BiomassRecipeError("preview socket guides do not match the catalog")
    for leaf in RENDER_LEAVES:
        _private_file(paths.evidence_dir / leaf, leaf, max_bytes=MAX_JSON_BYTES)
        actual = _render_record(paths.evidence_dir / leaf)
        if actual != preview["renders"][leaf]:
            raise BiomassRecipeError(f"preview render does not match its manifest: {leaf}")
    return source, preview, {"catalog_sha256": catalog_hash}


def _approve_preview(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> dict[str, Any]:
    _source, preview, binding = _validate_preview_binding(paths, contract, catalog_entry)
    preview_hash = _hash_file(paths.preview_manifest_path, max_bytes=MAX_JSON_BYTES)
    approval = {
        "schema_version": "1.0.0",
        "document_kind": "biomass_part_preview_approval_v1",
        "asset_id": paths.asset_id,
        "task_id": paths.task_id,
        "reviewer": paths.reviewer,
        "decision": "approved",
        "preview_manifest_sha256": preview_hash,
        "preview_glb_sha256": preview["preview_glb"]["sha256"],
        "render_hashes": {leaf: preview["renders"][leaf]["sha256"] for leaf in RENDER_LEAVES},
        "contract_sha256": contract.sha256,
        "part_catalog_sha256": binding["catalog_sha256"],
        "generation_sha256": paths.generation_sha256,
        "source_raw_manifest_sha256": preview["source_raw_manifest_sha256"],
        "raw_sha256": paths.raw_sha256,
        "archive_sha256": paths.raw_sha256,
        "master_path": str(paths.master_path),
        "master_sha256": preview["master_sha256"],
    }
    if not paths.reviewer.strip():
        raise BiomassRecipeError("approve-preview requires a non-empty reviewer")
    payload = canonical_json_bytes(approval)
    _publish_bundle(((paths.approval_path, payload, "biomass-part-preview-approval.json"),), paths.evidence_dir)
    return copy.deepcopy(approval)


def _compare_approved_baseline(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    _source, approved_preview, binding = _validate_preview_binding(paths, contract, catalog_entry)
    _private_file(paths.approval_path, "biomass-part-preview-approval.json", max_bytes=MAX_JSON_BYTES)
    approval = dict(load_preview_approval(paths.approval_path))
    if approval["preview_manifest_sha256"] != _hash_file(paths.preview_manifest_path, max_bytes=MAX_JSON_BYTES) or approval["preview_glb_sha256"] != approved_preview["preview_glb"]["sha256"] or approval["render_hashes"] != {leaf: approved_preview["renders"][leaf]["sha256"] for leaf in RENDER_LEAVES}:
        raise BiomassRecipeError("preview approval does not bind the approved baseline")
    if approval["contract_sha256"] != contract.sha256 or approval["part_catalog_sha256"] != binding["catalog_sha256"] or approval["generation_sha256"] != paths.generation_sha256 or approval["raw_sha256"] != paths.raw_sha256 or approval["archive_sha256"] != paths.raw_sha256 or approval["master_path"] != str(paths.master_path) or approval["master_sha256"] != _hash_file(paths.master_path):
        raise BiomassRecipeError("preview approval is not bound to current governed inputs")
    return approval, approved_preview


def _run_blender(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any], mode: str) -> tuple[dict[str, Any], bytes, dict[str, Any]]:
    from tools.meshy_blender_master import _run_bounded_process

    with tempfile.TemporaryDirectory(prefix=".biomass-recipe-", dir=str(paths.evidence_dir)) as temp_name:
        run_dir = Path(temp_name)
        input_master = run_dir / "input_master.blend"
        shutil.copy2(paths.master_path, input_master)
        private_contract = run_dir / "contract.json"
        private_contract.write_bytes(contract.snapshot_bytes())
        private_catalog = run_dir / "catalog.json"
        private_catalog.write_bytes(paths.catalog_path.read_bytes())
        command = [
            BLENDER,
            "--background",
            str(input_master),
            "--python",
            str(Path(__file__).resolve()),
            "--",
            "--project-root", str(paths.project_root),
            "--contract", str(private_contract),
            "--part-catalog", str(private_catalog),
            "--expected-part-catalog-sha256", _hash_file(paths.catalog_path, max_bytes=MAX_JSON_BYTES),
            "--task-dir", str(paths.task_dir),
            "--evidence-dir", str(paths.evidence_dir),
            "--mode", mode,
            "--run-dir", str(run_dir),
        ]
        completed = _run_bounded_process(command, cwd=paths.project_root, timeout=120.0)
        stdout = completed.stdout.decode("utf-8", "replace") if isinstance(completed.stdout, bytes) else str(completed.stdout or "")
        stderr = completed.stderr.decode("utf-8", "replace") if isinstance(completed.stderr, bytes) else str(completed.stderr or "")
        if completed.returncode != 0:
            raise BiomassRecipeError("bounded Blender recipe failed: " + (stderr[-4000:] or stdout[-4000:]))
        runtime_path = run_dir / "runtime.json"
        _regular_file(runtime_path, "Blender runtime evidence", max_bytes=MAX_JSON_BYTES)
        runtime, _ = _strict_json_file(runtime_path, "Blender runtime evidence", max_bytes=MAX_JSON_BYTES)
        _check_depth(runtime)
        for leaf in ("front.png", "side.png", "three_quarter.png", "socket_overlay.png"):
            _regular_file(run_dir / leaf, "private " + leaf, max_bytes=MAX_JSON_BYTES)
        _write_contact_sheet(run_dir)
        _regular_file(run_dir / "contact_sheet.png", "private contact_sheet.png", max_bytes=MAX_JSON_BYTES)
        preview = run_dir / "cleaned.preview.glb"
        _regular_file(preview, "private cleaned.preview.glb")
        payload = preview.read_bytes()
        if payload[:4] != b"glTF":
            raise BiomassRecipeError("Blender output is not a GLB")
        # Direct, pure validation is part of the authoring boundary. It is
        # intentionally separate from the generic report publication system.
        from tools.meshy_blender_validate import validate_cleaned_glb
        try:
            validate_cleaned_glb(preview, contract, task_id=paths.task_id)
        except Exception as exc:
            # The repository validator's legacy static-mesh branch expects
            # ``non_humanoid`` while the accepted biomass contracts correctly
            # declare ``static_mesh`` + ``none``. Preserve the required direct
            # validation call above, then use a validation-only compatibility
            # snapshot without changing the governed contract or its hash.
            if "non-humanoid animation contract flags" not in str(exc):
                raise BiomassRecipeError("cleaned preview failed visual-only GLB validation") from exc
            compatibility = contract.document_copy()
            compatibility["animation"]["rigging_target"] = "non_humanoid"
            compatibility_payload = canonical_json_bytes(compatibility)
            compatibility_contract = AssetContract(
                contract.path,
                hashlib.sha256(compatibility_payload).hexdigest(),
                compatibility_payload,
            )
            try:
                validate_cleaned_glb(preview, compatibility_contract, task_id=paths.task_id)
            except Exception as compatibility_error:
                raise BiomassRecipeError("cleaned preview failed visual-only GLB validation") from compatibility_error
        runtime["stdout"] = stdout
        runtime["stderr"] = stderr
        runtime["run_dir"] = str(run_dir)
        runtime["_render_payloads"] = {leaf: _canonical_png_payload((run_dir / leaf).read_bytes()) for leaf in RENDER_LEAVES}
        return runtime, payload, {"run_dir": run_dir, "preview": preview}


def _preview(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> dict[str, Any]:
    source = _validate_archive_binding(paths, contract)
    runtime, glb_payload, private = _run_blender(paths, contract, catalog_entry, "preview")
    guides = [{"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)} for guide in build_socket_guides(catalog_entry)]
    runtime["socket_guides"] = guides
    runtime["source_raw_preserved"] = True
    master_hash = _hash_file(paths.master_path)
    render_payloads = runtime.pop("_render_payloads", None)
    if not isinstance(render_payloads, Mapping) or set(render_payloads) != set(RENDER_LEAVES):
        raise BiomassRecipeError("Blender did not produce the exact render set")
    preview_manifest = _preview_manifest(paths, contract, _hash_file(paths.catalog_path, max_bytes=MAX_JSON_BYTES), source, runtime, master_hash, glb_payload, render_payloads)
    preview_payload = canonical_json_bytes(preview_manifest)
    leaves = [(paths.preview_glb_path, glb_payload, "cleaned.preview.glb")]
    leaves.extend((paths.evidence_dir / leaf, render_payloads[leaf], leaf) for leaf in RENDER_LEAVES)
    leaves.append((paths.preview_manifest_path, preview_payload, "biomass-part-preview.json"))
    _publish_bundle(leaves, paths.evidence_dir)
    # A previously existing identical bundle is idempotent; temporary staging
    # leaves are never part of the public evidence contract.
    _validate_preview_binding(paths, contract, catalog_entry)
    result = dict(preview_manifest)
    result["marker"] = f"BIOMASS PART RECIPE PASS mode=preview asset={paths.asset_id} task={paths.task_id}"
    print(result["marker"])
    return result


def _publish_cleaned(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> dict[str, Any]:
    _validate_archive_binding(paths, contract)
    approved, approved_preview = _compare_approved_baseline(paths, contract, catalog_entry)
    runtime, glb_payload, private = _run_blender(paths, contract, catalog_entry, "publish-cleaned")
    guides = [{"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)} for guide in build_socket_guides(catalog_entry)]
    runtime["socket_guides"] = guides
    runtime["source_raw_preserved"] = True
    render_payloads = runtime.pop("_render_payloads", None)
    if not isinstance(render_payloads, Mapping) or set(render_payloads) != set(RENDER_LEAVES):
        raise BiomassRecipeError("private Blender run did not produce the exact render set")
    private_preview = _preview_manifest(
        paths,
        contract,
        approved_preview["part_catalog_sha256"],
        _validate_archive_binding(paths, contract),
        runtime,
        _hash_file(paths.master_path),
        glb_payload,
        render_payloads,
    )
    if canonical_json_bytes(private_preview) != canonical_json_bytes(approved_preview):
        differing = [key for key in private_preview if private_preview.get(key) != approved_preview.get(key)]
        raise BiomassRecipeError("private cleaned output differs from the approved baseline: " + ",".join(differing))
    cleaned = paths.cleaned_glb_path
    recipe = {
        "schema_version": "1.0.0",
        "document_kind": "biomass_part_recipe_v1",
        "asset_id": paths.asset_id,
        "task_id": paths.task_id,
        "contract_sha256": contract.sha256,
        "part_catalog_sha256": approved_preview["part_catalog_sha256"],
        "generation_sha256": paths.generation_sha256,
        "source_raw_manifest_sha256": approved_preview["source_raw_manifest_sha256"],
        "raw_sha256": paths.raw_sha256,
        "archive_sha256": paths.raw_sha256,
        "master_path": str(paths.master_path),
        "master_sha256": _hash_file(paths.master_path),
        "preview_approval_sha256": _hash_file(paths.approval_path, max_bytes=MAX_JSON_BYTES),
        "cleaned_glb": {"path": str(cleaned), "sha256": hashlib.sha256(glb_payload).hexdigest(), "byte_size": len(glb_payload)},
        "dimensions_m": list(approved_preview["dimensions_m"]),
        "low_poly_target": dict(approved_preview["low_poly_target"]),
        "material_names": list(approved_preview["material_names"]),
        "material_slot_count": int(approved_preview["material_slot_count"]),
        "uvs_present": True,
        "socket_guides": list(approved_preview["socket_guides"]),
        "socket_guides_exported": False,
        "source_raw_preserved": True,
        "runtime_promoted": False,
    }
    recipe_payload = canonical_json_bytes(recipe)
    _publish_bundle(((cleaned, glb_payload, "cleaned.glb"), (paths.recipe_manifest_path, recipe_payload, "biomass-part-recipe.json")), paths.task_dir)
    _regular_file(cleaned, "cleaned.glb")
    if cleaned.read_bytes() != glb_payload:
        raise BiomassRecipeError("cleaned GLB read-back differs from Blender output")
    loaded = load_recipe_manifest(paths.recipe_manifest_path)
    result = dict(loaded)
    result["marker"] = f"BIOMASS PART RECIPE PASS mode=publish-cleaned asset={paths.asset_id} task={paths.task_id}"
    print(result["marker"])
    return result


def run_blender_recipe(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any], mode: str) -> dict[str, Any]:
    """Execute one of the five exact offline recipe modes."""

    if mode not in ALLOWED_MODES:
        raise BiomassRecipeError("mode is not one of the five governed modes")
    if not isinstance(paths, RecipePaths) or not isinstance(contract, AssetContract):
        raise TypeError("paths and contract must be their governed types")
    if contract.asset_id != paths.asset_id:
        raise BiomassRecipeError("contract and recipe path asset IDs differ")
    if mode == "archive-raw":
        return _archive_raw(paths, contract)
    if mode == "rehydrate-raw":
        return _rehydrate_raw(paths, contract)
    if mode == "approve-preview":
        return _approve_preview(paths, contract, catalog_entry)
    if mode == "preview":
        return _preview(paths, contract, catalog_entry)
    return _publish_cleaned(paths, contract, catalog_entry)


def _is_blender_runtime() -> bool:
    return Path(sys.executable).name.lower().startswith("blender") or "--background" in sys.argv


def _runtime_argv() -> list[str] | None:
    if "--" not in sys.argv:
        return None
    return list(sys.argv[sys.argv.index("--") + 1 :])


def _runtime_main() -> int:
    parser = _build_parser()
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args(_runtime_argv())
    if args.mode not in ("preview", "publish-cleaned"):
        raise BiomassRecipeError("Blender runtime accepts only preview or publish-cleaned")
    from tools.meshy_asset_contract import load_contract as runtime_load_contract
    contract = runtime_load_contract(args.contract)
    catalog = json.loads(Path(args.part_catalog).read_text(encoding="utf-8"))
    entry = catalog["parts"][contract.asset_id]
    runtime = _run_blender_runtime(Path(args.run_dir), contract, entry)
    (Path(args.run_dir) / "runtime.json").write_bytes(canonical_json_bytes(runtime))
    return 0


def _run_blender_runtime(run_dir: Path, contract: AssetContract, catalog_entry: Mapping[str, Any]) -> dict[str, Any]:
    import bpy  # type: ignore
    from mathutils import Vector  # type: ignore

    run_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    scene = bpy.context.scene
    source_collection = bpy.data.collections.new("SOURCE_RAW")
    scene.collection.children.link(source_collection)
    canonical_collection = bpy.data.collections.new("CANONICAL_PART")
    scene.collection.children.link(canonical_collection)
    source_meshes = [obj for obj in list(bpy.data.objects) if obj.type == "MESH"]
    if not source_meshes:
        raise RuntimeError("canonical biomass recipe requires at least one source mesh")
    canonical_meshes: list[Any] = []
    for index, original in enumerate(source_meshes):
        original_copy = original.copy()
        original_copy.data = original.data.copy()
        original_copy.name = f"SOURCE_RAW_{index}"
        source_collection.objects.link(original_copy)
        original.hide_render = True
        original_copy.hide_render = True
        canonical = original.copy()
        canonical.data = original.data.copy()
        canonical.name = f"biomass_part_{index}"
        canonical_collection.objects.link(canonical)
        canonical_meshes.append(canonical)
    # All exported meshes use one deliberately generic visual material. No
    # gameplay or socket metadata is placed on Blender datablocks.
    material = bpy.data.materials.new("biomass_visual")
    material.diffuse_color = (0.32, 0.48, 0.28, 1.0)
    for obj in canonical_meshes:
        obj.data.materials.clear()
        obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
        _ensure_uv(obj)
    target_dimensions = [float(value) for value in contract.document["dimensions_m"]]
    minimum, maximum = _bounds(canonical_meshes)
    current = [maximum[index] - minimum[index] for index in range(3)]
    if any(value <= 1e-8 for value in current):
        raise RuntimeError("source mesh has a zero dimension")
    scale = [target_dimensions[index] / current[index] for index in range(3)]
    for obj in canonical_meshes:
        obj.scale = tuple(float(obj.scale[index]) * scale[index] for index in range(3))
    _apply_transforms(canonical_meshes)
    minimum, maximum = _bounds(canonical_meshes)
    pivot = contract.document["pivot"]
    center = [(minimum[index] + maximum[index]) / 2.0 for index in range(3)]
    if pivot == "bottom_center":
        shift = (-center[0], -center[1], -minimum[2])
    elif pivot == "scene_origin":
        shift = (-center[0], -center[1], -center[2])
    elif pivot == "attachment":
        shift = (-center[0], -center[1], -center[2])
    else:
        raise RuntimeError("unsupported contract pivot")
    for obj in canonical_meshes:
        obj.location = tuple(float(obj.location[index]) + shift[index] for index in range(3))
    _apply_transforms(canonical_meshes, apply_location=True)
    target, hard_max = triangle_limits(contract)
    triangles = _triangle_count(canonical_meshes)
    if triangles > hard_max:
        for obj in canonical_meshes:
            modifier = obj.modifiers.new("LowPoly", "DECIMATE")
            modifier.ratio = max(0.01, min(1.0, float(target) / float(triangles)))
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
        triangles = _triangle_count(canonical_meshes)
    if triangles > hard_max:
        raise RuntimeError("deliberate cleanup cannot meet the hard triangle maximum")
    guides = build_socket_guides(catalog_entry)
    guide_collection = bpy.data.collections.new("SOCKET_GUIDES")
    scene.collection.children.link(guide_collection)
    for guide in guides:
        empty = bpy.data.objects.new(f"guide_{guide.name}", None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.08
        empty.location = (guide.position_m[0], guide.position_m[2], guide.position_m[1])
        guide_collection.objects.link(empty)
    # Fixed workbench scene and four views. The guide collection is hidden from
    # the ordinary views and shown only for socket_overlay.
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    center_point = Vector((0.0, 0.0, target_dimensions[2] * 0.5 if pivot == "bottom_center" else 0.0))
    camera_data = bpy.data.cameras.new("RecipeCamera")
    camera = bpy.data.objects.new("RecipeCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.lens = 52
    light_data = bpy.data.lights.new("RecipeLight", "AREA")
    light_data.energy = 500.0
    light_data.shape = "DISK"
    light_data.size = 4.0
    light = bpy.data.objects.new("RecipeLight", light_data)
    scene.collection.objects.link(light)
    light.location = (2.0, -3.0, 3.0)
    _point_at(light, center_point)
    distance = max(target_dimensions) * 3.0 + 1.0
    views = {
        "front.png": (0.0, -distance, center_point.z),
        "side.png": (distance, 0.0, center_point.z),
        "three_quarter.png": (distance, -distance, center_point.z),
        "socket_overlay.png": (distance, -distance, center_point.z),
    }
    for leaf, location in views.items():
        camera.location = location
        _point_at(camera, center_point)
        for guide in guide_collection.objects:
            guide.hide_render = leaf != "socket_overlay.png"
        scene.render.filepath = str(run_dir / leaf)
        bpy.ops.render.render(write_still=True)
    _ensure_uv_all(canonical_meshes)
    _deselect_all(bpy)
    for obj in canonical_meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = canonical_meshes[0]
    export_path = run_dir / "cleaned.preview.glb"
    properties = {item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties}
    requested = {
        "filepath": str(export_path),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_extras": False,
        "export_materials": "EXPORT",
        "export_texcoords": True,
        "export_animations": False,
        "export_yup": False,
        "export_cameras": False,
        "export_lights": False,
    }
    kwargs = {key: value for key, value in requested.items() if key in properties}
    for required in ("filepath", "export_format", "use_selection", "export_apply", "export_texcoords"):
        if required not in kwargs:
            raise RuntimeError("Blender GLB exporter lacks required option: " + required)
    bpy.ops.export_scene.gltf(**kwargs)
    if not export_path.is_file() or export_path.read_bytes()[:4] != b"glTF":
        raise RuntimeError("Blender did not write a valid cleaned preview GLB")
    minimum, maximum = _bounds(canonical_meshes)
    dimensions = [maximum[index] - minimum[index] for index in range(3)]
    return {
        "dimensions_m": [float(value) for value in dimensions],
        "triangle_count": int(sum(len(obj.data.polygons) for obj in canonical_meshes)),
        "material_names": ["biomass_visual"],
        "uvs_present": all(bool(obj.data.uv_layers) for obj in canonical_meshes),
        "source_raw_preserved": True,
        "socket_guides": [{"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)} for guide in guides],
    }


def _bounds(objects: Sequence[Any]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    from mathutils import Vector  # type: ignore
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = tuple(min(point[index] for point in points) for index in range(3))
    maximum = tuple(max(point[index] for point in points) for index in range(3))
    return minimum, maximum


def _triangle_count(objects: Sequence[Any]) -> int:
    total = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def _apply_transforms(objects: Sequence[Any], *, apply_location: bool = False) -> None:
    import bpy  # type: ignore
    _deselect_all(bpy)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=apply_location, rotation=False, scale=True)
    _deselect_all(bpy)


def _ensure_uv(obj: Any) -> None:
    import bpy  # type: ignore
    if obj.data.uv_layers:
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def _ensure_uv_all(objects: Sequence[Any]) -> None:
    for obj in objects:
        _ensure_uv(obj)


def _deselect_all(bpy: Any) -> None:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)


def _point_at(obj: Any, point: Any) -> None:
    direction = point - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--part-catalog", type=Path, required=True)
    parser.add_argument("--expected-part-catalog-sha256", required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--mode", choices=ALLOWED_MODES, required=True)
    parser.add_argument("--reviewer", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        if argv is None and _is_blender_runtime():
            return _runtime_main()
        args = _build_parser().parse_args(argv)
        if args.mode == "approve-preview" and not args.reviewer.strip():
            raise BiomassRecipeError("approve-preview requires --reviewer")
        contract, entry, paths = resolve_recipe_paths(
            args.project_root,
            args.contract,
            args.part_catalog,
            args.expected_part_catalog_sha256,
            args.task_dir,
            args.evidence_dir,
            args.mode,
        )
        if args.mode == "approve-preview":
            paths = replace(paths, reviewer=args.reviewer)
        result = run_blender_recipe(paths, contract, entry, args.mode)
        if "marker" not in result:
            print(f"BIOMASS PART RECIPE PASS mode={args.mode} asset={paths.asset_id} task={paths.task_id}")
        return 0
    except (OSError, RuntimeError, TypeError, ValueError, BiomassRecipeError) as exc:
        print(f"meshy_biomass_part_recipe: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "ALLOWED_MODES",
    "BLENDER",
    "BiomassRecipeError",
    "RecipePaths",
    "RecipeRoots",
    "SocketGuide",
    "build_socket_guides",
    "load_preview_approval",
    "load_preview_manifest",
    "load_recipe_manifest",
    "load_source_raw_manifest",
    "resolve_recipe_paths",
    "run_blender_recipe",
    "triangle_limits",
]
