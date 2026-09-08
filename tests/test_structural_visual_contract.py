from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import pytest

from tools.structural_visual_contract import (
    VisualContractError,
    load_dimensions,
    module_profile,
    validate_geometry,
)


ROOT = Path(__file__).parents[1]
POLICY = ROOT / "data/art/structural_visual_dimensions.v1.json"


def _box(minimum: tuple[float, float, float], maximum: tuple[float, float, float]):
    x0, y0, z0 = minimum
    x1, y1, z1 = maximum
    v = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    faces = (
        (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
        (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7),
    )
    triangles = []
    for a, b, c, d in faces:
        triangles.extend(((v[a], v[b], v[c]), (v[a], v[c], v[d])))
    return triangles


def _floor_with_top_triangles(*, omit_one_top: bool = False, raised: float = 0.0):
    triangles = _box((-2.0, -0.25, -2.0), (2.0, 0.0, 2.0))
    if raised:
        triangles[0] = tuple((x, y + raised if y == 0 else y, z) for x, y, z in triangles[0])
    if omit_one_top:
        triangles = triangles[:2] + triangles[3:]
    return triangles


def _wall():
    return _box((-2.0, 0.0, -0.1), (2.0, 3.2, 0.1))


def _wall_with_recessed_terminal_faces():
    return _box((-1.9, 0.0, -0.1), (1.9, 3.1, 0.1)) + _box((-2.0, 3.1, -0.1), (2.0, 3.2, 0.1))


def _wall_with_discontinuous_protected_band():
    body = _box((-1.9, 0.0, -0.1), (1.9, 3.2, 0.1))
    end_faces = [
        ((-2.0, 0.0, -0.1), (-2.0, 0.0, 0.1), (-2.0, 3.2, 0.1)),
        ((-2.0, 0.0, -0.1), (-2.0, 3.2, 0.1), (-2.0, 3.2, -0.1)),
        ((2.0, 0.0, -0.1), (2.0, 3.2, 0.1), (2.0, 0.0, 0.1)),
        ((2.0, 0.0, -0.1), (2.0, 3.2, -0.1), (2.0, 3.2, 0.1)),
    ]
    return body + end_faces


def _wall_with_interior_protected_band_gap():
    # The end-cap sliver reaches x=-2, the body starts at x=-1.9, and the
    # missing [-1.98,-1.9] interval is inside the protected terminal band.
    return _box((-2.0, 0.0, -0.1), (-1.98, 3.2, 0.1)) + _box((-1.9, 0.0, -0.1), (2.0, 3.2, 0.1))


def _floor_with_beveled_left_boundary():
    triangles = _box((-1.9, -0.25, -2.0), (2.0, 0.0, 2.0))
    # Recessed top strip keeps the AABB and top projection but is not a planar
    # outer mating face.
    triangles.extend([
        ((-2.0, -0.02, -2.0), (-2.0, -0.02, 2.0), (-1.9, 0.0, 2.0)),
        ((-2.0, -0.02, -2.0), (-1.9, 0.0, 2.0), (-1.9, 0.0, -2.0)),
    ])
    # A sloped boundary strip projects to the complete slab profile, but no
    # triangle is coplanar with x=-2 across that profile.
    triangles.extend([
        ((-2.0, -0.25, -2.0), (-1.9, -0.25, 2.0), (-1.9, 0.0, 2.0)),
        ((-2.0, -0.25, -2.0), (-1.9, 0.0, 2.0), (-2.0, 0.0, -2.0)),
    ])
    return triangles


def _door_frame():
    parts = [
        _box((-2.0, 0.0, -0.1), (-0.6, 3.2, 0.1)),
        _box((0.6, 0.0, -0.1), (2.0, 3.2, 0.1)),
        _box((-0.6, 2.2, -0.1), (0.6, 3.2, 0.1)),
    ]
    return [triangle for part in parts for triangle in part]


@pytest.mark.parametrize("keys", [
    ("floor_interface", "max_recess_depth_m"),
    ("edge_interface", "terminal_mating_band_m"),
    ("global", "float_roundtrip_epsilon_m"),
    ("global", "required_object_scale", 0),
    ("global", "required_mesh_origin_offset_m", 0),
    ("coordinate_system", "allowed_yaw_degrees", 1),
])
def test_roundtrip_epsilon_cannot_relax_canonical_policy(tmp_path: Path, keys) -> None:
    policy = load_dimensions()
    parent = policy
    for key in keys[:-1]:
        parent = parent[key]
    parent[keys[-1]] += 0.00005
    path = tmp_path / "drifted-policy.json"
    path.write_text(json.dumps(policy))
    with pytest.raises(VisualContractError, match="must equal"):
        load_dimensions(path)
    with pytest.raises(VisualContractError, match="must equal"):
        module_profile("floor_1x1", policy)
    with pytest.raises(VisualContractError, match="must equal"):
        validate_geometry("floor_1x1", _box((-2, -0.25, -2), (2, 0, 2)), policy)


@pytest.mark.parametrize("blocking_faces", [
    _box((-2, 0, -.1), (2, 3.2, .1)),
    _door_frame() + _box((-.6, 0, -.1), (.6, 2.2, -.09999)),
    _door_frame() + _box((-.6, 0, .09999), (.6, 2.2, .1)),
])
def test_door_opening_cannot_be_sealed_at_its_front_or_back_boundary(blocking_faces):
    result = validate_geometry("doorway_frame_open_1x1", blocking_faces, load_dimensions())
    assert result["status"] == "fail", result
    assert any("clear prism" in error for error in result["errors"])


def test_default_policy_is_exact_reviewed_art_policy() -> None:
    policy = load_dimensions()
    assert hashlib.sha256(POLICY.read_bytes()).hexdigest() == (
        "5499c1921bc90492ba60015b8a046b41de047ac17892883821c41efb234ec43f"
    )
    assert policy["status"] == "approved_dimensions_pending_source_authority"
    assert policy["authority"]["integration_baseline_status"] == "operator_approval_required"
    assert policy["global"]["per_asset_dimension_overrides_allowed"] is False


def test_loader_rejects_missing_invalid_nonfinite_bool_and_overrides(tmp_path: Path) -> None:
    with pytest.raises(VisualContractError):
        load_dimensions(tmp_path / "missing.json")

    policy = load_dimensions()
    for mutation in (
        lambda p: p["global"].update(grid_step_m=True),
        lambda p: p["global"].update(deck_height_m=float("nan")),
        lambda p: p["global"].update(per_asset_dimension_overrides_allowed=True),
        lambda p: p.update(schema_version="9.0.0"),
        lambda p: p["floor_interface"].update(unknown_key=1),
        lambda p: p["ramp_interface"].update(footprint_cells=[True, 2]),
    ):
        candidate = json.loads(json.dumps(policy))
        mutation(candidate)
        path = tmp_path / f"bad-{len(list(tmp_path.iterdir()))}.json"
        path.write_text(json.dumps(candidate, allow_nan=True))
        with pytest.raises(VisualContractError):
            load_dimensions(path)


def test_module_profiles_support_core_and_hold_unknown() -> None:
    dimensions = load_dimensions()
    supported = (
        "floor_1x1", "floor_2x1", "corridor_floor_1x1",
        "corridor_floor_1x2", "wall_straight_1x1",
        "doorway_frame_open_1x1", "pillar_support_1x1",
    )
    for module_id in supported:
        profile = module_profile(module_id, dimensions)
        assert profile["status"] == "pass"
        assert profile["held"] is False
        assert profile["bounds"]["min"] < profile["bounds"]["max"]
    held = module_profile("ramp_up_1x2", dimensions)
    assert held["status"] == "hold"
    assert held["held"] is True
    assert held["reason"]


def test_floor_requires_exact_top_coverage_and_rejects_relief() -> None:
    dimensions = load_dimensions()
    result = validate_geometry("floor_1x1", _floor_with_top_triangles(), dimensions)
    assert result["status"] == "pass", result

    missing = validate_geometry(
        "floor_1x1", _floor_with_top_triangles(omit_one_top=True), dimensions
    )
    assert missing["status"] == "fail"
    assert any("coverage" in error or "mating" in error for error in missing["errors"])

    raised = validate_geometry(
        "floor_1x1", _floor_with_top_triangles(raised=0.01), dimensions
    )
    assert raised["status"] == "fail"
    assert any("relief" in error or "bounds" in error for error in raised["errors"])


def test_wall_accepts_reflected_winding_but_needs_terminal_profiles() -> None:
    dimensions = load_dimensions()
    triangles = [tuple(reversed(triangle)) for triangle in _wall()]
    assert validate_geometry("wall_straight_1x1", triangles, dimensions)["status"] == "pass"
    no_end_caps = [
        triangle for triangle in _wall()
        if not (all(abs(point[0] - 2.0) < 1e-9 for point in triangle)
                or all(abs(point[0] + 2.0) < 1e-9 for point in triangle))
    ]
    result = validate_geometry("wall_straight_1x1", no_end_caps, dimensions)
    assert result["status"] == "fail"
    assert any("terminal" in error for error in result["errors"])


def test_terminal_and_floor_mating_checks_reject_inset_or_beveled_faces() -> None:
    dimensions = load_dimensions()
    recessed_wall = validate_geometry(
        "wall_straight_1x1", _wall_with_recessed_terminal_faces(), dimensions
    )
    assert recessed_wall["status"] == "fail", recessed_wall
    assert any("terminal" in error for error in recessed_wall["errors"])

    discontinuous = validate_geometry(
        "wall_straight_1x1", _wall_with_discontinuous_protected_band(), dimensions
    )
    assert discontinuous["status"] == "fail", discontinuous
    assert any("terminal" in error for error in discontinuous["errors"])

    interior_gap = validate_geometry(
        "wall_straight_1x1", _wall_with_interior_protected_band_gap(), dimensions
    )
    assert interior_gap["status"] == "fail", interior_gap
    assert any("terminal" in error for error in interior_gap["errors"])

    beveled_floor = validate_geometry(
        "floor_1x1", _floor_with_beveled_left_boundary(), dimensions
    )
    assert beveled_floor["status"] == "fail", beveled_floor
    assert any("mating boundary" in error for error in beveled_floor["errors"])


def test_doorway_checks_actual_triangle_intersection_not_only_vertices() -> None:
    dimensions = load_dimensions()
    clear = validate_geometry("doorway_frame_open_1x1", _door_frame(), dimensions)
    assert clear["status"] == "pass", clear

    crossing = _door_frame() + [
        ((-0.8, 1.0, 0.0), (0.8, 1.0, 0.0), (0.0, 2.4, 0.0))
    ]
    blocked = validate_geometry("doorway_frame_open_1x1", crossing, dimensions)
    assert blocked["status"] == "fail"
    assert any("clear prism" in error for error in blocked["errors"])


def test_pillar_requires_base_and_top_contacts_and_rejects_bad_numbers() -> None:
    dimensions = load_dimensions()
    pillar = _box((-0.25, 0.0, -0.25), (0.25, 3.2, 0.25))
    assert validate_geometry("pillar_support_1x1", pillar, dimensions)["status"] == "pass"

    no_top = [triangle for triangle in pillar if not all(y >= 3.2 - 1e-9 for _, y, _ in triangle)]
    result = validate_geometry("pillar_support_1x1", no_top, dimensions)
    assert result["status"] == "fail"
    assert any("top contact" in error for error in result["errors"])

    nonfinite = validate_geometry(
        "floor_1x1", [[(0.0, 0.0, 0.0), (math.nan, 0.0, 0.0), (0.0, 0.0, 1.0)]], dimensions
    )
    assert nonfinite["status"] == "fail"
    assert any("non-finite" in error for error in nonfinite["errors"])


def test_unsupported_or_invalid_dimensions_fail_closed() -> None:
    dimensions = load_dimensions()
    held = validate_geometry("ceiling_cap_1x1", _box((-2, -0.25, -2), (2, 0, 2)), dimensions)
    assert held["status"] == "hold"
    assert held["errors"]
    empty = validate_geometry("floor_1x1", [], dimensions)
    assert empty["status"] == "fail"
    assert "geometry is empty" in empty["errors"]
