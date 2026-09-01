#!/usr/bin/env python3
"""Host-safe paths and validation for the loot-container Blender recipe.

This module deliberately keeps Blender integration at the command boundary.  It
can be imported by host Python without importing ``bpy``; future Blender-only
authoring code must remain behind a lazy runtime import.
"""

from __future__ import annotations

import argparse
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
from typing import Any, Collection, Mapping, Union

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools import meshy_governance as governance
from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract

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
EXPORT_OBJECT_NAMES = (
    "ContainerRoot",
    "ContainerBody",
    "HingePivot",
    "ContainerLid",
    "FrontHandle",
    "LatchLeft",
    "LatchRight",
    "LootVisual",
)
_BOX_PART_NAMES = (
    "BodyFloor",
    "BodyFront",
    "BodyRear",
    "BodyLeft",
    "BodyRight",
    "LidTop",
    "LidFront",
    "LidRear",
    "LidLeft",
    "LidRight",
    "HandleLeft",
    "HandleRight",
    "HandleGrip",
)
_RECIPE_OWNER_KEY = "meshy_recipe_owner"
_RECIPE_OWNER_VALUE = ASSET_ID
RENDER_LEAVES = ("closed.png", "open.png", "looted.png", "states_contact_sheet.png")
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


def validate_manifest_document(
    document: Mapping[str, Any], expected_master_path: PathLike | None = None
) -> list[str]:
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

    expected_master = str(
        _derive_master_path() if expected_master_path is None else _lexical_path(expected_master_path)
    )
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


def validate_functional_evidence(evidence: Mapping[str, Any]) -> list[str]:
    """Validate the small runtime inventory used to bind the one-state recipe."""

    errors: list[str] = []
    actions = evidence.get("action_names") if isinstance(evidence, Mapping) else None
    if actions != ["lid_open"]:
        errors.append("action_names must contain exactly one lid_open action")
    objects = evidence.get("state_mesh_names") if isinstance(evidence, Mapping) else None
    if objects != list(EXPORT_OBJECT_NAMES):
        errors.append("state meshes must equal the functional export hierarchy without duplicates")
    if isinstance(objects, list) and len(objects) != len(set(objects)):
        errors.append("state meshes must not contain duplicates")
    return sorted(set(errors))


def _require_finished(result: Any, label: str) -> None:
    try:
        values = set(result)
    except TypeError:
        values = {str(result)}
    if "FINISHED" not in values or "CANCELLED" in values or "ERROR" in values:
        raise RuntimeError("Blender operator did not finish: {0} result={1!r}".format(label, values))


def _ensure_collection(bpy: Any, scene: Any, name: str) -> Any:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if scene.collection.children.get(name) is None:
        scene.collection.children.link(collection)
    return collection


def _link_only(obj: Any, collection: Any) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def _recipe_owned(datablock: Any) -> bool:
    return datablock.get(_RECIPE_OWNER_KEY) == _RECIPE_OWNER_VALUE


def _mark_recipe_owned(datablock: Any) -> Any:
    datablock[_RECIPE_OWNER_KEY] = _RECIPE_OWNER_VALUE
    return datablock


def _matches_generated_name(name: str, canonical_names: Collection[str]) -> bool:
    if name in canonical_names:
        return True
    base, separator, suffix = name.rpartition(".")
    return separator == "." and len(suffix) >= 3 and suffix.isdigit() and base in canonical_names


def _preflight_generated_name_collisions(bpy: Any) -> None:
    generated = (
        ("object", bpy.data.objects, set(EXPORT_OBJECT_NAMES) | set(_BOX_PART_NAMES) | {"RecipeCamera", "RecipeStudioLight"}),
        ("action", bpy.data.actions, {"lid_open"}),
        ("material", bpy.data.materials, set(_MANIFEST_MATERIALS)),
        ("camera", bpy.data.cameras, {"RecipeCamera"}),
        ("light", bpy.data.lights, {"RecipeStudioLight"}),
    )
    collisions = [
        "{0} {1} is not recipe-owned".format(kind, datablock.name)
        for kind, datablocks, names in generated
        for datablock in datablocks
        if _matches_generated_name(datablock.name, names) and not _recipe_owned(datablock)
    ]
    if collisions:
        raise RuntimeError("generated-name collision: " + "; ".join(sorted(collisions)))


def _remove_owned_objects(bpy: Any) -> None:
    scaffold_data: list[tuple[str, Any]] = []
    for obj in list(bpy.data.objects):
        is_scaffold = obj.name == "mesh_node_WORKING"
        if not is_scaffold and not _recipe_owned(obj):
            continue
        obj_type = obj.type
        data = obj.data if obj_type in {"MESH", "CAMERA", "LIGHT"} else None
        if is_scaffold and data is not None:
            scaffold_data.append((obj_type, data))
        bpy.data.objects.remove(obj, do_unlink=True)

    for obj_type, data in scaffold_data:
        if data.users != 0:
            continue
        if obj_type == "MESH":
            bpy.data.meshes.remove(data)
        elif obj_type == "CAMERA":
            bpy.data.cameras.remove(data)
        elif obj_type == "LIGHT":
            bpy.data.lights.remove(data)

    for datablocks in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if _recipe_owned(datablock) and datablock.users == 0:
                datablocks.remove(datablock)
    for action in list(bpy.data.actions):
        if _recipe_owned(action):
            bpy.data.actions.remove(action)
    for material in list(bpy.data.materials):
        if _recipe_owned(material):
            bpy.data.materials.remove(material)


def _make_material(bpy: Any, name: str, color: tuple[float, float, float, float], metallic: float, roughness: float) -> Any:
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    _mark_recipe_owned(material)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node is None:
        raise RuntimeError("material has no Principled BSDF: " + name)
    node.inputs["Base Color"].default_value = color
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    return material


def _deselect_all(bpy: Any) -> None:
    for obj in tuple(bpy.context.selected_objects):
        obj.select_set(False)


def _add_box(bpy: Any, name: str, center: tuple[float, float, float], size: tuple[float, float, float], collection: Any, material: Any, bevel: float = 0.0) -> Any:
    _deselect_all(bpy)
    _require_finished(bpy.ops.mesh.primitive_cube_add(size=1.0, location=center), "add box " + name)
    obj = bpy.context.object
    _mark_recipe_owned(obj)
    _mark_recipe_owned(obj.data)
    obj.name = name
    obj.dimensions = size
    _require_finished(bpy.ops.object.transform_apply(location=False, rotation=False, scale=True), "apply box dimensions " + name)
    _link_only(obj, collection)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new(name="PurposefulEdgeBevel", type="BEVEL")
        modifier.width = min(float(bevel), 0.008)
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        _require_finished(bpy.ops.object.modifier_apply(modifier=modifier.name), "apply bevel " + name)
    return obj


def _join_as(bpy: Any, name: str, objects: list[Any]) -> Any:
    if not objects:
        raise RuntimeError("cannot join an empty object list")
    _deselect_all(bpy)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    _require_finished(bpy.ops.object.join(), "join " + name)
    objects[0].name = name
    _mark_recipe_owned(objects[0])
    _mark_recipe_owned(objects[0].data)
    return objects[0]


def _build_body(bpy: Any, collection: Any, alloy: Any) -> Any:
    parts = [
        _add_box(bpy, "BodyFloor", (0.0, 0.0, 0.035), (0.90, 0.55, 0.07), collection, alloy, 0.006),
        _add_box(bpy, "BodyFront", (0.0, -0.2625, 0.25), (0.90, 0.025, 0.36), collection, alloy, 0.006),
        _add_box(bpy, "BodyRear", (0.0, 0.2625, 0.25), (0.90, 0.025, 0.36), collection, alloy, 0.006),
        _add_box(bpy, "BodyLeft", (-0.4375, 0.0, 0.25), (0.025, 0.50, 0.36), collection, alloy, 0.006),
        _add_box(bpy, "BodyRight", (0.4375, 0.0, 0.25), (0.025, 0.50, 0.36), collection, alloy, 0.006),
    ]
    return _join_as(bpy, "ContainerBody", parts)


def _build_lid(bpy: Any, collection: Any, hinge: Any, alloy: Any) -> Any:
    parts = [
        _add_box(bpy, "LidTop", (0.0, 0.0, 0.60), (0.90, 0.55, 0.10), collection, alloy, 0.006),
        _add_box(bpy, "LidFront", (0.0, -0.2625, 0.49), (0.90, 0.025, 0.12), collection, alloy, 0.006),
        _add_box(bpy, "LidRear", (0.0, 0.2625, 0.49), (0.90, 0.025, 0.12), collection, alloy, 0.006),
        _add_box(bpy, "LidLeft", (-0.4375, 0.0, 0.49), (0.025, 0.50, 0.12), collection, alloy, 0.006),
        _add_box(bpy, "LidRight", (0.4375, 0.0, 0.49), (0.025, 0.50, 0.12), collection, alloy, 0.006),
    ]
    lid = _join_as(bpy, "ContainerLid", parts)
    lid.parent = hinge
    lid.matrix_parent_inverse = hinge.matrix_world.inverted()
    return lid


def _build_handle(bpy: Any, collection: Any, alloy: Any) -> Any:
    parts = [
        _add_box(bpy, "HandleLeft", (-0.19, -0.266, 0.29), (0.035, 0.018, 0.13), collection, alloy, 0.004),
        _add_box(bpy, "HandleRight", (0.19, -0.266, 0.29), (0.035, 0.018, 0.13), collection, alloy, 0.004),
        _add_box(bpy, "HandleGrip", (0.0, -0.266, 0.235), (0.38, 0.018, 0.035), collection, alloy, 0.004),
    ]
    return _join_as(bpy, "FrontHandle", parts)


def _build_accents(bpy: Any, collection: Any, accent: Any) -> tuple[Any, Any, Any]:
    left = _add_box(bpy, "LatchLeft", (-0.23, -0.272, 0.43), (0.07, 0.006, 0.14), collection, accent, 0.003)
    right = _add_box(bpy, "LatchRight", (0.23, -0.272, 0.43), (0.07, 0.006, 0.14), collection, accent, 0.003)
    loot = _add_box(bpy, "LootVisual", (0.0, 0.0, 0.12), (0.28, 0.18, 0.08), collection, accent, 0.004)
    loot["wrapper_visibility"] = "open_unlooted_only"
    return left, right, loot


def _unwrap_object(bpy: Any, obj: Any) -> None:
    _deselect_all(bpy)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    _require_finished(bpy.ops.object.mode_set(mode="EDIT"), "enter edit mode for UV unwrap")
    _require_finished(bpy.ops.mesh.select_all(action="SELECT"), "select mesh for UV unwrap")
    _require_finished(bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02), "smart project UVs")
    _require_finished(bpy.ops.uv.pack_islands(margin=0.02), "pack UVs")
    _require_finished(bpy.ops.object.mode_set(mode="OBJECT"), "leave edit mode for UV unwrap")
    obj.select_set(False)


def _build_animation(bpy: Any, hinge: Any, loot: Any, scene: Any) -> Any:
    action = bpy.data.actions.new("lid_open")
    _mark_recipe_owned(action)
    hinge.rotation_mode = "XYZ"
    hinge.animation_data_create()
    hinge.animation_data.action = action
    hinge.rotation_euler = (0.0, 0.0, 0.0)
    if not hinge.keyframe_insert(data_path="rotation_euler", index=0, frame=1):
        raise RuntimeError("could not keyframe closed hinge")
    hinge.rotation_euler.x = math.radians(-105.0)
    if not hinge.keyframe_insert(data_path="rotation_euler", index=0, frame=30):
        raise RuntimeError("could not keyframe open hinge")
    if not hinge.keyframe_insert(data_path="rotation_euler", index=0, frame=60):
        raise RuntimeError("could not keyframe looted hinge")

    # Blender 5.2 creates a second shared Action slot on the same Action when
    # the second owner is keyed; this keeps visibility and hinge channels in
    # exactly one lid_open Action.
    loot.animation_data_create()
    loot.animation_data.action = action
    loot.hide_render = True
    if not loot.keyframe_insert(data_path="hide_render", frame=1):
        raise RuntimeError("could not keyframe hidden loot")
    loot.hide_render = False
    if not loot.keyframe_insert(data_path="hide_render", frame=30):
        raise RuntimeError("could not keyframe visible loot")
    loot.hide_render = True
    if not loot.keyframe_insert(data_path="hide_render", frame=60):
        raise RuntimeError("could not keyframe hidden looted loot")
    scene.frame_set(1)
    return action


def _configure_preview_scene(bpy: Any, scene: Any, root: Any) -> None:
    camera_data = bpy.data.cameras.new("RecipeCamera")
    _mark_recipe_owned(camera_data)
    camera = bpy.data.objects.new("RecipeCamera", camera_data)
    _mark_recipe_owned(camera)
    scene.collection.objects.link(camera)
    camera.location = (1.35, -1.35, 1.05)
    target = (0.0, 0.0, 0.28)
    direction = __import__("mathutils").Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.22
    scene.camera = camera

    light_data = bpy.data.lights.new("RecipeStudioLight", type="AREA")
    _mark_recipe_owned(light_data)
    light = bpy.data.objects.new("RecipeStudioLight", light_data)
    _mark_recipe_owned(light)
    scene.collection.objects.link(light)
    light.location = (1.5, -2.0, 3.0)
    light_data.energy = 600.0
    light_data.size = 4.0

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.studio_light = "paint.sl"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.curvature_ridge_factor = 1.5
    shading.curvature_valley_factor = 1.0
    shading.show_specular_highlight = True
    if hasattr(shading, "background_type"):
        shading.background_type = "WORLD"
    scene.world.color = (0.035, 0.045, 0.055)
    scene.view_settings.view_transform = "Standard"
    try:
        scene.view_settings.look = "Medium High Contrast"
    except TypeError:
        scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.frame_start = 1
    scene.frame_end = 60
    scene.frame_set(1)


def _export_glb(bpy: Any, scene: Any, export_objects: list[Any], path: Path) -> None:
    _deselect_all(bpy)
    for obj in export_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objects[0]
    scene.frame_set(1)
    requested = {
        "filepath": str(path),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_extras": True,
        "export_materials": "EXPORT",
        "export_texcoords": True,
        "export_animations": True,
        "export_cameras": False,
        "export_lights": False,
        "export_current_frame": False,
        "export_frame_range": True,
    }
    supported = {item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kwargs = {key: value for key, value in requested.items() if key in supported}
    for required in ("filepath", "export_format", "use_selection", "export_apply", "export_extras", "export_materials", "export_texcoords", "export_animations"):
        if required not in kwargs:
            raise RuntimeError("Blender GLB exporter lacks required option: " + required)
    _require_finished(bpy.ops.export_scene.gltf(**kwargs), "selection-only GLB export")
    if not path.is_file() or path.stat().st_size <= 20 or path.read_bytes()[:4] != b"glTF":
        raise RuntimeError("Blender GLB export is stale, empty, or not GLB")


def _render_states(bpy: Any, scene: Any, run_dir: Path) -> None:
    for frame, leaf in ((1, "closed.png"), (30, "open.png"), (60, "looted.png")):
        scene.frame_set(frame)
        target = run_dir / leaf
        scene.render.filepath = str(target)
        _require_finished(bpy.ops.render.render(write_still=True), "render " + leaf)
        if not target.is_file() or target.stat().st_size <= 0 or target.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            raise RuntimeError("render output is stale or invalid: " + leaf)
    scene.frame_set(1)


def _mesh_triangles(obj: Any) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _bounds_for_meshes(mesh_objects: list[Any]) -> tuple[list[float], list[float]]:
    points: list[tuple[float, float, float]] = []
    for obj in mesh_objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ __import__("mathutils").Vector(corner)
            points.append((float(point.x), float(point.y), float(point.z)))
    if not points:
        raise RuntimeError("re-imported GLB has no mesh geometry")
    return [min(point[index] for point in points) for index in range(3)], [max(point[index] for point in points) for index in range(3)]


def _fresh_glb_evidence(bpy: Any, glb_path: Path, raw_preserved: bool) -> dict[str, Any]:
    _require_finished(bpy.ops.wm.read_factory_settings(use_empty=True), "fresh Blender scene for GLB re-import")
    _require_finished(bpy.ops.import_scene.gltf(filepath=str(glb_path)), "fresh GLB re-import")
    scene = bpy.context.scene
    scene.frame_set(1)
    objects = list(bpy.data.objects)
    mesh_objects = [obj for obj in objects if obj.type == "MESH"]
    minimum, maximum = _bounds_for_meshes(mesh_objects)
    dimensions = [maximum[index] - minimum[index] for index in range(3)]
    materials = sorted({material.name for obj in mesh_objects for material in obj.data.materials})
    uvs_present = bool(mesh_objects) and all(bool(obj.data.uv_layers) for obj in mesh_objects)
    triangles = sum(_mesh_triangles(obj) for obj in mesh_objects)
    action_names = sorted(action.name for action in bpy.data.actions)
    inventory = [name for name in EXPORT_OBJECT_NAMES if bpy.data.objects.get(name) is not None]
    root = bpy.data.objects.get("ContainerRoot")
    if root is None:
        raise RuntimeError("fresh GLB re-import has no ContainerRoot")
    return {
        "action_names": action_names,
        "state_mesh_names": inventory,
        "object_inventory": inventory,
        "triangle_count": triangles,
        "materials": materials,
        "uvs_present": uvs_present,
        "dimensions_m": dimensions,
        "root_location": [float(value) for value in root.location],
        "raw_preserved": bool(raw_preserved),
    }


def _run_blender_recipe_runtime(paths: RecipePaths, contract: AssetContract, run_dir: Path) -> dict[str, Any]:
    import bpy  # type: ignore

    scene = bpy.context.scene
    _preflight_generated_name_collisions(bpy)
    _remove_owned_objects(bpy)
    export_collection = _ensure_collection(bpy, scene, "EXPORT")
    source_raw = _ensure_collection(bpy, scene, "SOURCE_RAW")
    _ensure_collection(bpy, scene, "WORKING")
    _ensure_collection(bpy, scene, "SOCKETS_MARKERS")
    raw_preserved = bool(bpy.data.objects.get("mesh_node") and source_raw.objects.get("mesh_node"))
    marker_names = {obj.name for obj in bpy.data.objects if obj.name in {"ORIGIN_MARKER", "FORWARD_Z_MARKER", "OriginMarker", "ScaleMarker"}}
    raw_preserved = raw_preserved and bool(marker_names)

    alloy = _make_material(bpy, "painted_ship_alloy", (0.23, 0.29, 0.34, 1.0), 0.65, 0.48)
    accent = _make_material(bpy, "warning_accent", (0.65, 0.18, 0.06, 1.0), 0.4, 0.42)
    root = bpy.data.objects.new("ContainerRoot", None)
    _mark_recipe_owned(root)
    root.location = (0.0, 0.0, 0.0)
    export_collection.objects.link(root)
    root["required_states"] = "closed,open,looted"
    root["default_state"] = "closed"
    root["hinge_axis"] = "X"
    root["hinge_open_degrees"] = 105.0
    root["state_frames"] = "closed:1,open:30,looted:60"
    root["collision_owner"] = "godot_wrapper"
    root["source_provider"] = "meshy"
    root["source_task_id"] = SELECTED_TASK_ID

    hinge = bpy.data.objects.new("HingePivot", None)
    _mark_recipe_owned(hinge)
    hinge.location = (0.0, 0.245, 0.43)
    hinge.parent = root
    export_collection.objects.link(hinge)
    body = _build_body(bpy, export_collection, alloy)
    body.parent = root
    lid = _build_lid(bpy, export_collection, hinge, alloy)
    handle = _build_handle(bpy, export_collection, alloy)
    left, right, loot = _build_accents(bpy, export_collection, accent)
    for obj in (handle, left, right, loot):
        obj.parent = root
    meshes = [body, lid, handle, left, right, loot]
    for mesh in meshes:
        _unwrap_object(bpy, mesh)
    action = _build_animation(bpy, hinge, loot, scene)
    action_name = action.name
    _configure_preview_scene(bpy, scene, root)
    export_objects = [root, body, hinge, lid, handle, left, right, loot]
    if tuple(obj.name for obj in export_objects) != EXPORT_OBJECT_NAMES:
        raise RuntimeError("functional export hierarchy order drifted")
    _render_states(bpy, scene, run_dir)
    glb_path = run_dir / "cleaned.preview.glb"
    _export_glb(bpy, scene, export_objects, glb_path)
    scene.frame_set(1)
    updated_master = run_dir / "updated_master.blend"
    _require_finished(bpy.ops.wm.save_as_mainfile(filepath=str(updated_master)), "save updated Blender master")
    if not updated_master.is_file() or updated_master.stat().st_size <= 0:
        raise RuntimeError("updated Blender master was not saved")
    source_material_names = sorted((alloy.name, accent.name))
    source_master_inventory = sorted(obj.name for obj in bpy.data.objects)
    evidence = _fresh_glb_evidence(bpy, glb_path, raw_preserved)
    evidence["source_action_names"] = [action_name]
    evidence["source_materials"] = source_material_names
    evidence["master_object_inventory"] = source_master_inventory
    evidence_path = run_dir / "runtime_evidence.json"
    evidence_path.write_bytes(canonical_json_bytes(evidence))
    if not evidence_path.is_file():
        raise RuntimeError("runtime evidence was not written")
    print("BLENDER LOOT RECIPE RUNTIME PASS")
    return evidence


def _hash_decoded_rgba(path: Path) -> str:
    from PIL import Image

    with Image.open(path) as image:
        return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def _build_contact_sheet(run_dir: Path) -> None:
    from PIL import Image, ImageDraw, ImageFont

    images = []
    for leaf in ("closed.png", "open.png", "looted.png"):
        with Image.open(run_dir / leaf) as image:
            images.append(image.convert("RGBA"))
    label_height = 40
    sheet = Image.new("RGBA", (640 * 3, 640 + label_height), (22, 28, 34, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, (label, image) in enumerate(zip(("CLOSED", "OPEN", "LOOTED"), images)):
        x = index * 640
        sheet.paste(image, (x, label_height))
        draw.text((x + 12, 12), label, fill=(240, 240, 240, 255), font=font)
    sheet.save(run_dir / "states_contact_sheet.png", format="PNG", optimize=False, compress_level=6)


def _publish_leaf(path: Path, payload: bytes, label: str) -> None:
    parent = path.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    _reject_symlink_components(path, label)
    try:
        governance.atomic_write_bytes(path, payload, project_root=parent, allowed_root=parent, mode=0o600)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ValueError(label + " publication failed") from exc
    _regular_file(path, label)


def _source_manifest_path(paths: RecipePaths) -> Path:
    return paths.master_path.parent / "build_recipe_manifest.json"


def _validate_runtime_evidence(evidence: Mapping[str, Any]) -> None:
    errors = validate_functional_evidence(evidence)
    if evidence.get("object_inventory") != list(EXPORT_OBJECT_NAMES):
        errors.append("GLB object inventory is not the exact functional hierarchy")
    if evidence.get("triangle_count", 0) > 1500:
        errors.append("runtime triangle design target exceeded")
    if evidence.get("materials") != list(_MANIFEST_MATERIALS):
        errors.append("runtime material inventory is not the exact two-material set")
    if evidence.get("uvs_present") is not True:
        errors.append("runtime GLB UV evidence is missing")
    dimensions = evidence.get("dimensions_m")
    if not isinstance(dimensions, list) or len(dimensions) != 3 or any(abs(float(value) - expected) > 1e-5 for value, expected in zip(dimensions, _MANIFEST_DIMENSIONS)):
        errors.append("runtime default closed dimensions are not exact")
    if evidence.get("root_location") != [0.0, 0.0, 0.0]:
        errors.append("runtime root pivot is not bottom-center origin")
    if evidence.get("raw_preserved") is not True:
        errors.append("SOURCE_RAW or markers were not preserved")
    if errors:
        raise ValueError("; ".join(sorted(set(errors))))


def _validate_recipe_inputs(paths: RecipePaths, contract: AssetContract) -> str:
    if not isinstance(paths, RecipePaths):
        raise TypeError("paths must be a RecipePaths instance")
    if not isinstance(contract, AssetContract) or contract.asset_id != ASSET_ID:
        raise ValueError("contract must be the loot-container AssetContract")
    _regular_file(paths.master_path, "Blender master")
    raw_path = paths.task_dir / "raw.glb"
    _regular_file(raw_path, "task-local raw.glb")
    raw_hash = governance.file_sha256(raw_path, max_bytes=_MAX_GLB_BYTES)
    if not paths.evidence_dir.exists() or not paths.evidence_dir.is_dir() or paths.evidence_dir.is_symlink():
        raise ValueError("evidence directory must be an existing regular directory")
    _reject_symlink_components(paths.evidence_dir, "evidence directory")
    return raw_hash


def run_blender_recipe(paths: RecipePaths, contract: AssetContract, mode: str) -> dict[str, Any]:
    """Run the bounded Blender authoring process and publish deterministic evidence."""

    if mode not in _ALLOWED_MODES:
        raise ValueError("mode must be preview or publish-cleaned")
    raw_hash = _validate_recipe_inputs(paths, contract)
    from tools.meshy_blender_master import _run_bounded_process

    with tempfile.TemporaryDirectory(prefix=".meshy-loot-recipe-", dir=str(paths.evidence_dir)) as temporary:
        run_dir = Path(temporary)
        input_master = run_dir / "input_master.blend"
        shutil.copy2(paths.master_path, input_master)
        contract_path = run_dir / "contract.json"
        contract_path.write_bytes(contract.snapshot_bytes())
        runtime_paths = replace(paths, master_path=input_master)
        command = build_blender_command(runtime_paths, contract_path, mode) + ["--run-dir", str(run_dir)]
        completed = _run_bounded_process(command, cwd=paths.project_root, timeout=120.0)
        stdout = completed.stdout.decode("utf-8", "replace") if isinstance(completed.stdout, bytes) else str(completed.stdout or "")
        stderr = completed.stderr.decode("utf-8", "replace") if isinstance(completed.stderr, bytes) else str(completed.stderr or "")
        if completed.returncode != 0:
            raise RuntimeError("Blender recipe failed: " + (stderr[-4000:] or stdout[-4000:]))
        runtime_evidence_path = run_dir / "runtime_evidence.json"
        if not runtime_evidence_path.is_file():
            raise RuntimeError("Blender recipe did not produce runtime evidence: " + (stderr[-4000:] or stdout[-4000:]))
        evidence = json.loads(runtime_evidence_path.read_text(encoding="utf-8"))
        if not isinstance(evidence, dict):
            raise ValueError("runtime evidence must be an object")
        _validate_runtime_evidence(evidence)
        _build_contact_sheet(run_dir)
        for leaf in RENDER_LEAVES:
            _regular_file(run_dir / leaf, "private " + leaf)
        glb_path = run_dir / "cleaned.preview.glb"
        _regular_file(glb_path, "private scratch GLB")
        if glb_path.read_bytes()[:4] != b"glTF":
            raise ValueError("private scratch GLB is not GLB")
        master_copy = run_dir / "updated_master.blend"
        _regular_file(master_copy, "private updated Blender master")

        render_hashes = {leaf: _hash_decoded_rgba(run_dir / leaf) for leaf in RENDER_LEAVES}
        manifest = {
            "schema_version": "1.0.0",
            "document_kind": "loot_container_master_recipe",
            "asset_id": ASSET_ID,
            "task_id": SELECTED_TASK_ID,
            "contract_sha256": contract.sha256,
            "raw_sha256": raw_hash,
            "master_path": str(paths.master_path),
            "objects": list(EXPORT_OBJECT_NAMES),
            "states": dict(_MANIFEST_STATES),
            "hinge": dict(_MANIFEST_HINGE),
            "dimensions_m": [float(value) for value in evidence["dimensions_m"]],
            "triangle_count": int(evidence["triangle_count"]),
            "materials": list(evidence["materials"]),
            "uvs_present": bool(evidence["uvs_present"]),
            "source_raw_preserved": bool(evidence["raw_preserved"]),
            "runtime_promoted": False,
            "renders": render_hashes,
        }
        errors = validate_manifest_document(manifest, expected_master_path=paths.master_path)
        if errors:
            raise ValueError("manifest validation failed: " + "; ".join(errors))
        master_payload = master_copy.read_bytes()
        _publish_leaf(paths.master_path, master_payload, "updated Blender master")
        for leaf in RENDER_LEAVES:
            _publish_leaf(paths.evidence_dir / leaf, (run_dir / leaf).read_bytes(), leaf)
        _publish_leaf(paths.scratch_glb, glb_path.read_bytes(), "scratch GLB")
        manifest_payload = canonical_json_bytes(manifest)
        source_manifest = _source_manifest_path(paths)
        _publish_leaf(source_manifest, manifest_payload, "source recipe manifest")
        _publish_leaf(paths.manifest_path, manifest_payload, "evidence recipe manifest")
        print("LOOT CONTAINER RECIPE PASS mode={0} asset={1} states=closed,open,looted".format(mode, ASSET_ID))
        result = dict(manifest)
        result["runtime_evidence"] = evidence
        result["stdout"] = stdout
        result["stderr"] = stderr
        result["marker"] = "LOOT CONTAINER RECIPE PASS mode={0} asset={1} states=closed,open,looted".format(mode, ASSET_ID)
        return result


def _is_blender_runtime() -> bool:
    return Path(sys.executable).name.lower().startswith("blender") or "--background" in sys.argv


def _runtime_argv() -> list[str] | None:
    if "--" not in sys.argv:
        return None
    return list(sys.argv[sys.argv.index("--") + 1 :])


def _run_runtime_main() -> int:
    parser = _build_parser()
    parser.add_argument("--run-dir", type=Path, default=None)
    args = parser.parse_args(_runtime_argv())
    if args.run_dir is None:
        raise ValueError("Blender runtime requires private --run-dir")
    contract = load_contract(args.contract)
    run_dir = _resolve_path(args.run_dir)
    run_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    master_path = _resolve_path(__import__("bpy").data.filepath)
    paths = RecipePaths(
        project_root=_resolve_path(args.project_root),
        task_dir=_resolve_path(args.task_dir),
        master_path=master_path,
        evidence_dir=_resolve_path(args.evidence_dir),
        scratch_glb=run_dir / "cleaned.preview.glb",
        manifest_path=run_dir / "build_recipe_manifest.json",
    )
    _run_blender_recipe_runtime(paths, contract, run_dir)
    return 0


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
        str(paths.project_root / "tools/meshy_loot_container_recipe.py"),
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

    allowed_root_lexical = _lexical_path(allowed_root)
    _reject_symlink_components(allowed_root_lexical, "allowed root")
    root = allowed_root_lexical.resolve(strict=False)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("allowed root must be a regular directory")
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
    try:
        if argv is None and _is_blender_runtime():
            return _run_runtime_main()
        args = _build_parser().parse_args(argv)
        contract, paths = resolve_recipe_paths(
            args.project_root, args.contract, args.task_dir, args.evidence_dir
        )
        run_blender_recipe(paths, contract, args.mode)
        return 0
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"meshy_loot_container_recipe: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "ASSET_ID",
    "BLENDER",
    "CANONICAL_MASTER_LEAF",
    "CANONICAL_MASTER_PATH",
    "EXPORT_OBJECT_NAMES",
    "PROTECTED_REPO_PATHS",
    "PublishedArtifact",
    "RENDER_LEAVES",
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
