extends RefCounted
class_name LifeBoatBuilder

# Builds the fixed life boat layout. The life boat is always the same
# — 3 rooms in a linear arrangement:
#
#   [airlock] → [cockpit] → [engine_bay]
#
# The airlock is the connection point to the derelict's dock.
# The cockpit has flight controls and scanner.
# The engine bay has engineering, maintenance, and life support.
#
# This is NOT procgen — the layout is hand-authored and deterministic.
# The player learns it, and repair mechanics target specific rooms.

const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")

# Life boat room definitions. Order matters — index 0 is the airlock
# (dock connection point).
const ROOMS: Array[Dictionary] = [
	{"id": "airlock_01", "role": "airlock", "deck": 0},
	{"id": "cockpit_01", "role": "bridge", "deck": 0},
	{"id": "engine_bay_01", "role": "engineering", "deck": 0},
]


# Builds the life boat as a Node3D tree. Returns a Node3D named
# "LifeBoat" with one child per room, each containing structural
# modules. The caller is responsible for adding it to the scene tree
# and positioning it adjacent to the derelict dock.
static func build() -> Node3D:
	var graph: RoomGraphScript = RoomGraphScript.new()
	for room_def in ROOMS:
		graph.add_room(room_def["id"], room_def["role"], room_def["deck"])

	# Linear chain: airlock → cockpit → engine_bay.
	graph.add_link("airlock_01", "cockpit_01", "door")
	graph.add_link("cockpit_01", "engine_bay_01", "door")

	var placer: StructuralPlacerScript = StructuralPlacerScript.new()
	var structure: Node3D = placer.place_structure(graph)
	if structure == null:
		push_error("LifeBoatBuilder: StructuralPlacer returned null")
		return null

	var root: Node3D = Node3D.new()
	root.name = "LifeBoat"
	root.add_child(structure)
	return root


# Returns the RoomGraph for the life boat. Useful for tests and for
# the start scene combiner to inspect room roles without building
# the full Node3D tree.
static func build_graph() -> RoomGraphScript:
	var graph: RoomGraphScript = RoomGraphScript.new()
	for room_def in ROOMS:
		graph.add_room(room_def["id"], room_def["role"], room_def["deck"])
	graph.add_link("airlock_01", "cockpit_01", "door")
	graph.add_link("cockpit_01", "engine_bay_01", "door")
	return graph


# Returns the Node3D for the airlock room inside a built life boat.
# The start scene combiner uses this to position the life boat
# adjacent to the derelict dock.
static func get_airlock_node(life_boast_root: Node3D) -> Node3D:
	if life_boast_root == null or life_boast_root.get_child_count() < 1:
		return null
	var structure: Node = life_boast_root.get_child(0)
	if structure == null:
		return null
	return structure.get_node_or_null("airlock_01")
