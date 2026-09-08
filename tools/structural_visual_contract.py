"""Pure structural visual policy and geometry validation.

This module intentionally knows nothing about Blender, GLB accessors, sockets, or
physics.  Inputs are already in runtime (Godot Y-up) coordinates and every
interface check is fail-closed.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Iterable, Sequence


class VisualContractError(ValueError):
    """Raised when the canonical dimensions document is missing or invalid."""


_EPS = 0.0001
_DEFAULT_PATH = Path(__file__).resolve().parents[1] / "data/art/structural_visual_dimensions.v1.json"
_SUPPORTED = {
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
}


def _is_number(value: Any) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(float(value))
    except (OverflowError, ValueError):
        return False


def _close(left: float, right: float, epsilon: float = _EPS) -> bool:
    return abs(float(left) - float(right)) <= epsilon


def _path(path: str) -> str:
    return path or "document"


def _scan_json(value: Any, path: str = "document") -> list[str]:
    """Find non-finite numbers and non-string object keys without stringifying keys."""
    errors: list[str] = []
    stack: list[tuple[Any, str]] = [(value, path)]
    while stack:
        current, current_path = stack.pop()
        if isinstance(current, dict):
            for key, child in current.items():
                if not isinstance(key, str):
                    errors.append(f"{current_path} contains a non-string object key")
                    child_path = f"{current_path}.<non-string-key>"
                else:
                    child_path = f"{current_path}.{key}"
                stack.append((child, child_path))
        elif isinstance(current, (list, tuple)):
            for index, child in reversed(list(enumerate(current))):
                stack.append((child, f"{current_path}[{index}]"))
        elif isinstance(current, float) and not math.isfinite(current):
            errors.append(f"{current_path} contains non-finite value")
    return sorted(set(errors))


def _expect_mapping(value: Any, path: str, required: Iterable[str], optional: Iterable[str] = ()) -> None:
    if not isinstance(value, dict):
        raise VisualContractError(f"{path} must be an object")
    required_set = set(required)
    optional_set = set(optional)
    missing = sorted(required_set - set(value))
    unknown = sorted(set(value) - required_set - optional_set)
    if missing:
        raise VisualContractError(f"{path} missing field(s): {', '.join(missing)}")
    if unknown:
        raise VisualContractError(f"{path} unknown field(s): {', '.join(unknown)}")


def _number_at(document: dict[str, Any], dotted_path: str) -> float:
    value: Any = document
    for component in dotted_path.split("."):
        value = value[component]
    if not _is_number(value):
        raise VisualContractError(f"{dotted_path} must be a finite number")
    return float(value)


def _require_number(value: Any, path: str, expected: float | None = None) -> None:
    if not _is_number(value):
        raise VisualContractError(f"{path} must be a finite number and not a boolean")
    # Import round-trip tolerance belongs to geometry, never policy values.
    if expected is not None and float(value) != float(expected):
        raise VisualContractError(f"{path} must equal {expected:g}")


def _require_vector(value: Any, path: str, expected: Sequence[float] | None = None) -> None:
    if not isinstance(value, list) or len(value) != 3:
        raise VisualContractError(f"{path} must be a 3-vector")
    for index, component in enumerate(value):
        _require_number(component, f"{path}[{index}]")
        if expected is not None and float(component) != float(expected[index]):
            raise VisualContractError(f"{path} must equal {list(expected)!r}")


def _require_string(value: Any, path: str, expected: str | None = None) -> None:
    if not isinstance(value, str) or not value:
        raise VisualContractError(f"{path} must be a non-empty string")
    if expected is not None and value != expected:
        raise VisualContractError(f"{path} must equal {expected!r}")


def _validate_dimensions(document: Any) -> dict[str, Any]:
    if not isinstance(document, dict):
        raise VisualContractError("dimensions document must be an object")
    scan_errors = _scan_json(document)
    if scan_errors:
        raise VisualContractError("; ".join(scan_errors))

    _expect_mapping(
        document,
        "root",
        (
            "schema_version", "document_kind", "status", "kit_id", "authority",
            "coordinate_system", "global", "floor_interface", "edge_interface",
            "doorway_open_interface", "wall_family_interface", "pillar_interface",
            "ramp_interface", "transform_contract", "variants", "ownership",
        ),
    )
    _require_string(document["schema_version"], "schema_version", "1.0.0")
    _require_string(document["document_kind"], "document_kind", "structural_visual_dimensions")
    _require_string(document["status"], "status", "approved_dimensions_pending_source_authority")
    _require_string(document["kit_id"], "kit_id")

    _expect_mapping(document["authority"], "authority", (
        "integration_baseline_commit", "integration_baseline_status",
        "source_attestation_schema", "source_attestation_status",
    ))
    for key in document["authority"]:
        _require_string(document["authority"][key], f"authority.{key}")

    _expect_mapping(document["coordinate_system"], "coordinate_system", (
        "runtime", "edge_local_axes", "floor_local_axes", "blender_conversion", "allowed_yaw_degrees",
    ))
    _require_string(document["coordinate_system"]["runtime"], "coordinate_system.runtime", "Godot Y-up")
    _require_string(document["coordinate_system"]["blender_conversion"], "coordinate_system.blender_conversion")
    for axis_group in ("edge_local_axes", "floor_local_axes"):
        _expect_mapping(document["coordinate_system"][axis_group], f"coordinate_system.{axis_group}", ("tangent", "up", "normal") if axis_group == "edge_local_axes" else ("width", "up", "depth"))
        for key, value in document["coordinate_system"][axis_group].items():
            _require_string(value, f"coordinate_system.{axis_group}.{key}")
    yaw = document["coordinate_system"]["allowed_yaw_degrees"]
    if not isinstance(yaw, list) or len(yaw) != 4:
        raise VisualContractError("coordinate_system.allowed_yaw_degrees must contain four numbers")
    for value, expected in zip(yaw, (0.0, 90.0, 180.0, 270.0)):
        _require_number(value, "coordinate_system.allowed_yaw_degrees[]", expected)

    _expect_mapping(document["global"], "global", (
        "grid_step_m", "deck_height_m", "walking_datum_y_m", "float_roundtrip_epsilon_m",
        "required_object_scale", "required_mesh_origin_offset_m", "per_asset_dimension_overrides_allowed",
    ))
    for key, expected in (("grid_step_m", 4.0), ("deck_height_m", 4.0), ("walking_datum_y_m", 0.0), ("float_roundtrip_epsilon_m", _EPS)):
        _require_number(document["global"][key], f"global.{key}", expected)
    _require_vector(document["global"]["required_object_scale"], "global.required_object_scale", (1.0, 1.0, 1.0))
    _require_vector(document["global"]["required_mesh_origin_offset_m"], "global.required_mesh_origin_offset_m", (0.0, 0.0, 0.0))
    if document["global"]["per_asset_dimension_overrides_allowed"] is not False:
        raise VisualContractError("global.per_asset_dimension_overrides_allowed must be false")

    _expect_mapping(document["floor_interface"], "floor_interface", (
        "cell_span_m", "slab_thickness_m", "top_y_m", "underside_y_m", "max_positive_relief_m",
        "max_recess_depth_m", "footprint_rule", "mating_edge_rule",
    ))
    for key, expected in (("cell_span_m", 4.0), ("slab_thickness_m", 0.25), ("top_y_m", 0.0), ("underside_y_m", -0.25), ("max_positive_relief_m", 0.0), ("max_recess_depth_m", 0.02)):
        _require_number(document["floor_interface"][key], f"floor_interface.{key}", expected)
    if not _close(_number_at(document, "floor_interface.top_y_m") - _number_at(document, "floor_interface.underside_y_m"), _number_at(document, "floor_interface.slab_thickness_m")):
        raise VisualContractError("floor_interface top/underside/thickness are inconsistent")
    _require_string(document["floor_interface"]["footprint_rule"], "floor_interface.footprint_rule")
    _require_string(document["floor_interface"]["mating_edge_rule"], "floor_interface.mating_edge_rule")

    _expect_mapping(document["edge_interface"], "edge_interface", (
        "edge_plane_normal_m", "visual_total_depth_m", "visual_normal_min_m", "visual_normal_max_m",
        "one_cell_tangent_min_m", "one_cell_tangent_max_m", "two_cell_tangent_min_m", "two_cell_tangent_max_m",
        "base_y_m", "shared_visual_top_y_m", "terminal_mating_height_m", "terminal_mating_band_m", "rule",
    ))
    for key, expected in (("edge_plane_normal_m", 0.0), ("visual_total_depth_m", 0.2), ("visual_normal_min_m", -0.1), ("visual_normal_max_m", 0.1), ("one_cell_tangent_min_m", -2.0), ("one_cell_tangent_max_m", 2.0), ("two_cell_tangent_min_m", -4.0), ("two_cell_tangent_max_m", 4.0), ("base_y_m", 0.0), ("shared_visual_top_y_m", 3.2), ("terminal_mating_height_m", 3.2), ("terminal_mating_band_m", 0.2)):
        _require_number(document["edge_interface"][key], f"edge_interface.{key}", expected)
    if not _close(_number_at(document, "edge_interface.visual_normal_max_m") - _number_at(document, "edge_interface.visual_normal_min_m"), _number_at(document, "edge_interface.visual_total_depth_m")):
        raise VisualContractError("edge_interface visual depth is inconsistent")
    _require_string(document["edge_interface"]["rule"], "edge_interface.rule")

    _expect_mapping(document["doorway_open_interface"], "doorway_open_interface", ("clear_prism", "threshold_max_y_m", "threshold_must_not_reduce_clear_prism", "state_parity"))
    _expect_mapping(document["doorway_open_interface"]["clear_prism"], "doorway_open_interface.clear_prism", ("tangent_min_m", "tangent_max_m", "bottom_y_m", "top_y_m", "normal_min_m", "normal_max_m"))
    for key, expected in (("tangent_min_m", -.6), ("tangent_max_m", .6), ("bottom_y_m", 0.0), ("top_y_m", 2.2), ("normal_min_m", -.1), ("normal_max_m", .1)):
        _require_number(document["doorway_open_interface"]["clear_prism"][key], f"doorway_open_interface.clear_prism.{key}", expected)
    _require_number(document["doorway_open_interface"]["threshold_max_y_m"], "doorway_open_interface.threshold_max_y_m", 0.0)
    if document["doorway_open_interface"]["threshold_must_not_reduce_clear_prism"] is not True:
        raise VisualContractError("doorway_open_interface threshold rule must be true")
    _require_string(document["doorway_open_interface"]["state_parity"], "doorway_open_interface.state_parity")

    _expect_mapping(document["wall_family_interface"], "wall_family_interface", ("straight_wing_span_m", "corner_and_junction_rule", "end_plane_rule"))
    _require_number(document["wall_family_interface"]["straight_wing_span_m"], "wall_family_interface.straight_wing_span_m", 4.0)
    _require_string(document["wall_family_interface"]["corner_and_junction_rule"], "wall_family_interface.corner_and_junction_rule")
    _require_string(document["wall_family_interface"]["end_plane_rule"], "wall_family_interface.end_plane_rule")

    _expect_mapping(document["pillar_interface"], "pillar_interface", ("base_contact_y_m", "top_contact_y_m", "contact_centers_xz_m", "rule"))
    _require_number(document["pillar_interface"]["base_contact_y_m"], "pillar_interface.base_contact_y_m", 0.0)
    _require_number(document["pillar_interface"]["top_contact_y_m"], "pillar_interface.top_contact_y_m", 3.2)
    centers = document["pillar_interface"]["contact_centers_xz_m"]
    if not isinstance(centers, list) or len(centers) != 2:
        raise VisualContractError("pillar_interface.contact_centers_xz_m must be an X/Z pair")
    for index, value in enumerate(centers):
        _require_number(value, f"pillar_interface.contact_centers_xz_m[{index}]", 0.0)
    _require_string(document["pillar_interface"]["rule"], "pillar_interface.rule")

    _expect_mapping(document["ramp_interface"], "ramp_interface", ("footprint_cells", "width_m", "run_m", "run_min_z_m", "run_max_z_m", "lower_endpoint_y_m", "upper_endpoint_y_m", "rise_m", "slope_degrees", "endpoint_rule", "runtime_status"))
    footprint_cells = document["ramp_interface"]["footprint_cells"]
    if (
        not isinstance(footprint_cells, list)
        or len(footprint_cells) != 2
        or any(isinstance(value, bool) or not isinstance(value, int) for value in footprint_cells)
        or footprint_cells != [1, 2]
    ):
        raise VisualContractError("ramp_interface.footprint_cells must equal [1, 2]")
    for key, expected in (("width_m", 4.0), ("run_m", 8.0), ("run_min_z_m", -4.0), ("run_max_z_m", 4.0), ("lower_endpoint_y_m", 0.0), ("upper_endpoint_y_m", .55), ("rise_m", .55), ("slope_degrees", 3.932896272184)):
        _require_number(document["ramp_interface"][key], f"ramp_interface.{key}", expected)
    if not _close(_number_at(document, "ramp_interface.run_max_z_m") - _number_at(document, "ramp_interface.run_min_z_m"), _number_at(document, "ramp_interface.run_m")):
        raise VisualContractError("ramp_interface run endpoints are inconsistent")
    if not _close(_number_at(document, "ramp_interface.upper_endpoint_y_m") - _number_at(document, "ramp_interface.lower_endpoint_y_m"), _number_at(document, "ramp_interface.rise_m")):
        raise VisualContractError("ramp_interface endpoint rise is inconsistent")
    _require_string(document["ramp_interface"]["endpoint_rule"], "ramp_interface.endpoint_rule")
    _require_string(document["ramp_interface"]["runtime_status"], "ramp_interface.runtime_status")

    _expect_mapping(document["transform_contract"], "transform_contract", ("cell_world_position", "edge_world_position", "yaw_by_direction", "additional_translation_rotation_scale_allowed"))
    _require_string(document["transform_contract"]["cell_world_position"], "transform_contract.cell_world_position")
    _require_string(document["transform_contract"]["edge_world_position"], "transform_contract.edge_world_position")
    _expect_mapping(document["transform_contract"]["yaw_by_direction"], "transform_contract.yaw_by_direction", ("south", "west", "north", "east"))
    for key, expected in (("south", 0.0), ("west", 90.0), ("north", 180.0), ("east", 270.0)):
        _require_number(document["transform_contract"]["yaw_by_direction"][key], f"transform_contract.yaw_by_direction.{key}", expected)
    if document["transform_contract"]["additional_translation_rotation_scale_allowed"] is not False:
        raise VisualContractError("transform_contract additional transforms must be disallowed")

    _expect_mapping(document["variants"], "variants", ("interface_parity_required", "allowed_difference", "intact_aliasing_allowed"))
    if document["variants"]["interface_parity_required"] is not True or document["variants"]["intact_aliasing_allowed"] is not False:
        raise VisualContractError("variants interface policy is inconsistent")
    _require_string(document["variants"]["allowed_difference"], "variants.allowed_difference")

    _expect_mapping(document["ownership"], "ownership", ("visual_contract_consumers", "forbidden_consumers"))
    for key in ("visual_contract_consumers", "forbidden_consumers"):
        values = document["ownership"][key]
        if not isinstance(values, list) or not values or not all(isinstance(item, str) and item for item in values):
            raise VisualContractError(f"ownership.{key} must be a non-empty list of strings")
    return document


def load_dimensions(path: Path | None = None) -> dict[str, Any]:
    """Load and validate the canonical art-only policy without dropping metadata."""
    candidate = _DEFAULT_PATH if path is None else Path(path)
    try:
        text = candidate.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise VisualContractError(f"cannot read dimensions policy: {candidate}") from exc
    try:
        document = json.loads(text, parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
        raise VisualContractError(f"invalid dimensions JSON: {candidate}") from exc
    return _validate_dimensions(document)


def _bounds(minimum: Sequence[float], maximum: Sequence[float]) -> dict[str, list[float]]:
    return {"min": [float(value) for value in minimum], "max": [float(value) for value in maximum]}


def module_profile(module_id: str, dimensions: dict[str, Any]) -> dict[str, Any]:
    """Return the supported module envelope, or an explicit HOLD profile."""
    dimensions = _validate_dimensions(dimensions)
    if not isinstance(module_id, str) or not module_id or "/" in module_id or "\\" in module_id:
        raise VisualContractError("module_id must be a simple non-empty string")
    edge = dimensions["edge_interface"]
    floor = dimensions["floor_interface"]
    if module_id not in _SUPPORTED:
        return {
            "module_id": module_id,
            "status": "hold",
            "held": True,
            "reason": f"unsupported geometry profile: {module_id}",
            "family": "unsupported",
            "bounds": None,
        }
    if module_id == "floor_1x1":
        cells_x, cells_z, family = 1, 1, "floor"
        bounds = _bounds((-2, floor["underside_y_m"], -2), (2, floor["top_y_m"], 2))
    elif module_id == "floor_2x1":
        cells_x, cells_z, family = 2, 1, "floor"
        bounds = _bounds((-4, floor["underside_y_m"], -2), (4, floor["top_y_m"], 2))
    elif module_id == "corridor_floor_1x1":
        cells_x, cells_z, family = 1, 1, "corridor_floor"
        bounds = _bounds((-2, floor["underside_y_m"], -2), (2, floor["top_y_m"], 2))
    elif module_id == "corridor_floor_1x2":
        cells_x, cells_z, family = 1, 2, "corridor_floor"
        bounds = _bounds((-2, floor["underside_y_m"], -4), (2, floor["top_y_m"], 4))
    elif module_id == "wall_straight_1x1":
        cells_x, cells_z, family = 1, 1, "wall"
        bounds = _bounds((edge["one_cell_tangent_min_m"], edge["base_y_m"], edge["visual_normal_min_m"]), (edge["one_cell_tangent_max_m"], edge["shared_visual_top_y_m"], edge["visual_normal_max_m"]))
    elif module_id == "doorway_frame_open_1x1":
        cells_x, cells_z, family = 1, 1, "doorway"
        bounds = _bounds((edge["one_cell_tangent_min_m"], edge["base_y_m"], edge["visual_normal_min_m"]), (edge["one_cell_tangent_max_m"], edge["shared_visual_top_y_m"], edge["visual_normal_max_m"]))
    else:
        cells_x, cells_z, family = 1, 1, "pillar"
        # The policy fixes contacts and cell envelope, not a cosmetic pillar width.
        half = floor["cell_span_m"] / 2.0
        bounds = _bounds((-half, edge["base_y_m"], -half), (half, edge["shared_visual_top_y_m"], half))
    return {
        "module_id": module_id,
        "status": "pass",
        "held": False,
        "reason": None,
        "family": family,
        "bounds": bounds,
        "cells": [cells_x, cells_z],
    }


def _normalise_triangles(triangles: Sequence[Sequence[Sequence[float]]]) -> tuple[list[tuple[tuple[float, float, float], ...]], list[str]]:
    errors: list[str] = []
    if isinstance(triangles, (str, bytes)) or not isinstance(triangles, Sequence):
        return [], ["triangles must be a sequence"]
    if not triangles:
        return [], ["geometry is empty"]
    result: list[tuple[tuple[float, float, float], ...]] = []
    for triangle_index, triangle in enumerate(triangles):
        if isinstance(triangle, (str, bytes)) or not isinstance(triangle, Sequence) or len(triangle) != 3:
            errors.append(f"triangle[{triangle_index}] must contain exactly three positions")
            continue
        points: list[tuple[float, float, float]] = []
        for vertex_index, point in enumerate(triangle):
            if isinstance(point, (str, bytes)) or not isinstance(point, Sequence) or len(point) != 3:
                errors.append(f"triangle[{triangle_index}][{vertex_index}] must be a 3-vector")
                continue
            if any(not _is_number(value) for value in point):
                errors.append(f"triangle[{triangle_index}][{vertex_index}] contains a non-finite or boolean coordinate")
                continue
            points.append((float(point[0]), float(point[1]), float(point[2])))
        if len(points) != 3:
            continue
        a, b, c = points
        cross = ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]), (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]), (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
        area_twice = math.sqrt(sum(component * component for component in cross))
        if area_twice <= _EPS * _EPS:
            errors.append(f"triangle[{triangle_index}] is degenerate")
            continue
        result.append((points[0], points[1], points[2]))
    return result, sorted(set(errors))


def _measured_bounds(triangles: Sequence[Sequence[Sequence[float]]]) -> dict[str, list[float]]:
    points = [point for triangle in triangles for point in triangle]
    return _bounds(
        [min(point[axis] for point in points) for axis in range(3)],
        [max(point[axis] for point in points) for axis in range(3)],
    )


def _bounds_errors(actual: dict[str, list[float]], expected: dict[str, list[float]], epsilon: float = _EPS) -> list[str]:
    errors: list[str] = []
    for label in ("min", "max"):
        for axis, name in enumerate(("x", "y", "z")):
            if not _close(actual[label][axis], expected[label][axis], epsilon):
                errors.append(f"bounds {label}.{name} {actual[label][axis]:g} does not equal expected {expected[label][axis]:g}")
    return errors


def _project(triangle: Sequence[Sequence[float]], axes: tuple[int, int]) -> tuple[tuple[float, float], ...]:
    return tuple((float(point[axes[0]]), float(point[axes[1]])) for point in triangle)


def _cross_2d(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _segment_intersection_x(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]) -> float | None:
    abx, aby = b[0] - a[0], b[1] - a[1]
    cdx, cdy = d[0] - c[0], d[1] - c[1]
    denominator = abx * cdy - aby * cdx
    if abs(denominator) <= _EPS * _EPS:
        return None
    acx, acy = c[0] - a[0], c[1] - a[1]
    t = (acx * cdy - acy * cdx) / denominator
    u = (acx * aby - acy * abx) / denominator
    if -_EPS <= t <= 1.0 + _EPS and -_EPS <= u <= 1.0 + _EPS:
        return a[0] + t * abx
    return None


def _intervals_at_x(polygon: Sequence[tuple[float, float]], x: float) -> list[tuple[float, float]]:
    ys: list[float] = []
    for index in range(len(polygon)):
        left = polygon[index]
        right = polygon[(index + 1) % len(polygon)]
        dx = right[0] - left[0]
        if abs(dx) <= _EPS:
            if _close(x, left[0]):
                ys.extend((left[1], right[1]))
            continue
        low, high = sorted((left[0], right[0]))
        if low - _EPS <= x <= high + _EPS:
            t = (x - left[0]) / dx
            if -_EPS <= t <= 1.0 + _EPS:
                ys.append(left[1] + t * (right[1] - left[1]))
    if len(ys) < 2:
        return []
    return [(min(ys), max(ys))]


def _intervals_cover(intervals: Sequence[tuple[float, float]], lower: float, upper: float) -> bool:
    if not intervals:
        return False
    cursor = lower
    for left, right in sorted(intervals):
        if right < cursor - _EPS:
            continue
        if left > cursor + _EPS:
            return False
        cursor = max(cursor, right)
        if cursor >= upper - _EPS:
            return True
    return cursor >= upper - _EPS


def _coverage(polygons: Sequence[Sequence[tuple[float, float]]], rectangle: tuple[float, float, float, float]) -> bool:
    """Exact linear-surface coverage using a complete edge-intersection sweep.

    Every x interval in a planar arrangement has a stable set of y intervals.
    Checking its midpoint and every arrangement boundary is equivalent to
    checking the union, unlike sparse point or AABB sampling.
    """
    xmin, xmax, ymin, ymax = rectangle
    if not polygons or xmax <= xmin or ymax <= ymin:
        return False
    critical = [xmin, xmax]
    edges: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for polygon in polygons:
        for point in polygon:
            if xmin - _EPS <= point[0] <= xmax + _EPS:
                critical.append(min(xmax, max(xmin, point[0])))
        for index in range(len(polygon)):
            edges.append((polygon[index], polygon[(index + 1) % len(polygon)]))
    for index, (a, b) in enumerate(edges):
        for c, d in edges[index + 1:]:
            x = _segment_intersection_x(a, b, c, d)
            if x is not None and xmin - _EPS <= x <= xmax + _EPS:
                critical.append(min(xmax, max(xmin, x)))
    critical = sorted(set(round(value, 12) for value in critical))
    samples = list(critical)
    samples.extend((left + right) / 2.0 for left, right in zip(critical, critical[1:]) if right - left > _EPS)
    for x in samples:
        intervals: list[tuple[float, float]] = []
        for polygon in polygons:
            intervals.extend(_intervals_at_x(polygon, x))
        if not _intervals_cover(intervals, ymin, ymax):
            return False
    return True


def _triangle_box_intersects(triangle: Sequence[Sequence[float]], box_min: Sequence[float], box_max: Sequence[float]) -> bool:
    """Triangle/AABB SAT, with a tiny inset so boundary contact remains allowed."""
    # Inset beyond the policy round-trip epsilon: a face exactly on the clear
    # prism boundary is contact, not an obstruction.
    inset_min = [box_min[index] + 2.0 * _EPS for index in range(3)]
    inset_max = [box_max[index] - 2.0 * _EPS for index in range(3)]
    if any(inset_min[index] >= inset_max[index] for index in range(3)):
        return False
    vertices = [tuple(triangle[index][axis] for axis in range(3)) for index in range(3)]
    center = tuple((inset_min[axis] + inset_max[axis]) / 2.0 for axis in range(3))
    half = tuple((inset_max[axis] - inset_min[axis]) / 2.0 for axis in range(3))
    relative = [tuple(vertex[axis] - center[axis] for axis in range(3)) for vertex in vertices]
    edges = [tuple(vertices[index + 1][axis] - vertices[index][axis] for axis in range(3)) for index in range(2)]
    edges.append(tuple(vertices[0][axis] - vertices[2][axis] for axis in range(3)))
    axes: list[tuple[float, float, float]] = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
    normal = (
        edges[0][1] * edges[1][2] - edges[0][2] * edges[1][1],
        edges[0][2] * edges[1][0] - edges[0][0] * edges[1][2],
        edges[0][0] * edges[1][1] - edges[0][1] * edges[1][0],
    )
    axes.append(normal)
    for edge in edges:
        for box_axis in ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)):
            axes.append((edge[1] * box_axis[2] - edge[2] * box_axis[1], edge[2] * box_axis[0] - edge[0] * box_axis[2], edge[0] * box_axis[1] - edge[1] * box_axis[0]))
    for axis in axes:
        length = math.sqrt(sum(component * component for component in axis))
        if length <= _EPS * _EPS:
            continue
        unit = tuple(component / length for component in axis)
        tri_min = min(sum(relative[index][axis_index] * unit[axis_index] for axis_index in range(3)) for index in range(3))
        tri_max = max(sum(relative[index][axis_index] * unit[axis_index] for axis_index in range(3)) for index in range(3))
        radius = sum(half[axis_index] * abs(unit[axis_index]) for axis_index in range(3))
        if tri_max < -radius or tri_min > radius:
            return False
    return True


def _point_in_projected_triangle(point: tuple[float, float], triangle: Sequence[tuple[float, float]]) -> bool:
    signs = [_cross_2d(triangle[index], triangle[(index + 1) % 3], point) for index in range(3)]
    return not (min(signs) < -_EPS and max(signs) > _EPS)


def _profile_coverage(
    triangles: Sequence[Sequence[Sequence[float]]],
    tangent_axis: int,
    normal_axis: int,
    y_axis: int,
    tangent_band: tuple[float, float],
    rectangle: tuple[float, float, float, float],
    terminal_plane: float,
) -> bool:
    polygons: list[tuple[tuple[float, float], ...]] = []
    for triangle in triangles:
        tangent_values = [point[tangent_axis] for point in triangle]
        # A projected triangle from an inset/beveled face is not evidence of
        # the actual mating plane.  Require the complete triangle to be
        # coplanar with the terminal plane; the band remains the protected
        # interval that the profile belongs to.
        if not all(abs(value - terminal_plane) <= _EPS for value in tangent_values):
            continue
        if max(tangent_values) < tangent_band[0] - _EPS or min(tangent_values) > tangent_band[1] + _EPS:
            continue
        polygons.append(_project(triangle, (normal_axis, y_axis)))
    return _coverage(polygons, rectangle)


def _protected_band_surface_coverage(
    triangles: Sequence[Sequence[Sequence[float]]],
    tangent_band: tuple[float, float],
    normal_min: float,
    normal_max: float,
    top: float,
) -> bool:
    """Require each outer wall surface to remain continuous through the band."""
    for normal_plane in (normal_min, normal_max):
        polygons = [
            _project(triangle, (0, 1))
            for triangle in triangles
            if all(abs(point[2] - normal_plane) <= _EPS for point in triangle)
        ]
        if not _coverage(polygons, (tangent_band[0], tangent_band[1], 0.0, top)):
            return False
    for y_plane in (0.0, top):
        polygons = [
            _project(triangle, (0, 2))
            for triangle in triangles
            if all(abs(point[1] - y_plane) <= _EPS for point in triangle)
        ]
        if not _coverage(polygons, (tangent_band[0], tangent_band[1], normal_min, normal_max)):
            return False
    return True


def _validate_floor(triangles: Sequence[Sequence[Sequence[float]]], profile: dict[str, Any], dimensions: dict[str, Any], errors: list[str]) -> None:
    floor = dimensions["floor_interface"]
    expected = profile["bounds"]
    errors.extend(_bounds_errors(_measured_bounds(triangles), expected))
    top = float(floor["top_y_m"])
    underside = float(floor["underside_y_m"])
    recess = float(floor["max_recess_depth_m"])
    if any(point[1] > top + _EPS for triangle in triangles for point in triangle):
        errors.append("floor has positive relief above walking datum")
    if any(point[1] < underside - _EPS for triangle in triangles for point in triangle):
        errors.append("floor extends below slab underside")
    top_triangles = [triangle for triangle in triangles if all( top - recess - _EPS <= point[1] <= top + _EPS for point in triangle)]
    xmin, xmax = expected["min"][0], expected["max"][0]
    zmin, zmax = expected["min"][2], expected["max"][2]
    if not _coverage([_project(triangle, (0, 2)) for triangle in top_triangles], (xmin, xmax, zmin, zmax)):
        errors.append("floor top projected coverage has a hole or exceeds maximum recess")
    for edge_name, tangent_axis, edge, rectangle, normal_axis in (
        ("left", 0, xmin, (zmin, zmax, underside, top), 2),
        ("right", 0, xmax, (zmin, zmax, underside, top), 2),
        ("front", 2, zmin, (xmin, xmax, underside, top), 0),
        ("back", 2, zmax, (xmin, xmax, underside, top), 0),
    ):
        polygons: list[tuple[tuple[float, float], ...]] = []
        for triangle in triangles:
            boundary_values = [point[tangent_axis] for point in triangle]
            if not all(abs(value - edge) <= _EPS for value in boundary_values):
                continue
            polygons.append(_project(triangle, (normal_axis, 1)))
        if not _coverage(polygons, rectangle):
            errors.append(f"floor {edge_name} mating boundary/slab profile is incomplete")


def _validate_wall_or_door(triangles: Sequence[Sequence[Sequence[float]]], profile: dict[str, Any], dimensions: dict[str, Any], errors: list[str], doorway: bool) -> None:
    edge = dimensions["edge_interface"]
    errors.extend(_bounds_errors(_measured_bounds(triangles), profile["bounds"]))
    tangent_min = float(edge["one_cell_tangent_min_m"])
    tangent_max = float(edge["one_cell_tangent_max_m"])
    band = float(edge["terminal_mating_band_m"])
    normal_min = float(edge["visual_normal_min_m"])
    normal_max = float(edge["visual_normal_max_m"])
    top = float(edge["shared_visual_top_y_m"])
    for label, tangent_band in (("left", (tangent_min, tangent_min + band)), ("right", (tangent_max - band, tangent_max))):
        if not _profile_coverage(
            triangles,
            0,
            2,
            1,
            tangent_band,
            (normal_min, normal_max, 0.0, top),
            tangent_min if label == "left" else tangent_max,
        ) or not _protected_band_surface_coverage(
            triangles, tangent_band, normal_min, normal_max, top
        ):
            errors.append(f"terminal {label} mating band does not cover the full shared profile")
    if doorway:
        clear = dimensions["doorway_open_interface"]["clear_prism"]
        # The opening is THROUGH the wall, so a face sealing its front/back
        # normal boundary is an obstruction, not permitted frame contact.
        # Counter the SAT helper's 2*epsilon inset on this axis and retain
        # coverage of the accepted geometry round-trip tolerance. Tangent/Y
        # boundary contact (jambs, lintel and floor) remains allowed.
        normal_margin = 4.0 * _EPS
        box_min = (float(clear["tangent_min_m"]), float(clear["bottom_y_m"]), float(clear["normal_min_m"]) - normal_margin)
        box_max = (float(clear["tangent_max_m"]), float(clear["top_y_m"]), float(clear["normal_max_m"]) + normal_margin)
        if any(_triangle_box_intersects(triangle, box_min, box_max) for triangle in triangles):
            errors.append("doorway clear prism is intersected by actual triangle geometry")


def _validate_pillar(triangles: Sequence[Sequence[Sequence[float]]], profile: dict[str, Any], dimensions: dict[str, Any], errors: list[str]) -> None:
    edge = dimensions["edge_interface"]
    actual = _measured_bounds(triangles)
    if not _close(actual["min"][1], float(edge["base_y_m"])):
        errors.append("pillar base contact does not reach the floor datum")
    if not _close(actual["max"][1], float(edge["shared_visual_top_y_m"])):
        errors.append("pillar top contact does not reach the shared structural top")
    if actual["min"][0] < -2.0 - _EPS or actual["max"][0] > 2.0 + _EPS or actual["min"][2] < -2.0 - _EPS or actual["max"][2] > 2.0 + _EPS:
        errors.append("pillar X/Z envelope exceeds the one-cell envelope")
    for label, y in (("base", float(edge["base_y_m"])), ("top", float(edge["shared_visual_top_y_m"]))):
        found = False
        for triangle in triangles:
            if all(_close(point[1], y) for point in triangle):
                projected = tuple((point[0], point[2]) for point in triangle)
                if abs(_cross_2d(projected[0], projected[1], projected[2])) > _EPS * _EPS and _point_in_projected_triangle((0.0, 0.0), projected):
                    found = True
                    break
        if not found:
            errors.append(f"pillar {label} contact face is missing at the required center")


def validate_geometry(module_id: str, triangles: Sequence[Sequence[Sequence[float]]], dimensions: dict[str, Any]) -> dict[str, Any]:
    """Validate actual runtime triangles against the canonical visual interface."""
    dimensions = _validate_dimensions(dimensions)
    normalised, errors = _normalise_triangles(triangles)
    measurements: dict[str, Any] = {"triangle_count": len(normalised)}
    if normalised:
        measurements["bounds"] = _measured_bounds(normalised)
    if errors:
        return {"status": "fail", "errors": sorted(set(errors)), "measurements": measurements}
    profile = module_profile(module_id, dimensions)
    if profile["status"] == "hold":
        return {"status": "hold", "errors": [profile["reason"]], "measurements": measurements, "module_id": module_id, "held": True, "reason": profile["reason"]}
    measurements["bounds"] = _measured_bounds(normalised)
    validation_errors: list[str] = []
    if profile["family"] in ("floor", "corridor_floor"):
        _validate_floor(normalised, profile, dimensions, validation_errors)
    elif profile["family"] == "wall":
        _validate_wall_or_door(normalised, profile, dimensions, validation_errors, doorway=False)
    elif profile["family"] == "doorway":
        _validate_wall_or_door(normalised, profile, dimensions, validation_errors, doorway=True)
    elif profile["family"] == "pillar":
        _validate_pillar(normalised, profile, dimensions, validation_errors)
    validation_errors = sorted(set(validation_errors))
    result: dict[str, Any] = {
        "status": "fail" if validation_errors else "pass",
        "errors": validation_errors,
        "measurements": measurements,
        "module_id": module_id,
        "family": profile["family"],
    }
    return result
