extends SceneTree

func _initialize() -> void:
	var builder_script := load("res://scripts/procgen/gameplay_slice_builder.gd")
	var palette_text: String = FileAccess.get_file_as_string("res://data/ui/rarity_palette.json")
	var parsed: Variant = JSON.parse_string(palette_text)
	if builder_script == null or not (parsed is Dictionary):
		_fail("required container dependencies failed to load")
		return
	var palette: Dictionary = parsed as Dictionary
	var container_palette: Dictionary = palette.get("container_kinds", {})
	for key in ["industrial_crate", "survivor_locker", "maintenance_cache", "hidden_cache"]:
		if not container_palette.has(key):
			_fail("rarity palette missing container kind %s" % key)
			return
	var layout := {
		"prototype": {"start_room": "airlock_01", "goal_room": "bridge_01"},
		"rooms": [
			{"id": "airlock_01", "room_role": "airlock", "deck": 0, "structural_placements": [{"name": "floor_cell_x0_z0"}]},
			{"id": "cargo_01", "room_role": "cargo", "deck": 0, "structural_placements": [{"name": "floor_cell_x1_z0"}]},
			{"id": "engineering_01", "room_role": "engineering", "deck": 0, "structural_placements": [{"name": "floor_cell_x2_z0"}]},
			{"id": "bridge_01", "room_role": "bridge", "deck": 0, "structural_placements": [{"name": "floor_cell_x3_z0"}]}
		]
	}
	var builder = builder_script.new()
	var slice: Dictionary = builder.build(layout)
	var kinds: Dictionary = {}
	for spec_v in slice.get("loot_containers", []):
		if spec_v is Dictionary:
			kinds[String((spec_v as Dictionary).get("kind", ""))] = true
	if not kinds.has("generic_crate") or not kinds.has("generic_locker"):
		_fail("expected gameplay slice builder to place both crate and locker containers")
		return
	print("CONTAINER VARIETY PASS kinds=%d placed=%d" % [container_palette.size(), kinds.size()])
	quit(0)

func _fail(reason: String) -> void:
	push_error("CONTAINER VARIETY FAIL reason=%s" % reason)
	quit(1)
