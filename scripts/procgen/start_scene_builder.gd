extends RefCounted
class_name StartSceneBuilder

# Builds the combined start scene: a randomized derelict with a fixed
# life boat attached at the dock.
#
# Pipeline:
#   1. Generate derelict shell from archetype + seed.
#   2. Build the fixed life boat.
#   3. Position the life boat adjacent to the derelict's dock room.
#   4. Return a root Node3D containing both.
#
# The root is NOT attached to the scene tree — the caller decides
# where to add it (playable scene, test scene, etc.).

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

# Default derelict archetype path.
const DERELICT_ARCHETYPE_PATH: String = "res://data/procgen/archetypes/derelict.json"

# Gap between the derelict dock and the life boat airlock (world units).
const DOCK_GAP: float = 6.0


# Builds the combined start scene for the given seed.
# Returns a Node3D named "StartScene" containing both the derelict
# and the life boat, or null on failure.
static func build(seed_value: int) -> Node3D:
	# Load derelict archetype.
	var archetype: Dictionary = _load_archetype(DERELICT_ARCHETYPE_PATH)
	if archetype.is_empty():
		push_error("StartSceneBuilder: could not load derelict archetype")
		return null

	# Build blueprint from archetype.
	var bp_data: Dictionary = archetype.get("blueprint", {})
	bp_data["seed_value"] = seed_value
	var blueprint = ShipBlueprintScript.from_dict(bp_data)

	# Generate derelict.
	var gen: ShipGeneratorScript = ShipGeneratorScript.new()
	var derelict: Node3D = gen.generate(blueprint, archetype)
	if derelict == null:
		push_error("StartSceneBuilder: derelict generation failed")
		return null

	# Build life boat.
	var life_boat: Node3D = LifeBoatBuilderScript.build()
	if life_boat == null:
		push_error("StartSceneBuilder: life boat build failed")
		return null

	# Find the derelict's dock room and position the life boat
	# adjacent to it.
	var dock_node: Node3D = _find_dock_node(derelict)
	if dock_node == null:
		push_error("StartSceneBuilder: derelict has no dock room")
		return null

	# Position the life boat so its airlock faces the dock.
	# The dock is at some world position; we place the life boat
	# offset along +Z from the dock.
	var dock_world_pos: Vector3 = _get_world_position(dock_node)
	life_boat.position = dock_world_pos + Vector3(0.0, 0.0, DOCK_GAP)

	# Combine under a single root.
	var root: Node3D = Node3D.new()
	root.name = "StartScene"
	root.add_child(derelict)
	root.add_child(life_boat)

	return root


# Finds the dock room node inside the derelict's ShipStructure.
static func _find_dock_node(derelict: Node3D) -> Node3D:
	if derelict == null or derelict.get_child_count() < 1:
		return null
	var structure: Node = derelict.get_child(0)
	if structure == null:
		return null
	# Look for a room named "dock_01" (the first dock room).
	for child in structure.get_children():
		if String(child.name).begins_with("dock"):
			return child
	return null


# Gets the world position of a node by walking up to the root.
static func _get_world_position(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	return node.global_position


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
