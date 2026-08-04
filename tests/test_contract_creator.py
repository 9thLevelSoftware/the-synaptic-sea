from __future__ import annotations

import pytest

from tools.blender_addons.structural_module_toolkit.contract_creator import (
    FAMILY_TEMPLATES,
    create_draft_contract,
)


REQUIRED_FAMILIES = (
    "floor",
    "corridor_floor",
    "wall",
    "portal",
    "support",
    "ceiling",
    "vertical_transition",
)


def test_floor_template_generates_edge_sockets() -> None:
    contract = create_draft_contract("test_floor", "floor", (2, 1))

    assert len(contract["sockets"]) == 4
    assert contract["bounds"]["placement_origin"] == "cell-center-floor"
    assert contract["footprint_cells"] == [2, 1]
    assert [socket["id"] for socket in contract["sockets"]] == [
        "floor_edge_north_01",
        "floor_edge_south_01",
        "floor_edge_east_01",
        "floor_edge_west_01",
    ]
    assert contract["sockets"][0]["position_m"] == [0.0, 0.0, 2.0]
    assert contract["sockets"][2]["position_m"] == [4.0, 0.0, 0.0]


def test_wall_template_generates_three_sockets() -> None:
    contract = create_draft_contract("test_wall", "wall", (1, 0))

    assert len(contract["sockets"]) == 3
    assert contract["bounds"]["placement_origin"] == "edge-center"
    assert {socket["kind"] for socket in contract["sockets"]} == {
        "wall_edge",
        "wall_face",
    }


def test_portal_template_generates_four_sockets() -> None:
    contract = create_draft_contract("test_portal", "portal", (1, 1))

    assert len(contract["sockets"]) == 4
    assert [socket["id"] for socket in contract["sockets"]] == [
        "portal_edge_north_01",
        "portal_edge_south_01",
        "portal_jamb_left_01",
        "portal_jamb_right_01",
    ]


def test_contract_has_required_fields() -> None:
    required = {
        "schema_version",
        "document_kind",
        "asset_id",
        "module_id",
        "category",
        "kit_id",
        "module_family",
        "grid_step_m",
        "bounds",
        "footprint_cells",
        "sockets",
        "collision",
    }
    bounds_required = {
        "local_min_m",
        "local_max_m",
        "placement_origin",
        "mesh_origin_offset_m",
    }

    for family in REQUIRED_FAMILIES:
        contract = create_draft_contract(f"test_{family}", family, (2, 1))
        assert required <= contract.keys()
        assert bounds_required <= contract["bounds"].keys()
        assert contract["collision"] == {
            "proxy_shape": "box",
            "nav_blocker": False,
        }
        assert len(contract["sockets"]) == FAMILY_TEMPLATES[family].socket_count


def test_contract_creator_rejects_unknown_family() -> None:
    with pytest.raises(ValueError, match="unsupported structural family"):
        create_draft_contract("test", "unknown", (1, 1))


def test_contract_creator_rejects_invalid_footprint() -> None:
    with pytest.raises(ValueError, match="footprint_cells"):
        create_draft_contract("test", "floor", (0, 1))
