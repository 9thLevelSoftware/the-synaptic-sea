"""Contract helpers for the room-kit-v2 roster and static GLB subset."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

from tools.prop_visual_metadata import _read_glb_chunks, read_glb_metadata


ROOT = Path(__file__).resolve().parents[1]
ROSTER = ROOT / "data/procgen/dressing/room_kit_v2.json"

_IMPROVED_IDS = frozenset(
    {
        "fabrication_station_derelict_v1",
        "medical_stasis_pod_derelict_v1",
        "power_cell_cradle_derelict_v1",
        "salvage_sorter_derelict_v1",
    }
)
_NEW_IDS = frozenset(
    {
        "oxygen_manifold_derelict_v1",
        "coolant_pump_skid_derelict_v1",
        "navigation_chart_table_derelict_v1",
        "scanner_signal_cabinet_derelict_v1",
        "hydroponic_grow_tray_derelict_v1",
        "water_reclaimer_derelict_v1",
        "galley_heater_derelict_v1",
        "crew_bunk_derelict_v1",
        "suit_service_stand_derelict_v1",
        "sample_quarantine_cabinet_derelict_v1",
        "gravity_coil_housing_derelict_v1",
        "cargo_restraint_frame_derelict_v1",
    }
)
_ROW_FIELDS = {
    "asset_id",
    "new",
    "max_size_m",
    "triangles_max",
    "material_max",
    "roles",
    "footprint_cells",
    "behavior",
}
_HELPER_PREFIXES = ("anchor", "collision", "socket", "helper")
_IDENTITY_MATRIX = [
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
]


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _assert_vector(value: Any, length: int, label: str) -> None:
    _assert(isinstance(value, list) and len(value) == length, f"{label} must have {length} values")
    _assert(all(_finite(item) for item in value), f"{label} must be finite")


def load_rows(path: Path = ROSTER) -> list[dict[str, Any]]:
    """Load and validate the frozen sixteen-row placement roster."""
    path = Path(path)
    _assert(path.is_file() and not path.is_symlink(), f"missing room-kit roster: {path}")
    document = json.loads(path.read_text(encoding="utf-8"))
    _assert(isinstance(document, dict), "roster must be an object")
    _assert(document.get("schema_version") == "1.0.0", "unsupported roster schema")
    _assert(document.get("asset_pack") == "room_kit_v2", "unexpected roster asset pack")
    rows = document.get("assets")
    _assert(isinstance(rows, list) and len(rows) == 16, "roster must contain exactly 16 rows")

    identifiers: list[str] = []
    for index, row in enumerate(rows):
        label = f"row {index}"
        _assert(isinstance(row, dict), f"{label} must be an object")
        _assert(set(row) == _ROW_FIELDS, f"{label} has unexpected fields")
        asset_id = row.get("asset_id")
        _assert(
            isinstance(asset_id, str)
            and asset_id.endswith("_derelict_v1")
            and asset_id.islower()
            and asset_id.replace("_", "").isalnum(),
            f"{label} has invalid asset_id",
        )
        identifiers.append(asset_id)
        _assert(isinstance(row.get("new"), bool), f"{label}.new must be boolean")
        _assert(row["new"] == (asset_id in _NEW_IDS), f"{label}.new does not match frozen ID set")
        _assert_vector(row.get("max_size_m"), 3, f"{label}.max_size_m")
        _assert(all(0.0 < value <= 2.2 for value in row["max_size_m"]), f"{label}.max_size_m outside finite envelope")
        for field, maximum in (("triangles_max", 10000), ("material_max", 4)):
            value = row.get(field)
            _assert(isinstance(value, int) and not isinstance(value, bool), f"{label}.{field} must be integer")
            _assert(0 < value <= maximum, f"{label}.{field} outside budget")
        roles = row.get("roles")
        _assert(isinstance(roles, list) and roles, f"{label}.roles must be non-empty")
        _assert(all(isinstance(role, str) and role and role == role.lower() for role in roles), f"{label}.roles must be lowercase strings")
        _assert(len(set(roles)) == len(roles), f"{label}.roles must be unique")
        _assert(row.get("footprint_cells") == [1, 1], f"{label}.footprint_cells must be [1, 1]")
        _assert(row.get("behavior") == "static_dressing", f"{label}.behavior must be static_dressing")

    _assert(len(set(identifiers)) == 16, "asset IDs must be unique")
    _assert(set(identifiers) == _IMPROVED_IDS | _NEW_IDS, "roster IDs do not match frozen Appendix A")
    _assert(sum(row["new"] is True for row in rows) == 12, "roster must contain exactly 12 new rows")
    _assert({row["asset_id"] for row in rows if row["new"] is False} == _IMPROVED_IDS, "improved roster set mismatch")
    return rows


def glb_document(path: Path) -> dict[str, Any]:
    """Read a GLB's JSON document without changing the shared metadata parser."""
    path = Path(path)
    _assert(path.is_file() and not path.is_symlink(), f"missing GLB: {path}")
    try:
        document, _binary = _read_glb_chunks(path.read_bytes())
    except (OSError, ValueError) as exc:
        raise AssertionError(f"invalid GLB: {path}: {exc}") from exc
    return document


def _identity_values(actual: Any, expected: list[float], label: str) -> None:
    _assert(isinstance(actual, list) and len(actual) == len(expected), f"{label} has invalid length")
    _assert(all(_finite(value) for value in actual), f"{label} must be finite")
    _assert(all(abs(float(value) - target) <= 1e-6 for value, target in zip(actual, expected)), f"{label} must be identity")


def _accessor(document: dict[str, Any], index: Any, label: str) -> dict[str, Any]:
    accessors = document.get("accessors")
    _assert(isinstance(accessors, list) and isinstance(index, int) and not isinstance(index, bool), f"{label} accessor is invalid")
    _assert(0 <= index < len(accessors) and isinstance(accessors[index], dict), f"{label} accessor is out of range")
    return accessors[index]


def _triangle_count(document: dict[str, Any], primitive: dict[str, Any]) -> int:
    attributes = primitive["attributes"]
    position = _accessor(document, attributes["POSITION"], "POSITION")
    count = primitive.get("indices", attributes["POSITION"])
    accessor = _accessor(document, count, "index/position")
    value = accessor.get("count")
    _assert(isinstance(value, int) and not isinstance(value, bool) and value > 0, "triangle accessor has invalid count")
    _assert(value % 3 == 0, "triangle accessor count is not divisible by three")
    position_count = position.get("count")
    _assert(isinstance(position_count, int) and not isinstance(position_count, bool) and position_count > 0, "POSITION accessor is empty")
    return value // 3


def validate_static(path: Path, row: dict[str, Any]) -> dict[str, Any]:
    """Validate a normalized, visual-only static GLB against one roster row."""
    path = Path(path)
    _assert(path.is_file() and not path.is_symlink(), f"missing asset: {path}")
    _assert(path.stat().st_size <= 8 * 1024 * 1024, "GLB exceeds static asset byte budget")
    document = glb_document(path)
    asset = document.get("asset")
    _assert(isinstance(asset, dict) and asset.get("version") == "2.0", "GLB must use glTF 2.0")
    scenes = document.get("scenes")
    nodes = document.get("nodes")
    meshes = document.get("meshes")
    _assert(isinstance(scenes, list) and scenes, "GLB has no scenes")
    _assert(isinstance(nodes, list) and nodes, "GLB has no nodes")
    _assert(isinstance(meshes, list) and meshes, "GLB has no meshes")
    _assert(not document.get("skins"), "static GLB must not contain skins")
    _assert(not document.get("animations"), "static GLB must not contain animations")

    referenced_meshes: set[int] = set()
    for node in nodes:
        _assert(isinstance(node, dict), "GLB node must be an object")
        name = str(node.get("name", ""))
        _assert(not name.lower().startswith(_HELPER_PREFIXES), f"helper node exported: {name}")
        for key, expected in (("matrix", _IDENTITY_MATRIX), ("translation", [0.0, 0.0, 0.0]), ("rotation", [0.0, 0.0, 0.0, 1.0]), ("scale", [1.0, 1.0, 1.0])):
            if key in node:
                _identity_values(node[key], expected, f"node {name} {key}")
        _assert("mesh" in node, f"non-mesh node exported: {name}")
        mesh_index = node["mesh"]
        _assert(isinstance(mesh_index, int) and not isinstance(mesh_index, bool) and 0 <= mesh_index < len(meshes), f"node {name} has invalid mesh")
        referenced_meshes.add(mesh_index)

    accessors = document.get("accessors")
    _assert(isinstance(accessors, list), "GLB accessors table is missing")
    for mesh in meshes:
        _assert(isinstance(mesh, dict) and isinstance(mesh.get("primitives"), list) and mesh["primitives"], "mesh has no primitives")
        for primitive in mesh["primitives"]:
            _assert(isinstance(primitive, dict), "mesh primitive must be an object")
            _assert(primitive.get("mode", 4) == 4, "static GLB primitive must be triangles")
            attributes = primitive.get("attributes")
            _assert(isinstance(attributes, dict) and {"POSITION", "NORMAL", "TEXCOORD_0"} <= set(attributes), "primitive is missing POSITION/NORMAL/TEXCOORD_0")
            for attribute in ("POSITION", "NORMAL", "TEXCOORD_0"):
                _accessor(document, attributes[attribute], attribute)
            _assert("targets" not in primitive, "morph targets are not supported")
            _triangle_count(document, primitive)
    _assert(referenced_meshes == set(range(len(meshes))), "GLB contains unreferenced meshes")

    buffers = document.get("buffers", [])
    _assert(isinstance(buffers, list) and buffers, "GLB has no buffer table")
    _assert(all(isinstance(buffer, dict) and not buffer.get("uri") for buffer in buffers), "external buffers are not supported")
    images = document.get("images", [])
    _assert(isinstance(images, list) and all(isinstance(image, dict) and not image.get("uri") for image in images), "external images are not supported")

    materials = document.get("materials", [])
    _assert(isinstance(materials, list) and 0 < len(materials) <= int(row["material_max"]), "material count exceeds static budget")
    allowed_materials = {
        "MAT_PaintedAlloyGray",
        "MAT_WarningStripe",
        "MAT_ReactorGlow",
        "MAT_Biomatter",
        "MAT_Conduit",
        "MAT_RoomKitDisplayOff",
        "MAT_ExposedSteelV2",
    }
    _assert(all(isinstance(material, dict) and material.get("name") in allowed_materials for material in materials), "noncanonical material")

    metadata = read_glb_metadata(path)
    lower = metadata["local_min_m"]
    upper = metadata["local_max_m"]
    _assert(all(_finite(value) for value in lower + upper), "GLB bounds must be finite")
    _assert(abs(lower[1]) <= 0.005, f"prop is not floor-centered/Y-up: {lower}")
    size = [high - low for low, high in zip(lower, upper)]
    _assert(all(0.05 <= actual <= float(cap) + 0.005 for actual, cap in zip(size, row["max_size_m"])), f"prop exceeds roster envelope: {size}")
    _assert(abs(lower[0] + upper[0]) <= 0.02 and abs(lower[2] + upper[2]) <= 0.02, "prop footprint is not centered")

    triangles = sum(_triangle_count(document, primitive) for mesh in meshes for primitive in mesh["primitives"])
    _assert(0 < triangles <= int(row["triangles_max"]), f"triangle budget exceeded: {triangles}")
    return metadata
