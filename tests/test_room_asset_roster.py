from __future__ import annotations

import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _load(relative: str) -> dict:
    return json.loads((PROJECT_ROOT / relative).read_text(encoding="utf-8"))


def test_derelict_room_roster_binds_real_visuals() -> None:
    catalog = _load("data/kits/gameplay_prop_v0.json")
    props = catalog["props"]
    assert props["loot_crate"]["mesh_path"] == (
        "res://assets/imported/props/dressing/loot_container_derelict_v1.glb"
    )
    assert props["workbench"]["mesh_path"] == (
        "res://assets/imported/props/dressing/maintenance_bench.glb"
    )

    for prop_id in ("loot_crate", "workbench"):
        mesh_path = props[prop_id]["mesh_path"]
        assert mesh_path.startswith("res://")
        asset = PROJECT_ROOT / mesh_path.removeprefix("res://")
        assert asset.is_file(), mesh_path

    index = _load("data/props/visual_bindings.generated.json")
    loot = index["dressing"]["loot_container_derelict_v1"]
    assert loot["visual_scene_path"] == props["loot_crate"]["mesh_path"]
    assert loot["provenance"]["license_state"] == "paid-private"
    assert loot["source"]["mesh_count"] > 0


def test_room_roster_has_structural_and_dressing_inputs() -> None:
    structural = _load("data/kits/ship_structural_v0.json")
    assert len(structural["modules"]) == 15
    assert {"floor_1x1", "wall_straight_1x1", "doorway_frame_open_1x1"}.issubset(
        {module["module_id"] for module in structural["modules"]}
    )
    assert {"cargo_pallet", "maintenance_bench", "service_rack"}.issubset(
        set(_load("data/props/visual_bindings.generated.json")["dressing"])
    )
