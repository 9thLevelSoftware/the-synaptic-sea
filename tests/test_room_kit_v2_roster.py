from __future__ import annotations

import copy
import json

import pytest

from tools.room_kit_contract import load_rows


EXPECTED_IMPROVED = {
    "fabrication_station_derelict_v1",
    "medical_stasis_pod_derelict_v1",
    "power_cell_cradle_derelict_v1",
    "salvage_sorter_derelict_v1",
}
EXPECTED_NEW = {
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



def roster_document(rows: list[dict]) -> dict:
    return {"schema_version": "1.0.0", "asset_pack": "room_kit_v2", "assets": rows}



def test_roster_is_the_frozen_four_plus_twelve_contract() -> None:
    rows = load_rows()

    assert len(rows) == 16
    assert {row["asset_id"] for row in rows if row["new"] is False} == EXPECTED_IMPROVED
    assert {row["asset_id"] for row in rows if row["new"] is True} == EXPECTED_NEW
    assert len({row["asset_id"] for row in rows}) == 16
    assert sum(row["new"] is True for row in rows) == 12



def test_roster_rows_preserve_exact_envelopes_roles_and_budgets() -> None:
    rows = {row["asset_id"]: row for row in load_rows()}

    assert rows["fabrication_station_derelict_v1"]["max_size_m"] == [1.8, 1.85, 1.1]
    assert rows["fabrication_station_derelict_v1"]["roles"] == [
        "maintenance",
        "engineering",
        "machine_shop",
    ]
    assert rows["medical_stasis_pod_derelict_v1"]["max_size_m"] == [2.2, 1.25, 1.1]
    assert rows["power_cell_cradle_derelict_v1"]["triangles_max"] == 4500
    assert rows["salvage_sorter_derelict_v1"]["roles"] == [
        "cargo",
        "storage",
        "tool_storage",
        "salvage",
    ]
    assert rows["oxygen_manifold_derelict_v1"]["roles"] == [
        "life_support",
        "engineering",
        "compartment",
    ]
    assert rows["cargo_restraint_frame_derelict_v1"]["max_size_m"] == [2.2, 1.7, 1.1]
    assert all(row["footprint_cells"] == [1, 1] for row in rows.values())
    assert all(row["behavior"] == "static_dressing" for row in rows.values())



def test_duplicate_fails(tmp_path) -> None:
    rows = load_rows()
    rows[-1] = copy.deepcopy(rows[0])
    path = tmp_path / "duplicate.json"
    path.write_text(json.dumps(roster_document(rows)), encoding="utf-8")

    with pytest.raises(AssertionError, match="unique"):
        load_rows(path)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("max_size_m", [1.0, float("inf"), 1.0]),
        ("max_size_m", [0.0, 1.0, 1.0]),
        ("triangles_max", 0),
        ("material_max", 5),
        ("roles", ["Engineering"]),
        ("footprint_cells", [2, 1]),
        ("behavior", "dynamic_system"),
    ],
)
def test_invalid_row_contract_fails(tmp_path, field, value) -> None:
    rows = load_rows()
    rows[0][field] = value
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps(roster_document(rows)), encoding="utf-8")

    with pytest.raises(AssertionError):
        load_rows(path)
