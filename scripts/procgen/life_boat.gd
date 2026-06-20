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

const SCHEMA_VERSION: String = "1.1.0"
const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

# Life boat room definitions. Order matters — index 0 is the airlock
# (dock connection point).
# Layout: linear chain along X axis (bow = +X, stern = -X)
#   cockpit_01 at x=1 (bow), airlock_01 at x=0 (mid), engine_bay_01 at x=-1 (stern)
const ROOMS: Array[Dictionary] = [
	{"id": "airlock_01", "role": "airlock", "deck": 0},
	{"id": "cockpit_01", "role": "bridge", "deck": 0},
	{"id": "engine_bay_01", "role": "engineering", "deck": 0},
]

# Fixed grid positions (cell x, cell z) for each room. Single-cell rooms.
const ROOM_CELL_X: Dictionary = {
	"airlock_01": 0,
	"cockpit_01": 1,
	"engine_bay_01": -1,
}
const ROOM_CELL_Z: Dictionary = {
	"airlock_01": 0,
	"cockpit_01": 0,
	"engine_bay_01": 0,
}


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


# Returns a layout Dictionary in LayoutSerializer schema v1.1.0 format.
# This allows the life boat to be loaded by GeneratedShipLoader exactly
# like a procgen ship. The layout is hand-authored and deterministic:
# 3 single-cell rooms in a linear chain along the X axis.
static func build_layout() -> Dictionary:
	var rooms_array: Array = []
	for room_def in ROOMS:
		var rid: String = room_def["id"]
		var role: String = room_def["role"]
		var deck: int = room_def["deck"]
		var cx: int = ROOM_CELL_X[rid]
		var cz: int = ROOM_CELL_Z[rid]
		var world_x: float = float(cx) * CELL_SIZE
		var world_y: float = float(deck) * DECK_HEIGHT
		var world_z: float = float(cz) * CELL_SIZE

		var placement_name: String
		if deck == 0:
			placement_name = "floor_cell_x%d_z%d" % [cx, cz]
		else:
			placement_name = "floor_cell_d%d_x%d_z%d" % [deck, cx, cz]

		var structural_placements: Array = [
			{
				"name": placement_name,
				"module": "floor_1x1",
				"module_id": "floor_1x1",
				"position": [cx, deck, cz],
				"world_position": [world_x, world_y, world_z],
				"yaw_degrees": 0.0,
			}
		]

		rooms_array.append({
			"id": rid,
			"room_role": role,
			"deck": deck,
			"structural_placements": structural_placements,
			"portals": [],
			"interior_zones": {},
			"motif_requests": [],
		})

	var room_links: Array = [
		{
			"id": "airlock_01_to_cockpit_01",
			"from_room": "airlock_01",
			"to_room": "cockpit_01",
			"from_cell": [ROOM_CELL_X["airlock_01"], ROOM_CELL_Z["airlock_01"], 0],
			"to_cell": [ROOM_CELL_X["cockpit_01"], ROOM_CELL_Z["cockpit_01"], 0],
			"module_id": "doorway_frame_open_1x1",
			"link_type": "door",
		},
		{
			"id": "airlock_01_to_engine_bay_01",
			"from_room": "airlock_01",
			"to_room": "engine_bay_01",
			"from_cell": [ROOM_CELL_X["airlock_01"], ROOM_CELL_Z["airlock_01"], 0],
			"to_cell": [ROOM_CELL_X["engine_bay_01"], ROOM_CELL_Z["engine_bay_01"], 0],
			"module_id": "doorway_frame_open_1x1",
			"link_type": "door",
		},
	]

	return {
		"schema_version": SCHEMA_VERSION,
		"document_kind": "ship_layout",
		"program_id": "life_boat_fixed",
		"kit_id": "ship_structural_v0",
		"design_intent": "fixed hand-authored life boat layout",
		"cell_size": CELL_SIZE,
		"rooms": rooms_array,
		"room_links": room_links,
		"blocked_links": [],
		"vertical_connections": [],
		"landmarks": [],
		"critical_path": ["airlock_01", "cockpit_01"],
		"fire_zones": [],
		"arc_zones": [],
		"breach_zones": [],
		"prototype": {
			"start_room": "airlock_01",
			"goal_room": "cockpit_01",
		},
	}


# Returns the RoomGraph for the life boat. Useful for tests and for
# the start scene combiner to inspect room roles without building
# the full Node3D tree.
static func build_graph() -> RoomGraphScript:
	var graph: RoomGraphScript = RoomGraphScript.new()
	for room_def in ROOMS:
		graph.add_room(room_def["id"], room_def["role"], room_def["deck"])
	graph.add_link("airlock_01", "cockpit_01", "door")
	graph.add_link("airlock_01", "engine_bay_01", "door")
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
