from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.structural_source_contract import (
    STRUCTURAL_SOURCE_MODULE_IDS,
    build_source_record,
    canonical_json,
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


def test_source_recovery_allowlist_is_exactly_the_eight_integrity_families() -> None:
    assert STRUCTURAL_SOURCE_MODULE_IDS == (
        "floor_1x1",
        "floor_2x1",
        "corridor_floor_1x1",
        "corridor_floor_1x2",
        "wall_straight_1x1",
        "doorway_frame_open_1x1",
        "pillar_support_1x1",
        "ramp_up_1x2",
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
])
def test_all_eight_modules_load_from_live_contracts(module_id: str) -> None:
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


def test_minimal_floor_fixture_contains_the_structural_contract_shape() -> None:
    document = json.loads(
        (FIXTURE_ROOT / "floor_1x1_contract.json").read_text(encoding="utf-8")
    )

    assert document["document_kind"] == "modular_asset_spec"
    assert document["module_id"] == "floor_1x1"
    assert len(document["sockets"]) == 4
