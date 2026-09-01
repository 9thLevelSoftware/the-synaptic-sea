#!/usr/bin/env python3
"""Host-safe paths and validation for the loot-container Blender recipe.

This module deliberately keeps Blender integration at the command boundary.  It
can be imported by host Python without importing ``bpy``; future Blender-only
authoring code must remain behind a lazy runtime import.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import re
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Union

from tools import meshy_governance as governance
from tools.meshy_asset_contract import AssetContract, load_contract

ASSET_ID = "loot_container_derelict_v1"
SELECTED_TASK_ID = "01a05dcb-fc3b-7418-b105-2170af354088"
BLENDER = "/opt/homebrew/bin/blender"
TRUSTED_MASTER_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source")
TRUSTED_EVIDENCE_ROOT = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1"
)
CANONICAL_MASTER_LEAF = "loot_container_derelict_v1_master.blend"
CANONICAL_MASTER_PATH = TRUSTED_MASTER_ROOT / ASSET_ID / CANONICAL_MASTER_LEAF
PROTECTED_REPO_PATHS = (
    Path("assets/imported"),
    Path("data/combat"),
    Path("data/props"),
    Path("scenes/wrappers"),
)

_MANIFEST_FIELDS = (
    "schema_version",
    "document_kind",
    "asset_id",
    "task_id",
    "contract_sha256",
    "raw_sha256",
    "master_path",
    "objects",
    "states",
    "hinge",
    "dimensions_m",
    "triangle_count",
    "materials",
    "uvs_present",
    "source_raw_preserved",
    "runtime_promoted",
    "renders",
)
_MANIFEST_OBJECTS = (
    "ContainerRoot",
    "ContainerBody",
    "HingePivot",
    "ContainerLid",
    "FrontHandle",
    "LatchLeft",
    "LatchRight",
    "LootVisual",
)
_MANIFEST_STATES = {"closed": 1, "open": 30, "looted": 60}
_MANIFEST_HINGE = {"axis": "X", "open_degrees": 105.0}
_MANIFEST_DIMENSIONS = (0.9, 0.55, 0.65)
_MANIFEST_MATERIALS = ("painted_ship_alloy", "warning_accent")
_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
_ALLOWED_MODES = frozenset(("preview", "publish-cleaned"))
_MAX_GLB_BYTES = 512 * 1024 * 1024

PathLike = Union[str, os.PathLike]


@dataclass(frozen=True)
class RecipePaths:
    project_root: Path
    task_dir: Path
    master_path: Path
    evidence_dir: Path
    scratch_glb: Path
    manifest_path: Path


@dataclass(frozen=True)
class PublishedArtifact:
    path: Path
    sha256: str
    byte_size: int


def _lexical_path(value: PathLike, base: Path | None = None) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = (base if base is not None else Path.cwd()) / path
    return Path(os.path.abspath(os.fspath(path)))


def _contained(root: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(root)
    except ValueError:
        return False
    return True


def _reject_symlink_components(path: Path, label: str) -> None:
    absolute = _lexical_path(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError(f"{label} could not be inspected") from exc
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"{label} contains a symlink component")


def _resolve_path(value: PathLike, base: Path | None = None) -> Path:
    return _lexical_path(value, base).resolve(strict=False)


def _validate_task_dir(project_root: Path, task_dir: PathLike) -> Path:
    try:
        task = governance.governed_task_path(
            project_root, task_dir, "Meshy loot-container task directory", allow_missing=False
        )
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ValueError(f"task directory is not governed: {exc}") from exc
    stage_root = project_root / governance.STAGING_RELATIVE
    _reject_symlink_components(stage_root, "Meshy staging root")
    _reject_symlink_components(task, "Meshy loot-container task directory")
    try:
        relative = task.relative_to(stage_root)
    except ValueError as exc:
        raise ValueError("task directory must be under Meshy staging") from exc
    if relative.parts != (ASSET_ID, SELECTED_TASK_ID):
        raise ValueError("task directory must be the exact selected loot-container task")
    return _resolve_path(task)


def _validate_evidence_dir(project_root: Path, evidence_dir: PathLike) -> Path:
    trusted_lexical = _lexical_path(TRUSTED_EVIDENCE_ROOT)
    evidence_lexical = _lexical_path(evidence_dir)
    _reject_symlink_components(trusted_lexical, "trusted evidence root")
    _reject_symlink_components(evidence_lexical, "evidence directory")
    trusted = trusted_lexical.resolve(strict=False)
    evidence = evidence_lexical.resolve(strict=False)
    if not _contained(trusted_lexical, evidence_lexical) or not _contained(trusted, evidence):
        raise ValueError("evidence directory must be under the trusted evidence root")
    if _contained(project_root, evidence_lexical) or _contained(project_root, evidence):
        raise ValueError("evidence directory must be outside the project root")
    return evidence


def _derive_master_path() -> Path:
    root = _lexical_path(TRUSTED_MASTER_ROOT)
    _reject_symlink_components(root, "trusted master root")
    candidate = root / ASSET_ID / CANONICAL_MASTER_LEAF
    if not _contained(root, candidate):  # pragma: no cover - fixed constants
        raise ValueError("canonical master path escapes the trusted master root")
    return _resolve_path(candidate)


def derive_recipe_paths(
    project_root: Path, task_dir: Path, evidence_dir: Path
) -> RecipePaths:
    """Derive governed, non-mutating paths for the selected recipe task."""

    project = governance.physical_project_root(project_root)
    task = _validate_task_dir(project, task_dir)
    evidence = _validate_evidence_dir(project, evidence_dir)
    return RecipePaths(
        project_root=project,
        task_dir=task,
        master_path=_derive_master_path(),
        evidence_dir=evidence,
        scratch_glb=evidence / "cleaned.preview.glb",
        manifest_path=evidence / "build_recipe_manifest.json",
    )


def _regular_file(path: Path, label: str, *, nonempty: bool = True) -> os.stat_result:
    try:
        info = os.lstat(path)
    except OSError as exc:
        raise ValueError(f"{label} could not be inspected") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValueError(f"{label} must be a regular file")
    if nonempty and info.st_size <= 0:
        raise ValueError(f"{label} must be non-empty")
    return info


def _load_governed_contract(project_root: Path, contract_path: PathLike) -> AssetContract:
    candidate = _lexical_path(contract_path, project_root)
    _reject_symlink_components(candidate, "contract")
    if not _contained(project_root, candidate):
        raise ValueError("contract must be inside the project root")
    _regular_file(candidate, "contract")
    try:
        return load_contract(candidate)
    except (OSError, TypeError, ValueError) as exc:
        raise ValueError(f"contract is invalid: {exc}") from exc


def _validate_raw_evidence(paths: RecipePaths, generation: Mapping[str, Any]) -> None:
    raw_path = paths.task_dir / "raw.glb"
    raw_info = _regular_file(raw_path, "task-local raw.glb")
    if raw_info.st_size > _MAX_GLB_BYTES:
        raise ValueError("task-local raw.glb exceeds the size limit")
    try:
        raw_hash = governance.file_sha256(raw_path, max_bytes=_MAX_GLB_BYTES)
    except (OSError, TypeError, ValueError) as exc:
        raise ValueError("task-local raw.glb could not be hashed") from exc
    outputs = generation.get("outputs")
    raw_evidence = outputs.get("raw.glb") if isinstance(outputs, Mapping) else None
    if not isinstance(raw_evidence, Mapping):
        raise ValueError("generation evidence lacks raw.glb evidence")
    if raw_evidence.get("sha256") != raw_hash:
        raise ValueError("task-local raw.glb hash does not match generation evidence")
    if raw_evidence.get("byte_size") != raw_info.st_size:
        raise ValueError("task-local raw.glb size does not match generation evidence")


def resolve_recipe_paths(
    project_root: Path, contract_path: Path, task_dir: Path, evidence_dir: Path
) -> tuple[AssetContract, RecipePaths]:
    """Resolve the exact selected task and all governed recipe path inputs."""

    project = governance.physical_project_root(project_root)
    task = _validate_task_dir(project, task_dir)
    try:
        from tools import meshy_candidate_review as candidate_review

        review_path, review, generation, loaded_root, _asset_root = candidate_review._load_task_record(
            project, task
        )
    except Exception as exc:
        raise ValueError(f"candidate task is not fully governed: {exc}") from exc
    if loaded_root != project:
        raise ValueError("candidate task resolved to a different project root")
    if not isinstance(review, Mapping) or review.get("state") != "selected":
        raise ValueError("loot-container recipe requires a selected review")
    if not isinstance(generation, Mapping) or generation.get("status") != "SUCCEEDED":
        raise ValueError("loot-container recipe requires SUCCEEDED generation evidence")
    if review.get("asset_id") != ASSET_ID or generation.get("asset_id") != ASSET_ID:
        raise ValueError("candidate evidence asset identity does not match loot container")
    if review.get("task_id") != SELECTED_TASK_ID or generation.get("task_id") != SELECTED_TASK_ID:
        raise ValueError("candidate evidence task identity does not match selected task")

    contract = _load_governed_contract(project, contract_path)
    if contract.asset_id != ASSET_ID:
        raise ValueError("contract asset identity does not match loot container")
    if generation.get("contract_sha256") != contract.sha256:
        raise ValueError("contract hash does not match generation evidence")

    paths = derive_recipe_paths(project, Path(review_path).parent, evidence_dir)
    _validate_raw_evidence(paths, generation)
    _reject_symlink_components(_lexical_path(paths.master_path).parent.parent, "trusted master root")
    _regular_file(paths.master_path, "canonical Blender master")
    return contract, paths


def _check_hash(value: object, label: str, errors: list[str]) -> None:
    if not isinstance(value, str) or _HASH_RE.fullmatch(value) is None:
        errors.append(f"{label} must be a lowercase 64-character SHA-256 hash")


def validate_manifest_document(document: Mapping[str, Any]) -> list[str]:
    """Return deterministic diagnostics for the strict master manifest contract."""

    if not isinstance(document, Mapping):
        return ["manifest must be an object"]
    errors: list[str] = []
    actual = set(document)
    expected = set(_MANIFEST_FIELDS)
    for field in sorted(expected - actual):
        errors.append(f"missing top-level field: {field}")
    for field in sorted(actual - expected, key=str):
        errors.append(f"unknown top-level field: {field}")
    if errors:
        # Continue checking present fields so callers receive deterministic,
        # useful diagnostics for malformed documents with several defects.
        pass

    if document.get("schema_version") != "1.0.0":
        errors.append("schema_version must be 1.0.0")
    if document.get("document_kind") != "loot_container_master_recipe":
        errors.append("document_kind must be loot_container_master_recipe")
    if document.get("asset_id") != ASSET_ID:
        errors.append("asset_id must be loot_container_derelict_v1")
    if document.get("task_id") != SELECTED_TASK_ID:
        errors.append("task_id must be the exact selected task")
    _check_hash(document.get("contract_sha256"), "contract_sha256", errors)
    _check_hash(document.get("raw_sha256"), "raw_sha256", errors)

    expected_master = str(_derive_master_path())
    if document.get("master_path") != expected_master:
        errors.append("master_path must be the canonical external Blender master")

    objects = document.get("objects")
    if objects != list(_MANIFEST_OBJECTS):
        errors.append("objects must equal the canonical loot-container object list")
    states = document.get("states")
    if states != _MANIFEST_STATES:
        errors.append("states must equal closed=1, open=30, looted=60")
    hinge = document.get("hinge")
    if hinge != _MANIFEST_HINGE:
        errors.append("hinge must use axis X and open_degrees 105.0")

    dimensions = document.get("dimensions_m")
    if not (
        isinstance(dimensions, list)
        and len(dimensions) == 3
        and all(
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and math.isfinite(float(value))
            for value in dimensions
        )
        and all(
            abs(float(value) - expected_value) <= 0.01 + 1e-12
            for value, expected_value in zip(dimensions, _MANIFEST_DIMENSIONS)
        )
    ):
        errors.append("dimensions_m must be within 0.01 m of [0.9, 0.55, 0.65]")

    triangles = document.get("triangle_count")
    if not isinstance(triangles, int) or isinstance(triangles, bool) or not 0 <= triangles <= 3000:
        errors.append("triangle_count must be an integer from 0 through 3000")

    materials = document.get("materials")
    if not (
        isinstance(materials, list)
        and 1 <= len(materials) <= 2
        and materials == list(dict.fromkeys(materials))
        and all(isinstance(name, str) and name in _MANIFEST_MATERIALS for name in materials)
        and materials == sorted(materials, key=_MANIFEST_MATERIALS.index)
    ):
        errors.append("materials must contain one or both permitted names in canonical order")

    if document.get("uvs_present") is not True:
        errors.append("uvs_present must be true")
    if document.get("source_raw_preserved") is not True:
        errors.append("source_raw_preserved must be true")
    if document.get("runtime_promoted") is not False:
        errors.append("runtime_promoted must be false")

    renders = document.get("renders")
    if not isinstance(renders, Mapping):
        errors.append("renders must be a mapping")
    elif any(not isinstance(key, str) or not key for key in renders):
        errors.append("renders mapping keys must be non-empty strings")
    return sorted(set(errors))


def build_blender_command(paths: RecipePaths, contract_path: Path, mode: str) -> list[str]:
    """Build the exact host-to-Blender argv without launching or mutating Blender."""

    if mode not in _ALLOWED_MODES:
        raise ValueError("mode must be preview or publish-cleaned")
    if not isinstance(paths, RecipePaths):
        raise TypeError("paths must be a RecipePaths instance")
    return [
        BLENDER,
        "--background",
        str(paths.master_path),
        "--python",
        str(Path(__file__).resolve()),
        "--",
        "--project-root",
        str(paths.project_root),
        "--contract",
        str(Path(contract_path)),
        "--task-dir",
        str(paths.task_dir),
        "--evidence-dir",
        str(paths.evidence_dir),
        "--mode",
        mode,
    ]


def publish_cleaned(source_glb: Path, destination: Path, allowed_root: Path) -> PublishedArtifact:
    """Exclusively publish a cleaned GLB, allowing only identical idempotency."""

    source = Path(source_glb)
    _regular_file(source, "source GLB")
    if source.stat().st_size > _MAX_GLB_BYTES:
        raise ValueError("source GLB exceeds the size limit")
    try:
        payload = source.read_bytes()
    except OSError as exc:
        raise ValueError("source GLB could not be read") from exc
    if not payload:
        raise ValueError("source GLB must be non-empty")
    digest = hashlib.sha256(payload).hexdigest()
    size = len(payload)

    root = _resolve_path(allowed_root)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("allowed root must be a regular directory")
    _reject_symlink_components(root, "allowed root")
    target = _lexical_path(destination)
    _reject_symlink_components(target, "cleaned GLB destination")
    resolved_target = target.resolve(strict=False)
    if not _contained(root, target) or not _contained(root, resolved_target):
        raise ValueError("cleaned GLB destination must be within the allowed root")
    if target == root or target.name in ("", ".", ".."):
        raise ValueError("cleaned GLB destination must be a file")

    if os.path.lexists(target):
        info = _regular_file(target, "existing cleaned GLB")
        try:
            existing_hash = governance.file_sha256(target, max_bytes=_MAX_GLB_BYTES)
        except (OSError, TypeError, ValueError) as exc:
            raise ValueError("existing cleaned GLB could not be hashed") from exc
        if existing_hash != digest or info.st_size != size:
            raise ValueError("existing cleaned GLB does not match source")
        return PublishedArtifact(target, digest, size)

    try:
        governance.atomic_create_bytes(
            target,
            payload,
            project_root=root,
            allowed_root=root,
            mode=0o600,
        )
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ValueError(f"cleaned GLB publication failed: {exc}") from exc

    published_info = _regular_file(target, "published cleaned GLB")
    if published_info.st_size != size:
        raise ValueError("published cleaned GLB size does not match source")
    try:
        published_hash = governance.file_sha256(target, max_bytes=_MAX_GLB_BYTES)
    except (OSError, TypeError, ValueError) as exc:
        raise ValueError("published cleaned GLB could not be verified") from exc
    if published_hash != digest:
        raise ValueError("published cleaned GLB hash does not match source")
    return PublishedArtifact(target, digest, size)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--mode", choices=sorted(_ALLOWED_MODES), required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        contract, paths = resolve_recipe_paths(
            args.project_root, args.contract, args.task_dir, args.evidence_dir
        )
        if args.mode == "preview":
            print("MESHY LOOT CONTAINER RECIPE PREVIEW", contract.asset_id)
            return 0
        print(
            "publish-cleaned is recognized but live GLB publication is deferred in Task 1",
            file=os.sys.stderr,
        )
        return 2
    except (OSError, TypeError, ValueError) as exc:
        print(f"meshy_loot_container_recipe: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "ASSET_ID",
    "BLENDER",
    "CANONICAL_MASTER_LEAF",
    "CANONICAL_MASTER_PATH",
    "PROTECTED_REPO_PATHS",
    "PublishedArtifact",
    "RecipePaths",
    "SELECTED_TASK_ID",
    "TRUSTED_EVIDENCE_ROOT",
    "TRUSTED_MASTER_ROOT",
    "build_blender_command",
    "derive_recipe_paths",
    "main",
    "publish_cleaned",
    "resolve_recipe_paths",
    "validate_manifest_document",
]
