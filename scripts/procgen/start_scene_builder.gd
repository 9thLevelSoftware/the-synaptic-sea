extends RefCounted
class_name StartSceneBuilder

# Builds the combined start scene: a randomized derelict with a fixed
# life boat attached at the dock.
#
# Pipeline:
#   1. Generate derelict layout via ShipLayoutGenerator.generate().
#   2. Generate life boat layout via LifeBoatBuilder.build_layout().
#   3. Build gameplay slices for both via GameplaySliceBuilder.build().
#   4. Write layout + gameplay pairs to temp files under user://start_scenario/.
#   5. Load both via GeneratedShipLoader.load_from_paths().
#   6. Position life boat adjacent to derelict's dock room.
#   7. Return a root Node3D containing both loaders.
#
# The root is NOT attached to the scene tree — the caller decides
# where to add it (playable scene, test scene, etc.).

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

# Default derelict archetype path.
const DERELICT_ARCHETYPE_PATH: String = "res://data/procgen/archetypes/derelict.json"

# Structural kit used by GeneratedShipLoader.
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

# Temp directory for layout + gameplay slice files.
const TEMP_DIR: String = "user://start_scenario"

# Gap between the derelict dock and the life boat airlock (world units).
const DOCK_GAP: float = 6.0


# Builds the combined start scene for the given seed.
# Returns a Node3D named "StartScene" containing both the derelict
# GeneratedShipLoader and the life boat GeneratedShipLoader, or null on failure.
static func build(seed_value: int) -> Node3D:
	# Load derelict archetype.
	var archetype: Dictionary = _load_archetype(DERELICT_ARCHETYPE_PATH)
	if archetype.is_empty():
		push_error("StartSceneBuilder: could not load derelict archetype")
		return null

	# Ensure temp directory exists.
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		DirAccess.make_dir_absolute(TEMP_DIR)

	# ---- Step 1: Generate derelict layout ----
	var blueprint: ShipBlueprintScript = _build_blueprint(archetype, seed_value)
	if blueprint == null:
		push_error("StartSceneBuilder: could not build derelict blueprint")
		return null

	var layout_gen: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var derelict_layout: Dictionary = layout_gen.generate(blueprint, archetype)
	if derelict_layout.is_empty():
		push_error("StartSceneBuilder: derelict layout generation failed")
		return null

	# ---- Step 2: Generate life boat layout ----
	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	if lb_layout.is_empty():
		push_error("StartSceneBuilder: life boat layout generation failed")
		return null

	# ---- Step 3: Build gameplay slices ----
	var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
	var derelict_gameplay: Dictionary = slice_builder.build(derelict_layout)
	if derelict_gameplay.is_empty():
		push_error("StartSceneBuilder: derelict gameplay slice build failed")
		return null

	var lb_gameplay: Dictionary = slice_builder.build(lb_layout)
	if lb_gameplay.is_empty():
		push_error("StartSceneBuilder: life boat gameplay slice build failed")
		return null

	# ---- Step 4: Write layouts + gameplay slices to temp files ----
	var derelict_layout_path: String = TEMP_DIR + "/derelict_layout.json"
	var derelict_gameplay_path: String = TEMP_DIR + "/derelict_gameplay.json"
	var lb_layout_path: String = TEMP_DIR + "/lifeboat_layout.json"
	var lb_gameplay_path: String = TEMP_DIR + "/lifeboat_gameplay.json"

	if not _write_json(derelict_layout_path, derelict_layout):
		push_error("StartSceneBuilder: could not write derelict layout")
		return null
	if not _write_json(derelict_gameplay_path, derelict_gameplay):
		push_error("StartSceneBuilder: could not write derelict gameplay slice")
		return null
	if not _write_json(lb_layout_path, lb_layout):
		push_error("StartSceneBuilder: could not write life boat layout")
		return null
	if not _write_json(lb_gameplay_path, lb_gameplay):
		push_error("StartSceneBuilder: could not write life boat gameplay slice")
		return null

	# ---- Step 5: Load both via GeneratedShipLoader ----
	var derelict: GeneratedShipLoaderScript = GeneratedShipLoaderScript.new()
	derelict.name = "Derelict"
	var derelict_ok: bool = derelict.load_from_paths(derelict_layout_path, KIT_PATH, derelict_gameplay_path)
	if not derelict_ok:
		push_error("StartSceneBuilder: derelict load_from_paths failed")
		derelict.queue_free()
		return null

	var life_boat: GeneratedShipLoaderScript = GeneratedShipLoaderScript.new()
	life_boat.name = "LifeBoat"
	var lb_ok: bool = life_boat.load_from_paths(lb_layout_path, KIT_PATH, lb_gameplay_path)
	if not lb_ok:
		push_error("StartSceneBuilder: life boat load_from_paths failed")
		derelict.queue_free()
		life_boat.queue_free()
		return null

	# ---- Step 6: Position life boat adjacent to derelict's dock room ----
	var dock_pos: Vector3 = _find_dock_position(derelict_layout)
	life_boat.position = dock_pos + Vector3(0.0, 0.0, DOCK_GAP)

	# ---- Step 7: Combine under a single root ----
	var root: Node3D = Node3D.new()
	root.name = "StartScene"
	root.add_child(derelict)
	root.add_child(life_boat)

	return root


# Builds a ShipBlueprint from the archetype's blueprint dict, overriding seed.
static func _build_blueprint(archetype: Dictionary, seed_value: int) -> ShipBlueprintScript:
	var bp_data: Dictionary = archetype.get("blueprint", {})
	var size: int = int(bp_data.get("size", ShipBlueprintScript.Size.MEDIUM))
	var condition: int = int(bp_data.get("condition", ShipBlueprintScript.Condition.WRECKED))
	return ShipBlueprintScript.new(size, condition, seed_value)


# Finds the world position of the dock room in the derelict layout.
# Returns the room center, or Vector3.ZERO if no dock room is found.
static func _find_dock_position(layout: Dictionary) -> Vector3:
	var rooms: Array = layout.get("rooms", [])
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var role: String = str(room.get("room_role", ""))
		var rid: String = str(room.get("id", ""))
		if role != "dock" and not rid.begins_with("dock"):
			continue
		# Find a floor placement to get the world position
		var placements: Array = room.get("structural_placements", [])
		for placement_variant in placements:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var pos: Variant = placement.get("world_position", placement.get("position", null))
			if pos == null or typeof(pos) != TYPE_ARRAY:
				continue
			var pos_arr: Array = pos
			if pos_arr.size() < 3:
				continue
			return Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	return Vector3.ZERO


# Writes a Dictionary to a JSON file. Returns true on success.
static func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("StartSceneBuilder: cannot open for write: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


# Loads an archetype JSON file and returns its contents as a Dictionary.
static func _load_archetype(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}
