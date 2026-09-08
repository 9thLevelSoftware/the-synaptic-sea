extends SceneTree

const BuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH := "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH := "res://data/kits/ship_structural_v0.json"
const REQUIRED_IDS := [
    "fabrication_station_derelict_v1",
    "medical_stasis_pod_derelict_v1",
    "power_cell_cradle_derelict_v1",
    "salvage_sorter_derelict_v1",
]

func _initialize() -> void:
    var layout: Dictionary = _json(LAYOUT_PATH)
    var prototype: Dictionary = layout.get("prototype", {}) as Dictionary
    prototype["goal_room"] = "bridge_01"
    layout["prototype"] = prototype
    var builder := BuilderScript.new()
    var gameplay: Dictionary = builder.build(layout)
    var placed: Array = gameplay.get("placed_props", []) as Array
    var found: Dictionary = {}
    for raw in placed:
        if raw is Dictionary:
            var visual_id := str((raw as Dictionary).get("visual_id", ""))
            if not visual_id.is_empty():
                found[visual_id] = true
    for required_id in REQUIRED_IDS:
        if not found.has(required_id):
            _fail("generated gameplay slice missing " + required_id)
            return

    var loader := LoaderScript.new()
    root.add_child(loader)
    if not loader.load_from_documents(layout, _json(KIT_PATH), gameplay, true, {
        "layout_path": LAYOUT_PATH,
        "kit_path": KIT_PATH,
        "gameplay_slice_path": "user://additional_dressing_procgen_smoke.json",
    }):
        _fail("GeneratedShipLoader rejected generated gameplay slice")
        return
    var specs: Array = loader.get_placed_prop_specs_copy()
    var materialized: Dictionary = {}
    for spec in specs:
        if spec is Dictionary:
            materialized[str((spec as Dictionary).get("visual_id", ""))] = true
    for required_id in REQUIRED_IDS:
        if not materialized.has(required_id):
            _fail("loader did not materialize " + required_id)
            return
    print("ADDITIONAL DRESSING PROCGEN PASS generated=%d materialized=%d" % [found.size(), materialized.size()])
    loader.clear_loaded_ship()
    loader.free()
    quit(0)

func _json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}

func _fail(reason: String) -> void:
    push_error("ADDITIONAL DRESSING PROCGEN FAIL " + reason)
    quit(1)
