from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from tools.structural_source_contract import (
    FOCUSED_NINE_CANDIDATE_MODULE_IDS,
    STRUCTURAL_SOURCE_MODULE_IDS,
    build_source_record,
    canonical_json,
    load_candidate_source_spec,
    load_source_spec,
    source_output_paths,
    y_up_to_z_up,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = Path(__file__).parent / "fixtures" / "structural_source_contracts"
CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.json"
)
GLB_RELATIVE = Path(
    "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"
)


def _write_floor_fixture(tmp_path: Path, document: dict) -> None:
    contract_path = tmp_path / CONTRACT_RELATIVE
    contract_path.parent.mkdir(parents=True)
    contract_path.write_text(json.dumps(document), encoding="utf-8")

    glb_path = tmp_path / GLB_RELATIVE
    glb_path.parent.mkdir(parents=True)
    glb_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())


def test_contract_coordinates_convert_y_up_to_blender_z_up() -> None:
    assert y_up_to_z_up((2.0, 3.0, -4.0)) == (2.0, -4.0, 3.0)


def test_floor_contract_exposes_exact_socket_anchor_names() -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")

    assert [socket.anchor_name for socket in spec.sockets] == [
        "Anchor_SOCK_floor_edge_north_01",
        "Anchor_SOCK_floor_edge_south_01",
        "Anchor_SOCK_floor_edge_east_01",
        "Anchor_SOCK_floor_edge_west_01",
    ]


def test_unknown_or_path_traversal_module_is_rejected() -> None:
    for module_id in ("not_a_structural_module", "../../floor_1x1"):
        with pytest.raises(ValueError, match="unsupported structural source module"):
            load_source_spec(PROJECT_ROOT, module_id)


def test_source_recovery_allowlist_is_exactly_the_fifteen_structural_families() -> None:
    assert STRUCTURAL_SOURCE_MODULE_IDS == (
        "floor_1x1",
        "floor_2x1",
        "corridor_floor_1x1",
        "corridor_floor_1x2",
        "wall_straight_1x1",
        "doorway_frame_open_1x1",
        "pillar_support_1x1",
        "ramp_up_1x2",
        "bulkhead_portal_2x1",
        "ceiling_cap_1x1",
        "doorway_frame_blocked_1x1",
        "wall_end_cap",
        "wall_inner_corner",
        "wall_outer_corner",
        "wall_t_junction",
    )


@pytest.mark.parametrize("module_id", [
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
    "bulkhead_portal_2x1",
    "ceiling_cap_1x1",
    "doorway_frame_blocked_1x1",
    "wall_end_cap",
    "wall_inner_corner",
    "wall_outer_corner",
    "wall_t_junction",
])
def test_all_fifteen_modules_load_from_live_contracts(module_id: str) -> None:
    spec = load_source_spec(PROJECT_ROOT, module_id)
    assert spec.module_id == module_id
    assert spec.kit_id == "ship_structural_v0"
    assert len(spec.sockets) > 0
    assert spec.contract_sha256
    assert spec.source_glb_sha256


def test_source_record_is_canonical_and_has_no_clock_field(tmp_path: Path) -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    blend_path, _record_path = source_output_paths(tmp_path, spec.module_id)

    raw = canonical_json(build_source_record(spec, blend_path))
    document = json.loads(raw)

    assert raw.endswith(b"\n")
    assert raw == canonical_json(document)
    assert document["document_kind"] == "structural_blender_source"
    assert document["schema_version"] == "1.0.0"
    assert "generated_at" not in document
    assert document["sockets"][0]["anchor_name"] == (
        "Anchor_SOCK_floor_edge_north_01"
    )


def test_contract_sha256_is_raw_file_hash() -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    raw = spec.contract_path.read_bytes()

    assert spec.contract_sha256 == hashlib.sha256(raw).hexdigest()


def test_socket_z_up_positions_match_contract_after_conversion() -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")

    for socket in spec.sockets:
        assert socket.position_z_up == y_up_to_z_up(socket.position_y_up)


def test_canonical_json_rejects_non_finite_values() -> None:
    with pytest.raises(ValueError):
        canonical_json({"x": float("nan")})


def test_source_output_paths_containment_rejects_path_traversal(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="unsupported structural source module"):
        source_output_paths(tmp_path, "../evil")


def test_mismatched_module_contract_is_rejected(tmp_path: Path) -> None:
    contract_path = tmp_path / CONTRACT_RELATIVE
    contract_path.parent.mkdir(parents=True)
    contract_path.write_bytes((FIXTURE_ROOT / "mismatched_module_contract.json").read_bytes())

    glb_path = tmp_path / GLB_RELATIVE
    glb_path.parent.mkdir(parents=True)
    glb_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())

    with pytest.raises(ValueError, match="contract module_id mismatch"):
        load_source_spec(tmp_path, "floor_1x1")


def test_invalid_schema_version_is_rejected(tmp_path: Path) -> None:
    document = json.loads((FIXTURE_ROOT / "floor_1x1_contract.json").read_text())
    document["schema_version"] = "2.0.0"
    _write_floor_fixture(tmp_path, document)

    with pytest.raises(ValueError, match="schema_version"):
        load_source_spec(tmp_path, "floor_1x1")


def test_mismatched_asset_id_is_rejected(tmp_path: Path) -> None:
    document = json.loads((FIXTURE_ROOT / "floor_1x1_contract.json").read_text())
    document["asset_id"] = "floor_2x1"
    _write_floor_fixture(tmp_path, document)

    with pytest.raises(ValueError, match="asset_id mismatch"):
        load_source_spec(tmp_path, "floor_1x1")


def test_inverted_bounds_are_rejected(tmp_path: Path) -> None:
    document = json.loads((FIXTURE_ROOT / "floor_1x1_contract.json").read_text())
    document["bounds"]["local_min_m"][0] = 3.0
    _write_floor_fixture(tmp_path, document)

    with pytest.raises(ValueError, match="bounds"):
        load_source_spec(tmp_path, "floor_1x1")


def test_oversized_integer_is_rejected_as_invalid_float(tmp_path: Path) -> None:
    document = json.loads((FIXTURE_ROOT / "floor_1x1_contract.json").read_text())
    document["grid_step_m"] = 10**1000
    _write_floor_fixture(tmp_path, document)

    with pytest.raises(ValueError, match="grid_step_m"):
        load_source_spec(tmp_path, "floor_1x1")


@pytest.mark.parametrize("relative_path", [CONTRACT_RELATIVE, GLB_RELATIVE])
def test_source_input_symlink_escape_is_rejected(
    tmp_path: Path, relative_path: Path
) -> None:
    real_path = PROJECT_ROOT / relative_path
    linked_path = tmp_path / relative_path
    linked_path.parent.mkdir(parents=True)

    if relative_path == CONTRACT_RELATIVE:
        linked_path.symlink_to(real_path)
    else:
        contract_path = tmp_path / CONTRACT_RELATIVE
        contract_path.parent.mkdir(parents=True)
        contract_path.write_bytes((PROJECT_ROOT / CONTRACT_RELATIVE).read_bytes())
        linked_path.symlink_to(real_path)

    with pytest.raises((ValueError, OSError)):
        load_source_spec(tmp_path, "floor_1x1")


def test_contract_symlink_loop_is_reported_as_value_error(tmp_path: Path) -> None:
    contract_path = tmp_path / CONTRACT_RELATIVE
    contract_path.parent.mkdir(parents=True)
    try:
        contract_path.symlink_to(contract_path.name)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    glb_path = tmp_path / GLB_RELATIVE
    glb_path.parent.mkdir(parents=True)
    glb_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())

    with pytest.raises(ValueError, match="cannot resolve structural contract path"):
        load_source_spec(tmp_path, "floor_1x1")


def test_source_output_module_symlink_loop_is_reported_as_value_error(
    tmp_path: Path,
) -> None:
    loop_root = tmp_path / "loop-root"
    try:
        loop_root.symlink_to(loop_root.name, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    with pytest.raises(ValueError, match="cannot resolve source output root path"):
        source_output_paths(loop_root, "floor_1x1")


def test_minimal_floor_fixture_contains_the_structural_contract_shape() -> None:
    document = json.loads(
        (FIXTURE_ROOT / "floor_1x1_contract.json").read_text(encoding="utf-8")
    )

    assert document["document_kind"] == "modular_asset_spec"
    assert document["module_id"] == "floor_1x1"
    assert len(document["sockets"]) == 4


CANDIDATE_CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
)
CANDIDATE_GLB_RELATIVE = Path(
    "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
)


def _write_pressure_door_fixture(tmp_path: Path, *, with_glb: bool = True) -> Path:
    contract_path = tmp_path / CANDIDATE_CONTRACT_RELATIVE
    contract_path.parent.mkdir(parents=True)
    contract_path.write_bytes((PROJECT_ROOT / CANDIDATE_CONTRACT_RELATIVE).read_bytes())

    staged_path = tmp_path / CANDIDATE_GLB_RELATIVE
    if with_glb:
        staged_path.parent.mkdir(parents=True)
        staged_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())
    return staged_path


def test_focused_nine_candidate_allowlist_is_pressure_door_only() -> None:
    assert FOCUSED_NINE_CANDIDATE_MODULE_IDS == ("pressure_door_1x1",)


def test_pressure_door_candidate_reuses_doorway_contract_shape(tmp_path: Path) -> None:
    staged_path = _write_pressure_door_fixture(tmp_path)

    spec = load_candidate_source_spec(
        tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE
    )
    doorway = load_source_spec(PROJECT_ROOT, "doorway_frame_open_1x1")

    assert spec.module_id == "pressure_door_1x1"
    assert spec.kit_id == doorway.kit_id
    assert spec.module_family == doorway.module_family == "portal"
    assert spec.grid_step_m == doorway.grid_step_m == 4.0
    assert spec.footprint_cells == doorway.footprint_cells == (1, 0)
    assert spec.bounds_min_y_up == doorway.bounds_min_y_up
    assert spec.bounds_max_y_up == doorway.bounds_max_y_up
    assert spec.nav_blocker is True
    assert [(socket.socket_id, socket.compatible_kinds) for socket in spec.sockets] == [
        (socket.socket_id, socket.compatible_kinds) for socket in doorway.sockets
    ]
    assert spec.source_glb_path == staged_path
    assert spec.source_glb_sha256


def test_pressure_door_candidate_rejects_missing_staged_glb(tmp_path: Path) -> None:
    _write_pressure_door_fixture(tmp_path, with_glb=False)

    with pytest.raises(ValueError, match="missing candidate source GLB"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE)


@pytest.mark.parametrize(
    "module_id,source_path",
    [
        ("doorway_frame_open_1x1", CANDIDATE_GLB_RELATIVE),
        ("../../pressure_door_1x1", CANDIDATE_GLB_RELATIVE),
        ("pressure_door_1x1", Path("assets/imported/structural/pressure_door_1x1.glb")),
        ("pressure_door_1x1", Path("assets/_staging/focused_nine/structural/pressure_door_1x1/../pressure_door_1x1.glb")),
        ("pressure_door_1x1", Path("assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.txt")),
    ],
)
def test_pressure_door_candidate_rejects_invalid_identity_or_path(
    tmp_path: Path, module_id: str, source_path: Path
) -> None:
    _write_pressure_door_fixture(tmp_path)

    with pytest.raises(ValueError):
        load_candidate_source_spec(tmp_path, module_id, source_path)


def test_pressure_door_candidate_rejects_absolute_external_path(tmp_path: Path) -> None:
    _write_pressure_door_fixture(tmp_path)
    external_path = tmp_path / "outside.glb"
    external_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())

    with pytest.raises(ValueError, match="candidate source GLB"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", external_path)


def test_pressure_door_candidate_rejects_symlink_escape(tmp_path: Path) -> None:
    staged_path = _write_pressure_door_fixture(tmp_path, with_glb=False)
    external_path = tmp_path / "outside.glb"
    external_path.write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())
    staged_path.parent.mkdir(parents=True, exist_ok=True)
    staged_path.symlink_to(external_path)

    with pytest.raises(ValueError, match="candidate source GLB"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE)


def test_pressure_door_candidate_rejects_symlink_plus_traversal(tmp_path: Path) -> None:
    _write_pressure_door_fixture(tmp_path)
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir()
    escape = tmp_path / CANDIDATE_GLB_RELATIVE.parent / "escape"
    escape.symlink_to(outside_dir, target_is_directory=True)
    source_path = CANDIDATE_GLB_RELATIVE.parent / "escape" / ".." / CANDIDATE_GLB_RELATIVE.name

    with pytest.raises(ValueError, match="candidate source GLB"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", source_path)


def test_pressure_door_candidate_rejects_source_glb_symlink_loop(
    tmp_path: Path,
) -> None:
    staged_path = _write_pressure_door_fixture(tmp_path, with_glb=False)
    staged_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        staged_path.symlink_to(staged_path.name)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    with pytest.raises(ValueError, match="candidate source GLB contains symlink"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE)


def test_pressure_door_candidate_rejects_external_symlink_ancestor(
    tmp_path: Path,
) -> None:
    staged_path = _write_pressure_door_fixture(tmp_path, with_glb=False)
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir()
    (outside_dir / staged_path.name).write_bytes((PROJECT_ROOT / GLB_RELATIVE).read_bytes())
    alias = staged_path.parent.parent / "alias"
    alias.parent.mkdir(parents=True, exist_ok=True)
    try:
        alias.symlink_to(outside_dir, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")
    source_path = alias / staged_path.name

    with pytest.raises(ValueError, match="candidate source GLB"):
        load_candidate_source_spec(tmp_path, "pressure_door_1x1", source_path)
