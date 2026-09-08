from __future__ import annotations

import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ADDITIONAL_PROPS = {
    "fabrication_station_derelict_v1": "res://assets/imported/props/dressing/fabrication_station_derelict_v1.glb",
    "medical_stasis_pod_derelict_v1": "res://assets/imported/props/dressing/medical_stasis_pod_derelict_v1.glb",
    "power_cell_cradle_derelict_v1": "res://assets/imported/props/dressing/power_cell_cradle_derelict_v1.glb",
    "salvage_sorter_derelict_v1": "res://assets/imported/props/dressing/salvage_sorter_derelict_v1.glb",
}


def _load(relative: str) -> dict:
    return json.loads((PROJECT_ROOT / relative).read_text(encoding="utf-8"))


def test_additional_derelict_props_are_new_catalogued_visuals() -> None:
    catalog = _load("data/kits/gameplay_prop_v0.json")["props"]
    index = _load("data/props/visual_bindings.generated.json")["dressing"]
    hashes: set[str] = set()

    for prop_id, mesh_path in ADDITIONAL_PROPS.items():
        assert prop_id in catalog
        assert catalog[prop_id]["mesh_path"] == mesh_path
        asset = PROJECT_ROOT / mesh_path.removeprefix("res://")
        assert asset.is_file(), mesh_path

        binding = index[prop_id]
        assert binding["visual_scene_path"] == mesh_path
        assert binding["binding"] == {"ids": [prop_id], "namespace": "visual_prop_id"}
        source_hash = binding["source"]["sha256"]
        assert source_hash not in hashes, f"duplicate visual asset hash for {prop_id}"
        hashes.add(source_hash)

    assert len(hashes) == len(ADDITIONAL_PROPS)
