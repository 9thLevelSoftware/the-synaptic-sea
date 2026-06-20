extends RefCounted
class_name ShipGenerator

# Orchestrator that wires the ShipBlueprint-driven procgen pipeline
# end-to-end.
#
# v4: Uses the new ShipLayoutGenerator pipeline to produce a
# layout.json Dictionary, writes it + a minimal gameplay_slice.json
# to temp files, and loads via GeneratedShipLoader.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

var layout_generator: RefCounted = ShipLayoutGeneratorScript.new()


# Builds the full Node3D tree for the given blueprint.
# `archetype` is forwarded to the layout generator for template
# selection and role weighting.
func generate(blueprint, archetype: Dictionary = {}) -> Node3D:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")

	var layout: Dictionary = layout_generator.generate(blueprint, archetype)
	if layout.is_empty():
		push_error("SHIP GENERATOR FAIL layout generation returned empty")
		return null

	return _load_layout_as_scene(layout)


func generate_layout(blueprint, archetype: Dictionary = {}) -> Dictionary:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")
	return layout_generator.generate(blueprint, archetype)


# Convenience wrapper that builds a ShipBlueprint from seed/size/condition
# and runs generate().
func generate_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1) -> Node3D:
	var blueprint = ShipBlueprintScript.new(size, condition, seed_value)
	return generate(blueprint)


func _load_layout_as_scene(layout: Dictionary) -> Node3D:
	# Write layout, kit reference, and minimal gameplay slice to temp files
	var temp_dir: String = "user://procgen_temp"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_absolute(temp_dir)

	var layout_path: String = temp_dir + "/layout.json"
	var kit_path: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
	var gameplay_path: String = temp_dir + "/gameplay_slice.json"

	# Write layout
	var layout_json: String = JSON.stringify(layout, "  ")
	var layout_file: FileAccess = FileAccess.open(layout_path, FileAccess.WRITE)
	if layout_file == null:
		push_error("SHIP GENERATOR FAIL cannot write layout: %s" % layout_path)
		return null
	layout_file.store_string(layout_json)
	layout_file.close()

	# Build kit doc from the existing kit
	# The GeneratedShipLoader needs the kit JSON, so we reference the shared one
	kit_path = "res://data/ship_structural_v0_kit.json"
	if not FileAccess.file_exists(ProjectSettings.globalize_path(kit_path)):
		# Fallback: look for kit alongside golden layouts
		kit_path = "res://data/procgen/golden/coherent_ship_001/kit.json"

	# Write minimal gameplay slice
	var proto: Dictionary = layout.get("prototype", {})
	var gameplay: Dictionary = {
		"start_room": str(proto.get("start_room", "")),
		"goal_room": str(proto.get("goal_room", "")),
		"objectives": [
			{
				"id": "obj_reach_goal",
				"sequence": 1,
				"type": "interact",
				"kind": "single",
				"room_id": str(proto.get("goal_room", "")),
				"approach_cell": _get_goal_approach_cell(layout),
			},
		],
	}
	var gameplay_json: String = JSON.stringify(gameplay, "  ")
	var gameplay_file: FileAccess = FileAccess.open(gameplay_path, FileAccess.WRITE)
	if gameplay_file == null:
		push_error("SHIP GENERATOR FAIL cannot write gameplay slice: %s" % gameplay_path)
		return null
	gameplay_file.store_string(gameplay_json)
	gameplay_file.close()

	# Load via GeneratedShipLoader
	var LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
	var loader: Node3D = LoaderScript.new()
	var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path)
	if not success:
		push_error("SHIP GENERATOR FAIL loader returned false")
		loader.queue_free()
		return null

	return loader


func _get_goal_approach_cell(layout: Dictionary) -> Array:
	var proto: Dictionary = layout.get("prototype", {})
	var goal_id: String = str(proto.get("goal_room", ""))
	var rooms: Array = layout.get("rooms", [])
	for room in rooms:
		if str(room.get("id", "")) != goal_id:
			continue
		var placements: Array = room.get("structural_placements", [])
		if placements.is_empty():
			return [0, 0, 0]
		# Return the first floor cell's grid coordinates
		var name: String = str(placements[0].get("name", ""))
		# Parse floor_cell_x{X}_z{Z} or floor_cell_d{D}_x{X}_z{Z}
		var parts: PackedStringArray = name.split("_")
		for i in range(parts.size()):
			if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
				var x_str: String = String(parts[i]).substr(1)
				var z_str: String = String(parts[i + 1]).substr(1)
				if x_str.is_valid_int() and z_str.is_valid_int():
					var deck: int = int(room.get("deck", 0))
					return [int(x_str), int(z_str), deck]
	return [0, 0, 0]
