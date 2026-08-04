#!/usr/bin/env python3
"""Build and validate an isolated staged pressure-door Godot overlay.

This module is intentionally separate from the promoted-source and live wrapper
validators.  It copies a checkout to a temporary destination, adds only the
staged pressure-door variants at their canonical imported paths, and promotes
only the staged wrapper resources inside that copy.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from collections.abc import Callable, Iterable, Sequence
from pathlib import Path
from typing import NoReturn

ASSET_ID = "pressure_door_1x1"
_VARIANT_ROLES: tuple[str, ...] = ("intact", "damaged", "breached")
_VARIANT_SUFFIXES = {"intact": "", "damaged": "_damaged", "breached": "_breached"}
_CANONICAL_IMPORT_RELATIVE = Path(
    "assets/imported/structural/ship_structural_v0/pressure_door_1x1"
)
_CANONICAL_WRAPPER_RELATIVE = Path(
    "scenes/wrappers/structural/ship_structural_v0"
)
_CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
)
_SMOKE_RELATIVE = Path("scripts/validation/focused_nine_staged_structural_smoke.gd")
_PACKAGE_FILENAMES = (
    f"{ASSET_ID}.manifest.json",
    f"{ASSET_ID}.input.json",
    f"{ASSET_ID}.tscn",
)
_IGNORED_COPY_NAMES = frozenset(
    {
        ".git",
        ".godot",
        ".hermes",
        ".mypy_cache",
        ".omh",
        ".pytest_cache",
        ".ruff_cache",
        ".serena",
        ".superpowers",
        "__pycache__",
    }
)
_DIAGNOSTIC_MARKERS = ("ERROR:", "WARNING:", "SCRIPT ERROR:")
_PASS_MARKER = "FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=4 collision=true"
_KIT_ID = "ship_structural_v0"
_MODULE_FAMILY = "portal"
_CANONICAL_CONTRACT_PATH = f"res://{_CONTRACT_RELATIVE.as_posix()}"
_CANONICAL_WRAPPER_PATH = f"res://{(_CANONICAL_WRAPPER_RELATIVE / f'{ASSET_ID}.tscn').as_posix()}"
_CANONICAL_SOURCE_PATH = f"{_CANONICAL_IMPORT_RELATIVE.as_posix()}/{ASSET_ID}.glb"
_EXPECTED_ANCHORS = (
    {"name": "Anchor_FloorCenter", "kind": "floor-center", "surface": "floor"},
    {
        "name": "Anchor_SOCK_portal_edge_west_01",
        "kind": "attachment",
        "socket_id": "portal_edge_west_01",
        "surface": "custom",
    },
    {
        "name": "Anchor_SOCK_portal_edge_east_01",
        "kind": "attachment",
        "socket_id": "portal_edge_east_01",
        "surface": "custom",
    },
    {
        "name": "Anchor_SOCK_portal_center_internal_01",
        "kind": "attachment",
        "socket_id": "portal_center_internal_01",
        "surface": "custom",
    },
)
_EXPECTED_COLLISION = {
    "kind": "static-body-proxy",
    "proxy_shape": "box",
    "nav_blocker": True,
}
_EXPECTED_BOUNDS = {
    "local_min_m": [-2.0, 0.0, 0.0],
    "local_max_m": [2.0, 3.2, 0.0],
    "placement_origin": "edge-center",
}


def _raw_path(value: Path | str, label: str) -> Path:
    path = Path(value).expanduser()
    if ".." in path.parts:
        raise ValueError(f"{label} must not contain traversal: {path}")
    return path if path.is_absolute() else Path.cwd() / path


def _resolve_path(path: Path, label: str) -> Path:
    try:
        return path.resolve(strict=False)
    except (OSError, RuntimeError, ValueError) as exc:
        raise ValueError(f"cannot resolve {label}: {path}") from exc


def _symlink_components(path: Path) -> Iterable[Path]:
    current = Path(path.anchor) if path.is_absolute() else Path.cwd()
    parts = path.parts[1:] if path.is_absolute() else path.parts
    for part in parts:
        current /= part
        try:
            if current.is_symlink() and current not in (Path("/var"), Path("/tmp")):
                # macOS exposes temporary directories through /var -> /private/var;
                # that system alias is not a caller-controlled staging alias.
                yield current
        except (OSError, RuntimeError, ValueError) as exc:
            raise ValueError(f"cannot inspect {path}") from exc


def _reject_symlink_alias(path: Path, label: str) -> None:
    aliases = tuple(_symlink_components(path))
    if aliases:
        raise ValueError(f"{label} contains symlink alias: {path}")


def _project_root(value: Path | str) -> Path:
    path = _raw_path(value, "project root")
    resolved = _resolve_path(path, "project root")
    if not resolved.is_dir():
        raise ValueError(f"project root is not a directory: {path}")
    return resolved


def _staging_root(value: Path | str) -> Path:
    path = _raw_path(value, "staging root")
    _reject_symlink_alias(path, "staging root")
    resolved = _resolve_path(path, "staging root")
    if not resolved.is_dir():
        raise ValueError(f"staging root is not a directory: {path}")
    return resolved


def _destination_path(value: Path | str, project_root: Path) -> Path:
    path = _raw_path(value, "destination")
    resolved = _resolve_path(path, "destination")
    if resolved == project_root or project_root in resolved.parents:
        raise ValueError(f"destination is within project root: {path}")
    _reject_symlink_alias(path, "destination")
    if path.exists() or path.is_symlink():
        raise ValueError(f"destination already exists: {path}")
    return resolved


def _contained(root: Path, candidate: Path, label: str) -> Path:
    resolved_root = _resolve_path(root, f"{label} root")
    _reject_symlink_alias(candidate, label)
    resolved_candidate = _resolve_path(candidate, label)
    if resolved_candidate == resolved_root or resolved_root not in resolved_candidate.parents:
        raise ValueError(f"{label} escapes root: {candidate}")
    return resolved_candidate


def _regular_file(path: Path, label: str) -> Path:
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise ValueError(f"missing {label}: {path}") from exc
    if not stat.S_ISREG(mode):
        raise ValueError(f"{label} is not a regular file: {path}")
    return path


def _staged_asset_dir(staging_root: Path) -> Path:
    candidates = (
        staging_root / "structural" / ASSET_ID,
        staging_root / "focused_nine" / "structural" / ASSET_ID,
        staging_root / "assets" / "_staging" / "focused_nine" / "structural" / ASSET_ID,
        staging_root / ASSET_ID,
        staging_root if staging_root.name == ASSET_ID else staging_root / "__not_a_candidate__",
    )
    for candidate in candidates:
        candidate = _contained(staging_root, candidate, "staged package")
        if candidate.is_dir():
            return candidate
    raise ValueError(f"missing staged package: {ASSET_ID}")


def _variant_filename(role: str) -> str:
    if role not in _VARIANT_ROLES:
        raise ValueError(f"unsupported pressure-door role: {role}")
    return f"{ASSET_ID}{_VARIANT_SUFFIXES[role]}.glb"


def _staged_variant_paths(staging_root: Path) -> dict[str, Path]:
    package = _staged_asset_dir(staging_root)
    paths: dict[str, Path] = {}
    for role in _VARIANT_ROLES:
        candidate = _contained(
            staging_root, package / _variant_filename(role), "staged variant"
        )
        try:
            path = _regular_file(candidate, f"staged variant {role}")
        except ValueError as exc:
            if not candidate.exists() and not candidate.is_symlink():
                raise ValueError(f"missing staged variant {role}") from exc
            raise
        paths[role] = path
    return paths


_GLB_COMPONENT_SIZES = {
    5120: 1,
    5121: 1,
    5122: 2,
    5123: 2,
    5125: 4,
    5126: 4,
}
_GLB_TYPE_COMPONENT_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
_GLB_INDEX_COMPONENT_TYPES = {5121, 5123, 5125}


def _validate_glb_semantics(
    document: dict[str, object], bin_payload: bytes | None, invalid: Callable[[str], NoReturn]
) -> None:
    """Reject GLB containers that do not reference bounded vertex geometry."""

    meshes = document.get("meshes")
    if not isinstance(meshes, list) or not meshes:
        invalid("no meshes")
        return

    buffers = document.get("buffers")
    buffer_views = document.get("bufferViews")
    accessors = document.get("accessors")
    if not isinstance(buffers, list) or not buffers:
        invalid("missing buffers")
    if not isinstance(buffer_views, list) or not buffer_views:
        invalid("missing buffer views")
    if not isinstance(accessors, list) or not accessors:
        invalid("missing accessors")

    def require_index(value: object, size: int, detail: str) -> int:
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < size:
            invalid(detail)
        return value

    buffer_lengths: list[int] = []
    for buffer_index, buffer in enumerate(buffers):
        if not isinstance(buffer, dict):
            invalid(f"buffer {buffer_index} is invalid")
        byte_length = buffer.get("byteLength")
        if not isinstance(byte_length, int) or isinstance(byte_length, bool) or byte_length < 0:
            invalid(f"buffer {buffer_index} byteLength is invalid")
        buffer_lengths.append(byte_length)
    if bin_payload is None:
        invalid("missing BIN chunk for buffers")
    if buffer_lengths[0] > len(bin_payload or b""):
        invalid("buffer 0 exceeds BIN chunk")

    view_records: list[tuple[int, int, int, int | None]] = []
    for view_index, view in enumerate(buffer_views):
        if not isinstance(view, dict):
            invalid(f"bufferView {view_index} is invalid")
        buffer_index = require_index(
            view.get("buffer"), len(buffer_lengths), f"bufferView {view_index} buffer reference"
        )
        if buffer_index != 0:
            invalid(f"bufferView {view_index} references unavailable buffer")
        byte_offset = view.get("byteOffset", 0)
        byte_length = view.get("byteLength")
        byte_stride = view.get("byteStride")
        if not isinstance(byte_offset, int) or isinstance(byte_offset, bool) or byte_offset < 0:
            invalid(f"bufferView {view_index} byteOffset is invalid")
        if not isinstance(byte_length, int) or isinstance(byte_length, bool) or byte_length < 0:
            invalid(f"bufferView {view_index} byteLength is invalid")
        if byte_stride is not None and (
            not isinstance(byte_stride, int)
            or isinstance(byte_stride, bool)
            or byte_stride < 4
            or byte_stride > 252
            or byte_stride % 4
        ):
            invalid(f"bufferView {view_index} byteStride is invalid")
        if byte_offset + byte_length > buffer_lengths[buffer_index]:
            invalid(f"bufferView {view_index} exceeds buffer bounds")
        if buffer_index == 0 and byte_offset + byte_length > len(bin_payload or b""):
            invalid(f"bufferView {view_index} exceeds BIN bounds")
        view_records.append((buffer_index, byte_offset, byte_length, byte_stride))

    def validate_accessor(
        accessor_value: object,
        expected_type: str,
        label: str,
        allowed_components: set[int] | None = None,
    ) -> None:
        accessor_index = require_index(accessor_value, len(accessors), f"{label} accessor reference")
        accessor = accessors[accessor_index]
        if not isinstance(accessor, dict):
            invalid(f"{label} accessor is invalid")
        buffer_view_index = require_index(
            accessor.get("bufferView"), len(view_records), f"{label} bufferView reference"
        )
        component_type = accessor.get("componentType")
        count = accessor.get("count")
        accessor_type = accessor.get("type")
        if not isinstance(component_type, int) or component_type not in _GLB_COMPONENT_SIZES:
            invalid(f"{label} accessor component type is invalid")
        if allowed_components is not None and (
            not isinstance(component_type, int) or component_type not in allowed_components
        ):
            invalid(f"{label} accessor component type is invalid")
        if not isinstance(count, int) or isinstance(count, bool) or count <= 0:
            invalid(f"{label} accessor count is invalid")
        if accessor_type != expected_type:
            invalid(f"{label} accessor type is invalid")
        accessor_offset = accessor.get("byteOffset", 0)
        if not isinstance(accessor_offset, int) or isinstance(accessor_offset, bool) or accessor_offset < 0:
            invalid(f"{label} accessor byteOffset is invalid")

        buffer_index, view_offset, view_length, byte_stride = view_records[buffer_view_index]
        element_size = _GLB_COMPONENT_SIZES[component_type] * _GLB_TYPE_COMPONENT_COUNTS[expected_type]
        stride = byte_stride or element_size
        if stride < element_size:
            invalid(f"{label} accessor stride is invalid")
        referenced_length = (count - 1) * stride + element_size
        if accessor_offset + referenced_length > view_length:
            invalid(f"{label} accessor exceeds bufferView bounds")
        absolute_end = view_offset + accessor_offset + referenced_length
        if absolute_end > buffer_lengths[buffer_index]:
            invalid(f"{label} accessor exceeds buffer bounds")
        if buffer_index == 0 and absolute_end > len(bin_payload or b""):
            invalid(f"{label} accessor exceeds BIN bounds")

        if label == "POSITION" and component_type != 5126:
            invalid("POSITION accessor component type is invalid")

    for mesh_index, mesh in enumerate(meshes):
        if not isinstance(mesh, dict):
            invalid(f"mesh {mesh_index} is invalid")
        primitives = mesh.get("primitives")
        if not isinstance(primitives, list) or not primitives:
            invalid(f"mesh {mesh_index} has no primitives")
        for primitive_index, primitive in enumerate(primitives):
            if not isinstance(primitive, dict):
                invalid(f"primitive {mesh_index}:{primitive_index} is invalid")
            attributes = primitive.get("attributes")
            if not isinstance(attributes, dict) or "POSITION" not in attributes:
                invalid(f"primitive {mesh_index}:{primitive_index} has no POSITION")
            validate_accessor(
                attributes["POSITION"],
                "VEC3",
                "POSITION",
            )
            if "indices" in primitive:
                validate_accessor(
                    primitive["indices"],
                    "SCALAR",
                    "indices",
                    _GLB_INDEX_COMPONENT_TYPES,
                )


def _validate_glb(path: Path, role: str) -> None:
    try:
        payload = path.read_bytes()
    except OSError as exc:
        raise ValueError(f"cannot read staged variant {role}: {path}") from exc

    def invalid(detail: str) -> NoReturn:
        raise ValueError(f"invalid staged variant {role} GLB {detail}")

    if len(payload) < 12:
        invalid("header")
    magic, version, declared_length = struct.unpack_from("<4sII", payload, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(payload):
        invalid("header")

    cursor = 12
    json_document: object | None = None
    json_chunks = 0
    bin_chunks = 0
    bin_payload: bytes | None = None
    chunk_index = 0
    while cursor < declared_length:
        if declared_length - cursor < 8:
            invalid("chunk header")
        chunk_length, chunk_type = struct.unpack_from("<I4s", payload, cursor)
        cursor += 8
        chunk_end = cursor + chunk_length
        if chunk_end > declared_length or chunk_length % 4:
            invalid("chunk bounds")
        if chunk_index == 0 and chunk_type != b"JSON":
            invalid("first chunk is not JSON")
        if chunk_type == b"JSON":
            json_chunks += 1
            if json_chunks != 1:
                invalid("contains more than one JSON chunk")
            try:
                json_document = json.loads(
                    payload[cursor:chunk_end].rstrip(b" \t\r\n\x00").decode("utf-8")
                )
            except (UnicodeDecodeError, json.JSONDecodeError):
                invalid("JSON chunk")
            asset = json_document.get("asset") if isinstance(json_document, dict) else None
            if not isinstance(asset, dict) or asset.get("version") != "2.0":
                invalid("JSON asset version")
        elif chunk_type == b"BIN\x00":
            bin_chunks += 1
            if bin_chunks != 1:
                invalid("contains more than one BIN chunk")
            bin_payload = payload[cursor:chunk_end]
        else:
            invalid("unknown chunk type")
        cursor = chunk_end
        chunk_index += 1

    if json_chunks != 1 or not isinstance(json_document, dict):
        invalid("missing JSON chunk")
    buffers = json_document.get("buffers")
    if isinstance(buffers, list) and buffers:
        if bin_chunks != 1:
            invalid("declares buffers without one BIN chunk")
    elif bin_chunks:
        invalid("contains BIN chunk without buffers")
    _validate_glb_semantics(json_document, bin_payload, invalid)


def _package_sources(project_root: Path, staging_root: Path, staged_package: Path) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    for filename in _PACKAGE_FILENAMES:
        staged_candidate = staged_package / filename
        source = _contained(staging_root, staged_candidate, "staged wrapper resource")
        try:
            sources[filename] = _regular_file(source, f"staged wrapper resource {filename}")
        except ValueError as exc:
            if not staged_candidate.exists() and not staged_candidate.is_symlink():
                raise ValueError(f"missing staged wrapper resource {filename}") from exc
            raise
    return sources


def _canonical_variant_paths() -> set[str]:
    return {
        f"res://{(_CANONICAL_IMPORT_RELATIVE / _variant_filename(role)).as_posix()}"
        for role in _VARIANT_ROLES
    }


def _parse_ext_resource_bindings(scene_text: str) -> dict[str, str]:
    bindings: dict[str, str] = {}
    for line in scene_text.splitlines():
        if not line.startswith("[ext_resource"):
            continue
        id_match = re.search(r'\bid="([^"]+)"', line)
        path_match = re.search(r'\bpath="([^"]+)"', line)
        if id_match is None or path_match is None:
            raise ValueError("invalid staged wrapper ext_resource declaration")
        resource_id = id_match.group(1)
        if resource_id in bindings:
            raise ValueError("duplicate staged wrapper ext_resource id")
        bindings[resource_id] = path_match.group(1)
    return bindings


def _canonical_variant_path_by_role() -> dict[str, str]:
    return {
        role: f"res://{(_CANONICAL_IMPORT_RELATIVE / _variant_filename(role)).as_posix()}"
        for role in _VARIANT_ROLES
    }


def _validate_scene_text(scene_text: str) -> None:
    resource_bindings = _parse_ext_resource_bindings(scene_text)
    expected_by_role = _canonical_variant_path_by_role()
    expected_paths = set(expected_by_role.values())
    if len(resource_bindings) != 3 or set(resource_bindings.values()) != expected_paths:
        raise ValueError("invalid staged wrapper ext_resource paths")
    if any(
        not path.startswith("res://")
        or ".." in Path(path.removeprefix("res://")).parts
        or "_staging" in path
        or "/Volumes/" in path
        for path in resource_bindings.values()
    ):
        raise ValueError("invalid staged wrapper ext_resource path")

    lines = [line.strip() for line in scene_text.splitlines()]
    node_records: list[tuple[str, str, str]] = []
    node_re = re.compile(r'^\[node\s+name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]+)")?[^\]]*\]$')
    for line in lines:
        match = node_re.match(line)
        if match:
            node_records.append((match.group(1), match.group(2) or "", match.group(3) or ""))
    direct_root = {name: node_type for name, node_type, parent in node_records if parent in ("", ".")}
    direct_visual = {name for name, _node_type, parent in node_records if parent == "Visual"}
    visual_node_re = re.compile(
        r'^\[node\b(?=[^\]]*\bname="VisualInstance_(?P<role>Intact|Damaged|Breached)")'
        r'(?=[^\]]*\bparent="Visual")'
        r'(?=[^\]]*\binstance=ExtResource\("(?P<resource_id>[^"]+)"\))[^\]]*\]$'
    )
    visual_bindings: dict[str, str] = {}
    visual_visibility: dict[str, bool | None] = {}
    for line_index, line in enumerate(lines):
        match = visual_node_re.match(line)
        if match:
            role = match.group("role").lower()
            if role in visual_bindings:
                raise ValueError("duplicate staged wrapper visual binding")
            visual_bindings[role] = match.group("resource_id")
            visible: bool | None = None
            property_index = line_index + 1
            while property_index < len(lines) and not lines[property_index].startswith("["):
                property_line = lines[property_index]
                if property_line.startswith("visible"):
                    visible_match = re.fullmatch(r"visible\s*=\s*(true|false)", property_line)
                    if visible_match is None:
                        raise ValueError(f"invalid staged wrapper {role} visibility")
                    visible = visible_match.group(1) == "true"
                property_index += 1
            visual_visibility[role] = visible
    if set(visual_bindings) != set(_VARIANT_ROLES):
        raise ValueError("invalid staged wrapper visual binding set")
    for role in _VARIANT_ROLES:
        resource_id = visual_bindings[role]
        if resource_bindings.get(resource_id) != expected_by_role[role]:
            raise ValueError(f"invalid staged wrapper visual binding for {role}")
        visible = visual_visibility[role]
        if (role == "intact" and visible is False) or (
            role in ("damaged", "breached") and visible is not False
        ):
            raise ValueError(f"invalid staged wrapper {role} visibility")

    expected_anchors = {
        "Anchor_FloorCenter",
        "Anchor_SOCK_portal_edge_west_01",
        "Anchor_SOCK_portal_edge_east_01",
        "Anchor_SOCK_portal_center_internal_01",
    }
    if direct_root.get("Pressure_Door_1x1") != "Node3D":
        raise ValueError("invalid staged wrapper root")
    if {name for name in direct_root if name.startswith("Anchor_")} != expected_anchors:
        raise ValueError("invalid staged wrapper anchor set")
    if any(direct_root.get(name) != "Marker3D" for name in expected_anchors):
        raise ValueError("invalid staged wrapper anchor types")
    if direct_root.get("CollisionRoot") != "StaticBody3D" or not any(
        name == "CollisionShape3D" and parent == "CollisionRoot" for name, _type, parent in node_records
    ):
        raise ValueError("invalid staged wrapper collision")
    expected_visual = {
        "VisualInstance_Intact",
        "VisualInstance_Damaged",
        "VisualInstance_Breached",
    }
    if direct_root.get("Visual") != "Node3D" or direct_visual != expected_visual:
        raise ValueError("invalid staged wrapper visual variant set")


def _expected_asset_fields() -> dict[str, str]:
    return {
        "id": ASSET_ID,
        "module_id": ASSET_ID,
        "category": "structural",
        "kit_id": _KIT_ID,
        "module_family": _MODULE_FAMILY,
        "contract_path": _CANONICAL_CONTRACT_PATH,
        "wrapper_scene": _CANONICAL_WRAPPER_PATH,
        "source_asset_path": _CANONICAL_SOURCE_PATH,
    }


def _validate_asset(asset: object, label: str, *, include_bounds: bool) -> dict[str, object]:
    if not isinstance(asset, dict):
        raise ValueError(f"{label} asset is invalid")  # noqa: TRY004
    expected = _expected_asset_fields()
    expected_keys = set(expected) | {"anchors", "collision"}
    if include_bounds:
        expected_keys.add("bounds")
    if set(asset) != expected_keys:
        raise ValueError(f"{label} asset schema is invalid")
    for field, value in expected.items():
        if asset.get(field) != value:
            raise ValueError(f"{label} asset {field} mismatch")
    anchors = {"policy": "required", "exposed": list(_EXPECTED_ANCHORS)}
    if asset.get("anchors") != anchors:
        raise ValueError(f"{label} asset anchors mismatch")
    if asset.get("collision") != _EXPECTED_COLLISION:
        raise ValueError(f"{label} asset collision mismatch")
    if include_bounds and asset.get("bounds") != _EXPECTED_BOUNDS:
        raise ValueError(f"{label} asset bounds mismatch")
    return asset


def _validate_promotion(document: object, label: str) -> None:
    if not isinstance(document, dict) or document.get("status") != "staged_not_promoted":
        raise ValueError(f"staged pressure-door {label} is not marked staged_not_promoted")
    expected = {
        "promoted": False,
        "runtime_paths_modified": False,
        "promotion_required": True,
    }
    if document.get("promotion") != expected:
        raise ValueError(f"staged pressure-door {label} has invalid promotion status")


def _validate_manifest(document: object) -> None:
    if not isinstance(document, dict):
        raise ValueError("invalid staged pressure-door manifest")  # noqa: TRY004
    expected_keys = {
        "schema_version",
        "document_kind",
        "status",
        "promotion",
        "asset",
        "required_roles",
        "variants",
        "hash_slots",
    }
    if set(document) != expected_keys:
        raise ValueError("staged pressure-door manifest schema is invalid")
    if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "staged_structural_wrapper_manifest":
        raise ValueError("invalid staged pressure-door manifest schema")
    _validate_promotion(document, "manifest")
    _validate_asset(document.get("asset"), "manifest", include_bounds=False)
    required_roles = list(_VARIANT_ROLES)
    if document.get("required_roles") != required_roles:
        raise ValueError("staged pressure-door manifest roles mismatch")
    expected_variants = [
        {
            "role": role,
            "path": f"res://{(_CANONICAL_IMPORT_RELATIVE / _variant_filename(role)).as_posix()}",
            "sha256": None,
        }
        for role in _VARIANT_ROLES
    ]
    if document.get("variants") != expected_variants:
        raise ValueError("staged pressure-door manifest variants/roles mismatch")
    expected_slots = {role: None for role in _VARIANT_ROLES}
    if document.get("hash_slots") != expected_slots:
        raise ValueError("staged pressure-door manifest hash slots are invalid")


def _validate_input(document: object, manifest: object) -> None:
    if not isinstance(document, dict):
        raise ValueError("invalid staged pressure-door input")  # noqa: TRY004
    expected_keys = {
        "schema_version",
        "document_kind",
        "status",
        "promotion",
        "asset",
        "required_roles",
        "hash_slots",
    }
    if set(document) != expected_keys:
        raise ValueError("staged pressure-door input schema is invalid")
    if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "staged_structural_wrapper_input":
        raise ValueError("invalid staged pressure-door input schema")
    _validate_promotion(document, "input")
    input_asset = _validate_asset(document.get("asset"), "input", include_bounds=True)
    manifest_asset = manifest.get("asset") if isinstance(manifest, dict) else None
    if not isinstance(manifest_asset, dict):
        raise ValueError(  # noqa: TRY004
            "staged pressure-door manifest/input asset cross-reference is invalid"
        )
    for field in (*_expected_asset_fields(), "anchors", "collision"):
        if input_asset.get(field) != manifest_asset.get(field):
            raise ValueError(f"staged pressure-door manifest/input {field} cross-reference differs")
    if document.get("required_roles") != list(_VARIANT_ROLES):
        raise ValueError("staged pressure-door input roles mismatch")
    expected_slots = {role: None for role in _VARIANT_ROLES}
    if document.get("hash_slots") != expected_slots:
        raise ValueError("staged pressure-door input hash slots are invalid")
    if isinstance(manifest, dict):
        if manifest.get("required_roles") != document.get("required_roles"):
            raise ValueError("staged pressure-door manifest/input roles differ")
        if manifest.get("hash_slots") != document.get("hash_slots"):
            raise ValueError("staged pressure-door manifest/input hash slots differ")


def _validate_contract(project_root: Path) -> None:
    path = _regular_file(project_root / _CONTRACT_RELATIVE, "pressure-door contract")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("invalid pressure-door contract") from exc
    if not isinstance(document, dict) or document.get("module_id") != ASSET_ID:
        raise ValueError("pressure-door contract module id mismatch")
    if document.get("kit_id") != "ship_structural_v0" or document.get("module_family") != "portal":
        raise ValueError("pressure-door contract kit/family mismatch")
    sockets = document.get("sockets")
    expected = (
        ("portal_edge_west_01", "portal_edge"),
        ("portal_edge_east_01", "portal_edge"),
        ("portal_center_internal_01", "portal_center"),
    )
    if not isinstance(sockets, list) or not all(isinstance(item, dict) for item in sockets):
        raise ValueError("pressure-door contract socket set mismatch")
    if [(item.get("id"), item.get("kind")) for item in sockets] != list(expected):
        raise ValueError("pressure-door contract socket set mismatch")
    collision = document.get("collision")
    if not isinstance(collision, dict) or collision.get("proxy_shape") != "box" or collision.get("nav_blocker") is not True:
        raise ValueError("pressure-door contract collision mismatch")


def _validate_staged_package(project_root: Path, staging_root: Path, staged_package: Path) -> dict[str, Path]:
    sources = _package_sources(project_root, staging_root, staged_package)
    try:
        scene_text = sources[f"{ASSET_ID}.tscn"].read_text(encoding="utf-8")
        manifest = json.loads(sources[f"{ASSET_ID}.manifest.json"].read_text(encoding="utf-8"))
        input_document = json.loads(sources[f"{ASSET_ID}.input.json"].read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid staged pressure-door metadata resources") from exc
    _validate_scene_text(scene_text)
    _validate_manifest(manifest)
    _validate_input(input_document, manifest)
    _validate_contract(project_root)
    return sources


def _copy_project_without_symlinks(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        if entry.name in _IGNORED_COPY_NAMES or entry.is_symlink():
            continue
        target = destination / entry.name
        if entry.is_dir():
            _copy_project_without_symlinks(entry, target)
        elif entry.is_file():
            shutil.copy2(entry, target)


def _copy_resources_into_overlay(
    overlay_root: Path,
    package_sources: dict[str, Path],
    staged_variants: dict[str, Path],
) -> None:
    import_root = overlay_root / _CANONICAL_IMPORT_RELATIVE
    import_root.mkdir(parents=True, exist_ok=True)
    for role, source in staged_variants.items():
        shutil.copy2(source, import_root / _variant_filename(role))

    wrapper_root = overlay_root / _CANONICAL_WRAPPER_RELATIVE
    wrapper_root.mkdir(parents=True, exist_ok=True)
    for filename, source in package_sources.items():
        shutil.copy2(source, wrapper_root / filename)


def build_overlay(project_root: Path, staging_root: Path, destination: Path) -> None:
    """Atomically build a project overlay containing the staged pressure door."""

    root = _project_root(project_root)
    stage = _staging_root(staging_root)
    destination_path = _destination_path(destination, root)
    staged_package = _staged_asset_dir(stage)
    staged_variants = _staged_variant_paths(stage)
    for role, path in staged_variants.items():
        _validate_glb(path, role)
    package_sources = _validate_staged_package(root, stage, staged_package)

    destination_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = Path(tempfile.mkdtemp(prefix="focused-nine-overlay-", dir=str(destination_path.parent)))
    try:
        _copy_project_without_symlinks(root, temporary_path)
        _copy_resources_into_overlay(temporary_path, package_sources, staged_variants)
        temporary_path.replace(destination_path)
    except BaseException:
        shutil.rmtree(temporary_path, ignore_errors=True)
        raise


def _diagnostics(output: str) -> list[str]:
    return [
        line.strip()
        for line in output.splitlines()
        if line.strip() and any(marker in line for marker in _DIAGNOSTIC_MARKERS)
    ]


def _run_godot(command: Sequence[str], overlay_root: Path, label: str, require_marker: bool = False) -> list[str]:
    try:
        completed = subprocess.run(
            list(command),
            cwd=str(overlay_root),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return [f"cannot invoke Godot for {label}: {exc}"]
    output = f"{getattr(completed, 'stdout', '') or ''}\n{getattr(completed, 'stderr', '') or ''}"
    errors = _diagnostics(output)
    if completed.returncode != 0 and not errors:
        errors.append(f"Godot {label} failed: exit {completed.returncode}")
    if require_marker and _PASS_MARKER not in output and not errors:
        errors.append(f"Godot {label} did not emit {_PASS_MARKER}")
    return errors


def validate_pressure_door_overlay(
    project_root: Path, staging_root: Path, godot: Path
) -> list[str]:
    """Return deterministic diagnostics from an isolated pressure-door validation."""

    try:
        root = _project_root(project_root)
        stage = _staging_root(staging_root)
        staged_package = _staged_asset_dir(stage)
        staged_variants = _staged_variant_paths(stage)
        for role, path in staged_variants.items():
            _validate_glb(path, role)
        _validate_staged_package(root, stage, staged_package)
    except (OSError, RuntimeError, ValueError) as exc:
        message = str(exc) or "invalid pressure-door staging input"
        return [message]

    with tempfile.TemporaryDirectory(prefix="focused-nine-pressure-door-") as temporary:
        overlay_root = Path(temporary) / "project"
        try:
            build_overlay(root, stage, overlay_root)
        except (OSError, RuntimeError, ValueError) as exc:
            return [f"cannot create pressure-door validation overlay: {exc}"]

        import_command = [str(godot), "--headless", "--import", "--path", str(overlay_root)]
        errors = _run_godot(import_command, overlay_root, "pressure-door import")
        if errors:
            return errors
        smoke_command = [
            str(godot),
            "--headless",
            "--path",
            str(overlay_root),
            "--script",
            f"res://{_SMOKE_RELATIVE.as_posix()}",
        ]
        return _run_godot(smoke_command, overlay_root, "pressure-door smoke", require_marker=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--staging-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot")))
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        errors = validate_pressure_door_overlay(args.project_root, args.staging_root, args.godot)
    except (OSError, RuntimeError, ValueError) as exc:
        errors = [str(exc) or "invalid pressure-door staging input"]
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(_PASS_MARKER)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
