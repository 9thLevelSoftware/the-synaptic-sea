#!/usr/bin/env python3
"""Validate a normalized Meshy GLB against its asset contract.

The validator contains a small host-Python glTF reader so the input, geometry,
and report logic can be tested without ``bpy``.  When executed by Blender it
also re-imports the GLB through Blender's glTF importer before reporting pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract  # noqa: E402


BLENDER_PATH = "/opt/homebrew/bin/blender"
PathLike = Union[str, os.PathLike]
Vector3 = Tuple[float, float, float]
Matrix4 = Tuple[float, ...]


class BlenderValidationError(ValueError):
    """Raised when a normalized GLB fails a contract quality gate."""


def _reject_duplicate_keys(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result = {}  # type: Dict[str, Any]
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError("non-finite JSON constant: " + value)


@dataclass(frozen=True)
class ParsedGlb:
    document: Dict[str, Any]
    binary: bytes


def _parse_glb(raw: bytes) -> ParsedGlb:
    if len(raw) < 12:
        raise BlenderValidationError("invalid GLB: file is shorter than the header")
    magic, version, total_length = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF":
        raise BlenderValidationError("invalid GLB magic")
    if version != 2:
        raise BlenderValidationError("unsupported GLB version: " + str(version))
    if total_length != len(raw):
        raise BlenderValidationError("GLB header length does not match file size")

    offset = 12
    json_chunk = None  # type: Optional[bytes]
    binary_chunk = b""
    while offset < total_length:
        if offset + 8 > total_length:
            raise BlenderValidationError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<I4s", raw, offset)
        offset += 8
        end = offset + chunk_length
        if end > total_length:
            raise BlenderValidationError("truncated GLB chunk")
        chunk = raw[offset:end]
        offset = end
        if chunk_type == b"JSON" and json_chunk is None:
            json_chunk = chunk
        elif chunk_type == b"BIN\x00" and not binary_chunk:
            binary_chunk = chunk
    if json_chunk is None:
        raise BlenderValidationError("GLB has no JSON chunk")

    try:
        document = json.loads(
            json_chunk.rstrip(b" \t\r\n").decode("utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        raise BlenderValidationError("GLB JSON chunk is unreadable: " + str(exc)) from exc
    if not isinstance(document, dict):
        raise BlenderValidationError("GLB JSON chunk must be an object")
    asset = document.get("asset")
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        raise BlenderValidationError("GLB must declare glTF asset version 2.0")
    return ParsedGlb(document, binary_chunk)


def _finite_vector(value: object, label: str) -> Vector3:
    if not isinstance(value, list) or len(value) != 3:
        raise BlenderValidationError(label + " must contain three numbers")
    result = tuple(float(item) for item in value)
    if not all(math.isfinite(item) for item in result):
        raise BlenderValidationError(label + " contains non-finite geometry")
    return result  # type: ignore


def _component_format(component_type: int) -> Tuple[str, int]:
    formats = {
        5121: ("B", 1),
        5123: ("H", 2),
        5125: ("I", 4),
        5126: ("f", 4),
    }
    if component_type not in formats:
        raise BlenderValidationError("unsupported accessor component type: " + str(component_type))
    return formats[component_type]


def _type_components(accessor_type: object) -> int:
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    if accessor_type not in components:
        raise BlenderValidationError("unsupported accessor type: " + str(accessor_type))
    return components[accessor_type]


def _accessor_values(
    document: Dict[str, Any], binary: bytes, accessor_index: int
) -> Tuple[List[Tuple[float, ...]], int, str]:
    accessors = document.get("accessors")
    views = document.get("bufferViews")
    if not isinstance(accessors, list) or not 0 <= accessor_index < len(accessors):
        raise BlenderValidationError("accessor index is invalid")
    accessor = accessors[accessor_index]
    if not isinstance(accessor, dict):
        raise BlenderValidationError("accessor must be an object")
    view_index = accessor.get("bufferView")
    if not isinstance(views, list) or not isinstance(view_index, int) or not 0 <= view_index < len(views):
        raise BlenderValidationError("accessor bufferView is invalid")
    view = views[view_index]
    if not isinstance(view, dict):
        raise BlenderValidationError("bufferView must be an object")
    component_type = accessor.get("componentType")
    if not isinstance(component_type, int):
        raise BlenderValidationError("accessor componentType is invalid")
    format_code, component_size = _component_format(component_type)
    component_count = _type_components(accessor.get("type"))
    count = accessor.get("count")
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise BlenderValidationError("accessor count is invalid")
    view_offset = view.get("byteOffset", 0)
    accessor_offset = accessor.get("byteOffset", 0)
    stride = view.get("byteStride", component_size * component_count)
    if not all(isinstance(value, int) and value >= 0 for value in (view_offset, accessor_offset, stride)):
        raise BlenderValidationError("accessor byte offsets are invalid")
    element_size = component_size * component_count
    if stride < element_size:
        raise BlenderValidationError("accessor byteStride is smaller than its element")
    start = int(view_offset) + int(accessor_offset)
    required_end = start if count == 0 else start + (count - 1) * int(stride) + element_size
    view_length = view.get("byteLength")
    if not isinstance(view_length, int) or view_length < 0:
        raise BlenderValidationError("bufferView byteLength is invalid")
    if start + (0 if count == 0 else (count - 1) * int(stride) + element_size) > int(view_offset) + view_length:
        raise BlenderValidationError("accessor exceeds its bufferView")
    if required_end > len(binary):
        raise BlenderValidationError("accessor exceeds the GLB binary chunk")

    values = []  # type: List[Tuple[float, ...]]
    format_string = "<" + (format_code * component_count)
    for index in range(count):
        item_offset = start + index * int(stride)
        item = struct.unpack_from(format_string, binary, item_offset)
        values.append(tuple(float(value) for value in item))
    return values, component_type, str(accessor.get("type"))


def _matrix_identity() -> Matrix4:
    return (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def _matrix_multiply(left: Matrix4, right: Matrix4) -> Matrix4:
    return tuple(
        sum(left[row * 4 + index] * right[index * 4 + column] for index in range(4))
        for row in range(4)
        for column in range(4)
    )


def _matrix_point(matrix: Matrix4, point: Vector3) -> Vector3:
    x, y, z = point
    return (
        matrix[0] * x + matrix[1] * y + matrix[2] * z + matrix[3],
        matrix[4] * x + matrix[5] * y + matrix[6] * z + matrix[7],
        matrix[8] * x + matrix[9] * y + matrix[10] * z + matrix[11],
    )


def _matrix_determinant3(matrix: Matrix4) -> float:
    return (
        matrix[0] * (matrix[5] * matrix[10] - matrix[6] * matrix[9])
        - matrix[1] * (matrix[4] * matrix[10] - matrix[6] * matrix[8])
        + matrix[2] * (matrix[4] * matrix[9] - matrix[5] * matrix[8])
    )


def _local_matrix(node: Dict[str, Any]) -> Matrix4:
    if "matrix" in node:
        matrix = node["matrix"]
        if not isinstance(matrix, list) or len(matrix) != 16:
            raise BlenderValidationError("node matrix must contain 16 numbers")
        values = tuple(float(value) for value in matrix)
        if not all(math.isfinite(value) for value in values):
            raise BlenderValidationError("node transform contains non-finite value")
        # glTF matrices are column-major; this is stored row-major internally.
        return tuple(values[column * 4 + row] for row in range(4) for column in range(4))

    translation = node.get("translation", [0.0, 0.0, 0.0])
    scale = node.get("scale", [1.0, 1.0, 1.0])
    rotation = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    if not isinstance(translation, list) or len(translation) != 3:
        raise BlenderValidationError("node translation must contain three numbers")
    if not isinstance(scale, list) or len(scale) != 3:
        raise BlenderValidationError("node scale must contain three numbers")
    if not isinstance(rotation, list) or len(rotation) != 4:
        raise BlenderValidationError("node rotation must contain four numbers")
    t = tuple(float(value) for value in translation)
    s = tuple(float(value) for value in scale)
    q = tuple(float(value) for value in rotation)
    if not all(math.isfinite(value) for value in t + s + q):
        raise BlenderValidationError("node transform contains non-finite value")
    if any(value <= 0.0 for value in s):
        raise BlenderValidationError("node transforms must have positive scale")
    qx, qy, qz, qw = q
    length = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    if length <= 1e-12:
        raise BlenderValidationError("node rotation quaternion is zero")
    qx, qy, qz, qw = (value / length for value in q)
    rotation_matrix = (
        1 - 2 * (qy * qy + qz * qz),
        2 * (qx * qy - qz * qw),
        2 * (qx * qz + qy * qw),
        t[0],
        2 * (qx * qy + qz * qw),
        1 - 2 * (qx * qx + qz * qz),
        2 * (qy * qz - qx * qw),
        t[1],
        2 * (qx * qz - qy * qw),
        2 * (qy * qz + qx * qw),
        1 - 2 * (qx * qx + qy * qy),
        t[2],
        0.0,
        0.0,
        0.0,
        1.0,
    )
    return tuple(
        rotation_matrix[row * 4 + column]
        * (s[column] if column < 3 else 1.0)
        for row in range(4)
        for column in range(4)
    )


def _node_world_matrices(document: Dict[str, Any]) -> Dict[int, Matrix4]:
    nodes = document.get("nodes", [])
    if not isinstance(nodes, list):
        raise BlenderValidationError("nodes must be an array")
    parents = {}  # type: Dict[int, int]
    for parent_index, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise BlenderValidationError("node must be an object")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise BlenderValidationError("node children must be an array")
        for child in children:
            if not isinstance(child, int) or not 0 <= child < len(nodes):
                raise BlenderValidationError("node child index is invalid")
            if child in parents:
                raise BlenderValidationError("node has multiple parents")
            parents[child] = parent_index

    worlds = {}  # type: Dict[int, Matrix4]
    visiting = set()  # type: set[int]

    def visit(index: int) -> Matrix4:
        if index in worlds:
            return worlds[index]
        if index in visiting:
            raise BlenderValidationError("node hierarchy contains a cycle")
        visiting.add(index)
        node = nodes[index]
        local = _local_matrix(node)
        parent = parents.get(index)
        world = _matrix_multiply(visit(parent), local) if parent is not None else local
        visiting.remove(index)
        worlds[index] = world
        return world

    for index in range(len(nodes)):
        visit(index)
    return worlds


def _mesh_positions(
    document: Dict[str, Any], binary: bytes, mesh_index: int
) -> Tuple[List[Vector3], int, bool, List[int]]:
    meshes = document.get("meshes")
    if not isinstance(meshes, list) or not 0 <= mesh_index < len(meshes):
        raise BlenderValidationError("mesh index is invalid")
    mesh = meshes[mesh_index]
    if not isinstance(mesh, dict):
        raise BlenderValidationError("mesh must be an object")
    primitives = mesh.get("primitives")
    if not isinstance(primitives, list) or not primitives:
        raise BlenderValidationError("mesh has no primitives")
    positions = []  # type: List[Vector3]
    triangles = 0
    has_uv = False
    material_indices = []  # type: List[int]
    for primitive in primitives:
        if not isinstance(primitive, dict):
            raise BlenderValidationError("mesh primitive must be an object")
        if primitive.get("mode", 4) != 4:
            raise BlenderValidationError("mesh primitive must use TRIANGLES mode")
        attributes = primitive.get("attributes")
        if not isinstance(attributes, dict) or not isinstance(attributes.get("POSITION"), int):
            raise BlenderValidationError("mesh primitive has no POSITION attribute")
        raw_positions, component_type, accessor_type = _accessor_values(
            document, binary, attributes["POSITION"]
        )
        if component_type != 5126 or accessor_type != "VEC3":
            raise BlenderValidationError("POSITION must be a float VEC3 accessor")
        decoded_positions = []  # type: List[Vector3]
        for value in raw_positions:
            point = _finite_vector(list(value), "POSITION")
            decoded_positions.append(point)
        positions.extend(decoded_positions)
        if "TEXCOORD_0" in attributes:
            if not isinstance(attributes["TEXCOORD_0"], int):
                raise BlenderValidationError("TEXCOORD_0 accessor is invalid")
            _accessor_values(document, binary, attributes["TEXCOORD_0"])
            has_uv = True

        indices_accessor = primitive.get("indices")
        if indices_accessor is None:
            index_count = len(decoded_positions)
        else:
            if not isinstance(indices_accessor, int):
                raise BlenderValidationError("indices accessor is invalid")
            index_values, index_component, index_type = _accessor_values(
                document, binary, indices_accessor
            )
            if index_type != "SCALAR" or index_component not in (5121, 5123, 5125):
                raise BlenderValidationError("indices must be an unsigned scalar accessor")
            index_count = len(index_values)
        if index_count == 0 or index_count % 3:
            raise BlenderValidationError("mesh primitive does not contain complete triangles")
        triangles += index_count // 3
        material = primitive.get("material")
        if material is not None:
            if not isinstance(material, int):
                raise BlenderValidationError("primitive material index is invalid")
            material_indices.append(material)
    return positions, triangles, has_uv, material_indices


def check_dimensions(
    actual: Sequence[float], expected: Sequence[float], tolerance: float
) -> bool:
    """Return whether all three dimensions are within absolute tolerance."""

    if len(actual) != 3 or len(expected) != 3 or not math.isfinite(float(tolerance)):
        return False
    return all(
        math.isfinite(float(observed))
        and math.isfinite(float(target))
        and abs(float(observed) - float(target)) <= float(tolerance) + 1e-9
        for observed, target in zip(actual, expected)
    )


def _triangle_budget_range(budget: object) -> Tuple[int, int]:
    if isinstance(budget, int) and not isinstance(budget, bool):
        return 1, budget
    if isinstance(budget, dict):
        minimum = budget.get("min")
        maximum = budget.get("max")
        if isinstance(minimum, int) and not isinstance(minimum, bool) and isinstance(maximum, int) and not isinstance(maximum, bool):
            return minimum, maximum
    raise BlenderValidationError("contract triangle budget is invalid")


def check_triangle_budget(triangle_count: int, budget: object) -> bool:
    """Return whether a triangle count is inside an integer/range budget."""

    try:
        minimum, maximum = _triangle_budget_range(budget)
    except BlenderValidationError:
        return False
    return isinstance(triangle_count, int) and not isinstance(triangle_count, bool) and minimum <= triangle_count <= maximum


# Host-side names used by callers and tests.
validate_dimensions = check_dimensions
dimensions_within_tolerance = check_dimensions
validate_triangle_budget = check_triangle_budget
triangle_budget_ok = check_triangle_budget


def _material_names(document: Dict[str, Any]) -> List[str]:
    materials = document.get("materials", [])
    if not isinstance(materials, list):
        raise BlenderValidationError("materials must be an array")
    names = []  # type: List[str]
    for index, material in enumerate(materials):
        if not isinstance(material, dict):
            raise BlenderValidationError("material " + str(index) + " must be an object")
        name = material.get("name", "")
        if not isinstance(name, str) or not name.strip():
            raise BlenderValidationError("material names must be descriptive")
        normalized = name.strip().lower()
        if normalized == "material" or normalized.startswith("material."):
            raise BlenderValidationError("material names must be descriptive")
        names.append(name)
    if len(names) != len(set(names)):
        raise BlenderValidationError("material names must be unique")
    return names


def _validate_images(document: Dict[str, Any]) -> None:
    images = document.get("images", [])
    if not isinstance(images, list):
        raise BlenderValidationError("images must be an array")
    for index, image in enumerate(images):
        if not isinstance(image, dict):
            raise BlenderValidationError("image " + str(index) + " must be an object")
        uri = image.get("uri")
        view = image.get("bufferView")
        if (not isinstance(uri, str) or not uri.strip()) and not isinstance(view, int):
            raise BlenderValidationError("image " + str(index) + " has no data reference")


def _state_tokens(document: Dict[str, Any]) -> List[str]:
    states = document.get("required_states", [])
    if not isinstance(states, list):
        return []
    return [state.lower() for state in states if isinstance(state, str) and state]


def _validate_node_policies(
    document: Dict[str, Any], worlds: Dict[int, Matrix4], bounds_min: Vector3, bounds_max: Vector3
) -> None:
    nodes = document.get("nodes", [])
    if not isinstance(nodes, list):
        return
    state_tokens = _state_tokens(document)
    forbidden_helper_names = []  # type: List[str]
    found_states = set()
    mesh_node_count = 0
    meshes = document.get("meshes", [])
    if isinstance(meshes, list):
        for mesh_index, mesh in enumerate(meshes):
            if not isinstance(mesh, dict):
                continue
            mesh_name = str(mesh.get("name", ""))
            lowered_mesh_name = mesh_name.lower()
            if any(token in lowered_mesh_name for token in ("collision", "physics", "helper", "socket", "marker")):
                forbidden_helper_names.append(mesh_name or ("mesh_" + str(mesh_index)))
            for state in state_tokens:
                if state in lowered_mesh_name:
                    found_states.add(state)

    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            continue
        name = str(node.get("name", ""))
        lowered = name.lower()
        if any(token in lowered for token in ("collision", "physics", "helper", "socket", "marker")):
            forbidden_helper_names.append(name or ("node_" + str(index)))
        for state in state_tokens:
            if state in lowered:
                found_states.add(state)
        mesh_index = node.get("mesh")
        if isinstance(mesh_index, int):
            mesh_node_count += 1
            world = worlds.get(index, _matrix_identity())
            determinant = _matrix_determinant3(world)
            if determinant <= 0.0:
                raise BlenderValidationError("node transforms must preserve positive orientation")
            forward = (world[2], world[6], world[10])
            forward_length = math.sqrt(sum(value * value for value in forward))
            if forward_length <= 1e-12:
                raise BlenderValidationError("forward transform has zero length")
            normalized_forward = tuple(value / forward_length for value in forward)
            if (
                abs(normalized_forward[0]) > 1e-5
                or abs(normalized_forward[1]) > 1e-5
                or normalized_forward[2] <= 0.999
            ):
                raise BlenderValidationError("forward axis must be canonical +Z")

    if forbidden_helper_names:
        raise BlenderValidationError("visual GLB contains floating helper or collision nodes")
    if len(found_states) >= 2:
        raise BlenderValidationError("visual GLB contains independently generated state meshes")
    if mesh_node_count == 0:
        raise BlenderValidationError("GLB has no mesh node")

    pivot = document.get("pivot")
    tolerance = float(document.get("dimension_tolerance_m", 0.0))
    if pivot == "bottom_center":
        center_x = (bounds_min[0] + bounds_max[0]) / 2.0
        center_y = (bounds_min[1] + bounds_max[1]) / 2.0
        if abs(center_x) > tolerance or abs(center_y) > tolerance or abs(bounds_min[2]) > tolerance:
            raise BlenderValidationError("bottom_center pivot policy is not satisfied")
    elif pivot == "scene_origin":
        for index, node in enumerate(nodes):
            if isinstance(node, dict) and isinstance(node.get("mesh"), int):
                world = worlds.get(index, _matrix_identity())
                if any(abs(float(world[offset])) > tolerance for offset in (3, 7, 11)):
                    raise BlenderValidationError("scene_origin pivot policy is not satisfied")
    elif pivot == "attachment":
        if not all(bounds_min[index] - tolerance <= 0.0 <= bounds_max[index] + tolerance for index in range(3)):
            raise BlenderValidationError("attachment pivot must lie within the visual bounds")


def _coerce_contract(contract: Union[AssetContract, PathLike]) -> AssetContract:
    if isinstance(contract, AssetContract):
        return contract
    return load_contract(Path(contract))


def _project_path(project_root: Path, value: Path) -> Path:
    path = value.expanduser()
    if not path.is_absolute():
        path = project_root.expanduser() / path
    return path


def validate_cleaned_glb(
    glb: PathLike, contract: Union[AssetContract, PathLike]
) -> Dict[str, Any]:
    """Validate ``glb`` and return the canonical report object."""

    path = Path(glb).expanduser()
    if not path.exists():
        raise BlenderValidationError("GLB file does not exist: " + str(path))
    if path.is_symlink() or not path.is_file():
        raise BlenderValidationError("GLB path must be a regular file: " + str(path))
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise BlenderValidationError("GLB file could not be read: " + str(exc)) from exc
    parsed = _parse_glb(raw)
    document = parsed.document
    asset_contract = _coerce_contract(contract)
    meshes = document.get("meshes")
    if not isinstance(meshes, list) or not meshes:
        raise BlenderValidationError("GLB mesh inventory is empty")

    worlds = _node_world_matrices(document)
    all_positions = []  # type: List[Vector3]
    triangle_count = 0
    has_uv = False
    used_material_indices = []  # type: List[int]
    for mesh_index in range(len(meshes)):
        positions, triangles, mesh_has_uv, material_indices = _mesh_positions(
            document, parsed.binary, mesh_index
        )
        all_positions.extend(positions)
        triangle_count += triangles
        has_uv = has_uv or mesh_has_uv
        used_material_indices.extend(material_indices)
    if not all_positions:
        raise BlenderValidationError("GLB mesh inventory contains no vertex positions")

    mesh_nodes = [
        (index, node)
        for index, node in enumerate(document.get("nodes", []))
        if isinstance(node, dict) and isinstance(node.get("mesh"), int)
    ]
    transformed_positions = []  # type: List[Vector3]
    meshes_with_nodes = set()
    for node_index, node in mesh_nodes:
        mesh_index = node["mesh"]
        meshes_with_nodes.add(mesh_index)
        mesh_positions, _triangles, _has_uv, _materials = _mesh_positions(
            document, parsed.binary, mesh_index
        )
        world = worlds.get(node_index, _matrix_identity())
        transformed_positions.extend(_matrix_point(world, point) for point in mesh_positions)
    if not transformed_positions:
        transformed_positions = all_positions
    for point in transformed_positions:
        if not all(math.isfinite(value) for value in point):
            raise BlenderValidationError("geometry contains non-finite value")
    bounds_min = tuple(min(point[index] for point in transformed_positions) for index in range(3))
    bounds_max = tuple(max(point[index] for point in transformed_positions) for index in range(3))
    dimensions = tuple(bounds_max[index] - bounds_min[index] for index in range(3))
    if not all(math.isfinite(value) and value >= 0.0 for value in dimensions):
        raise BlenderValidationError("geometry dimensions are non-finite")

    contract_doc = asset_contract.document
    expected_dimensions = contract_doc.get("dimensions_m")
    tolerance = contract_doc.get("dimension_tolerance_m")
    if not isinstance(expected_dimensions, list) or not isinstance(tolerance, (int, float)) or not check_dimensions(dimensions, expected_dimensions, float(tolerance)):
        raise BlenderValidationError("dimensions are outside contract tolerance")

    budget = contract_doc.get("budget", {}).get("triangles") if isinstance(contract_doc.get("budget"), dict) else None
    if not check_triangle_budget(triangle_count, budget):
        raise BlenderValidationError("triangle count exceeds contract budget")

    material_names = _material_names(document)
    budget_document = contract_doc.get("budget")
    material_budget = budget_document.get("material_slots") if isinstance(budget_document, dict) else None
    if not isinstance(material_budget, int) or len(material_names) > material_budget:
        raise BlenderValidationError("material slot count exceeds contract budget")
    for material_index in used_material_indices:
        if material_index < 0 or material_index >= len(material_names):
            raise BlenderValidationError("primitive material index is out of range")
    if material_names and not has_uv:
        raise BlenderValidationError("textured visual GLB has no UV coordinates")
    _validate_images(document)
    _validate_node_policies(document, worlds, bounds_min, bounds_max)

    animations = document.get("animations", [])
    skins = document.get("skins", [])
    if not isinstance(animations, list) or not isinstance(skins, list):
        raise BlenderValidationError("animation and skin inventories must be arrays")
    animation_document = contract_doc.get("animation")
    rigging_allowed = isinstance(animation_document, dict) and animation_document.get("meshy_rigging_allowed") is True
    if (animations or skins) and not rigging_allowed:
        raise BlenderValidationError("animation or rig data is forbidden by the contract")
    if (animations or skins) and isinstance(animation_document, dict) and animation_document.get("rigging_target") != "humanoid_biped":
        raise BlenderValidationError("animation or rig data requires a humanoid_biped target")

    return {
        "asset_id": asset_contract.asset_id,
        "contract_sha256": asset_contract.sha256,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "byte_size": len(raw),
        "mesh_count": len(meshes),
        "material_names": material_names,
        "triangle_count": triangle_count,
        "bounds": {
            "min": [float(value) for value in bounds_min],
            "max": [float(value) for value in bounds_max],
            "dimensions": [float(value) for value in dimensions],
        },
    }


def validate_glb(glb: PathLike, contract: Union[AssetContract, PathLike]) -> Dict[str, Any]:
    """Compatibility alias for the host-testable validator."""

    return validate_cleaned_glb(glb, contract)


def write_validation_report(report_path: PathLike, report: Dict[str, Any]) -> None:
    """Write one canonical UTF-8 validation report."""

    path = Path(report_path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_json_bytes(report))


def _is_blender_runtime() -> bool:
    return Path(sys.executable).name.lower().startswith("blender") or "--background" in sys.argv


def _reimport_with_blender(glb_path: Path, expected_triangles: int) -> None:
    # This import is deliberately local so system Python can import this module.
    import bpy  # type: ignore

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    result = bpy.ops.import_scene.gltf(filepath=str(glb_path))
    if "FINISHED" not in result:
        raise BlenderValidationError("Blender could not re-import cleaned.glb")
    mesh_objects = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if not mesh_objects:
        raise BlenderValidationError("Blender re-import produced no mesh objects")
    imported_triangles = 0
    for obj in mesh_objects:
        scale = obj.scale
        if any(float(value) <= 0.0 for value in scale):
            raise BlenderValidationError("Blender re-import contains non-positive transforms")
        imported_triangles += sum(max(len(polygon.vertices) - 2, 0) for polygon in obj.data.polygons)
    if imported_triangles != expected_triangles:
        raise BlenderValidationError(
            "Blender re-import triangle count differs from GLB count: "
            + str(imported_triangles)
            + " != "
            + str(expected_triangles)
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    return parser


_build_parser = build_parser


def _runtime_argv(argv: Optional[Sequence[str]]) -> Optional[List[str]]:
    if argv is not None:
        return list(argv)
    if "--" not in sys.argv:
        return None
    return list(sys.argv[sys.argv.index("--") + 1 :])


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    """Parse host or Blender arguments without importing ``bpy``."""

    runtime = argv is None and _is_blender_runtime()
    return build_parser().parse_args(_runtime_argv(argv) if runtime else argv)


write_report = write_validation_report
build_validation_report = validate_cleaned_glb


def main(argv: Optional[Sequence[str]] = None) -> int:
    runtime = _is_blender_runtime() if argv is None else False
    try:
        args = parse_args(argv)
        project_root = args.project_root.expanduser().resolve(strict=False)
        contract_path = _project_path(project_root, args.contract)
        glb_path = _project_path(project_root, args.glb)
        report_path = _project_path(project_root, args.report)
        task_dir = _project_path(project_root, args.task_dir)
        if not task_dir.is_dir():
            raise BlenderValidationError("task directory does not exist: " + str(task_dir))
        report = validate_cleaned_glb(glb_path, contract_path)
        if runtime:
            _reimport_with_blender(glb_path, int(report["triangle_count"]))
        write_validation_report(report_path, report)
        print(
            "MESHY BLENDER VALIDATION PASS asset={0} triangles={1} materials={2}".format(
                report["asset_id"], report["triangle_count"], len(report["material_names"])
            )
        )
        return 0
    except (BlenderValidationError, OSError, ValueError) as exc:
        print("meshy_blender_validate: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
