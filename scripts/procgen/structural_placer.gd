extends RefCounted
class_name StructuralPlacer

# Builds the physical "shell" of a procedurally generated ship from a
# RoomGraph. v2 places rooms on a 2D grid instead of a 1D chain,
# producing branching layouts with corridors, side rooms, and spatial
# variety.
#
# Placement algorithm:
#   1. Place airlock at grid origin (0, 0).
#   2. BFS through the room graph. For each room, find a free grid
#      position adjacent to its parent.
#   3. Rooms have footprints based on role (e.g. engineering = 2x1,
#      corridor = 1x1). The placer tries all 4 rotations (swap w/d)
#      to find the best fit.
#   4. Convert grid positions to world coordinates (CELL_SIZE per cell).
#   5. Place structural modules within each room's footprint.
#
# The output is a Node3D named "ShipStructure" with one child per
# room, each containing the placed modules.

const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")

const CELL_SIZE: float = 4.0
const ROOM_GAP: float = 2.0
const MODULE_BASE_PATH: String = "res://scenes/wrappers/structural/ship_structural_v0/"

# Room footprints in grid cells (width x depth). Larger rooms
# physically occupy more space. Roles not listed default to 1x1.
const ROOM_FOOTPRINTS: Dictionary = {
	"engineering": Vector2i(2, 1),
	"bridge": Vector2i(2, 1),
	"cargo": Vector2i(2, 1),
	"life_support": Vector2i(2, 1),
}

# Module lists per role. Same as v1.
const ROOM_MODULES: Dictionary = {
	"airlock": [
		"floor_1x1",
		"floor_1x1",
		"doorway_frame_open_1x1",
	],
	"corridor": [
		"corridor_floor_1x1",
		"corridor_floor_1x1",
	],
	"engineering": [
		"floor_1x1",
		"floor_2x1",
		"wall_straight_1x1",
	],
	"life_support": [
		"floor_1x1",
		"floor_1x1",
		"wall_straight_1x1",
	],
	"bridge": [
		"floor_2x1",
		"floor_2x1",
		"wall_straight_1x1",
	],
	"cargo": [
		"floor_2x1",
		"floor_2x1",
	],
	"crew_quarters": [
		"floor_1x1",
		"floor_1x1",
	],
	"medical": [
		"floor_1x1",
		"floor_1x1",
	],
	"maintenance": [
		"floor_1x1",
		"corridor_floor_1x1",
	],
}

const FALLBACK_MODULES: Array[String] = ["floor_1x1"]

# Direction vectors for 4-connected grid placement.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),  # north
	Vector2i(1, 0),   # east
	Vector2i(0, 1),   # south
	Vector2i(-1, 0),  # west
]

# Preferred directions per role. Rooms with a preference try those
# directions first, giving the layout a spatial personality (bridge
# faces forward, engineering is aft, etc.).
const DIRECTION_PREFERENCES: Dictionary = {
	"engineering": [2, 1, 3, 0],   # south, east, west, north (aft)
	"bridge": [0, 1, 3, 2],        # north, east, west, south (fore)
	"cargo": [1, 2, 3, 0],         # east, south, west, north (starboard)
	"life_support": [3, 0, 1, 2],  # west, north, east, south (port)
	"airlock": [0, 1, 2, 3],       # north first (entry faces forward)
}


# Builds the ShipStructure Node3D for the given graph using 2D grid
# placement. Returns a Node3D named "ShipStructure" or null on failure.
func place_structure(graph: RoomGraphScript) -> Node3D:
	if graph.rooms.is_empty():
		return null

	# Phase 1: compute grid positions via BFS.
	var grid_positions: Dictionary = _layout_rooms(graph)
	if grid_positions.is_empty():
		push_error("STRUCTURAL PLACER FAIL grid layout returned empty")
		return null

	# Phase 2: build the Node3D tree from grid positions.
	var root: Node3D = Node3D.new()
	root.name = "ShipStructure"

	for room in graph.rooms:
		var rid: String = String(room["id"])
		var role: String = String(room["role"])
		var grid_pos: Vector2i = grid_positions.get(rid, Vector2i.ZERO)
		var footprint: Vector2i = _footprint_for_role(role)

		# Convert grid position to world coordinates. The room's
		# origin is at the center of its footprint on the XZ plane.
		var world_x: float = float(grid_pos.x) * (CELL_SIZE + ROOM_GAP)
		var world_z: float = float(grid_pos.y) * (CELL_SIZE + ROOM_GAP)

		var room_node: Node3D = _create_room_node(room, Vector3(world_x, 0.0, world_z))
		root.add_child(room_node)

	return root


# BFS-based grid layout. Returns a Dictionary of room_id -> Vector2i.
func _layout_rooms(graph: RoomGraphScript) -> Dictionary:
	var positions: Dictionary = {}
	var occupied: Dictionary = {}  # grid cell -> room_id

	if graph.rooms.is_empty():
		return positions

	# Place first room (airlock) at origin.
	var first_id: String = String(graph.rooms[0]["id"])
	var first_role: String = String(graph.rooms[0]["role"])
	var first_fp: Vector2i = _footprint_for_role(first_role)
	positions[first_id] = Vector2i(0, 0)
	_occupy_cells(occupied, Vector2i(0, 0), first_fp, first_id)

	# BFS through the graph.
	var visited: Dictionary = {first_id: true}
	var queue: Array[String] = [first_id]

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_pos: Vector2i = positions[current_id]
		var current_fp: Vector2i = _footprint_for_role(_role_for_room(graph, current_id))

		for connected_id in graph.get_connected_rooms(current_id):
			if visited.has(connected_id):
				continue
			visited[connected_id] = true

			var connected_role: String = _role_for_room(graph, connected_id)
			var connected_fp: Vector2i = _footprint_for_role(connected_role)

			# Find best placement adjacent to current room.
			var best_pos: Vector2i = _find_adjacent_position(
				current_pos, current_fp, connected_fp, connected_role, occupied)

			if best_pos == Vector2i(-99999, -99999):
				# Fallback: try any free position near current.
				best_pos = _find_any_free_position(current_pos, connected_fp, occupied)

			if best_pos == Vector2i(-99999, -99999):
				push_error("STRUCTURAL PLACER WARN could not place room %s" % connected_id)
				continue

			positions[connected_id] = best_pos
			_occupy_cells(occupied, best_pos, connected_fp, connected_id)
			queue.append(connected_id)

	return positions


# Finds the best adjacent grid position for a new room, respecting
# direction preferences for the room's role.
func _find_adjacent_position(
		parent_pos: Vector2i,
		parent_fp: Vector2i,
		new_fp: Vector2i,
		new_role: String,
		occupied: Dictionary) -> Vector2i:

	var prefs: Array = DIRECTION_PREFERENCES.get(new_role, [0, 1, 2, 3])

	# Try preferred directions first.
	for dir_idx in prefs:
		var dir: Vector2i = DIRECTIONS[dir_idx]
		var candidate: Vector2i = _adjacent_cell(parent_pos, parent_fp, dir)
		if _can_place(candidate, new_fp, occupied):
			return candidate

	# Try all directions with all rotations.
	for dir_idx in range(4):
		var dir: Vector2i = DIRECTIONS[dir_idx]
		var rotated_fp: Vector2i = Vector2i(new_fp.y, new_fp.x)  # swap w/d
		if rotated_fp == new_fp:
			continue  # already tried (square room)
		var candidate: Vector2i = _adjacent_cell(parent_pos, parent_fp, dir)
		if _can_place(candidate, rotated_fp, occupied):
			return candidate

	return Vector2i(-99999, -99999)


# Computes the grid cell where a new room's anchor should go so it's
# adjacent to the parent room in the given direction.
func _adjacent_cell(parent_pos: Vector2i, parent_fp: Vector2i, dir: Vector2i) -> Vector2i:
	# Place the new room's edge against the parent's edge.
	# For each direction:
	#   north: new bottom edge = parent top edge - 1
	#   east:  new left edge = parent right edge
	#   south: new top edge = parent bottom edge
	#   west:  new right edge = parent left edge - 1
	if dir == Vector2i(0, -1):
		# north: new room below parent
		return Vector2i(parent_pos.x, parent_pos.y - 1)
	elif dir == Vector2i(1, 0):
		# east: new room to the right
		return Vector2i(parent_pos.x + parent_fp.x, parent_pos.y)
	elif dir == Vector2i(0, 1):
		# south: new room above parent
		return Vector2i(parent_pos.x, parent_pos.y + parent_fp.y)
	else:
		# west: new room to the left
		return Vector2i(parent_pos.x - 1, parent_pos.y)


# Checks whether a room with the given footprint can be placed at
# `pos` without overlapping any occupied cells.
func _can_place(pos: Vector2i, footprint: Vector2i, occupied: Dictionary) -> bool:
	for dx in range(footprint.x):
		for dz in range(footprint.y):
			var cell: Vector2i = Vector2i(pos.x + dx, pos.y + dz)
			if occupied.has(cell):
				return false
	return true


# Fallback: spiral outward from parent to find any free position.
func _find_any_free_position(
		parent_pos: Vector2i,
		footprint: Vector2i,
		occupied: Dictionary) -> Vector2i:

	for radius in range(1, 20):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dz) != radius:
					continue  # only perimeter
				var candidate: Vector2i = Vector2i(parent_pos.x + dx, parent_pos.y + dz)
				if _can_place(candidate, footprint, occupied):
					return candidate
	return Vector2i(-99999, -99999)


# Marks all grid cells occupied by a room.
func _occupy_cells(occupied: Dictionary, pos: Vector2i, footprint: Vector2i, room_id: String) -> void:
	for dx in range(footprint.x):
		for dz in range(footprint.y):
			occupied[Vector2i(pos.x + dx, pos.y + dz)] = room_id


# Returns the footprint for a room role. Unknown roles default to 1x1.
func _footprint_for_role(role: String) -> Vector2i:
	if ROOM_FOOTPRINTS.has(role):
		return ROOM_FOOTPRINTS[role]
	return Vector2i(1, 1)


# Returns the role for a room id in the graph.
func _role_for_room(graph: RoomGraphScript, room_id: String) -> String:
	var room: Dictionary = graph.get_room(room_id)
	if room.is_empty():
		return ""
	return String(room["role"])


# Creates a room Node3D with structural modules placed within its
# footprint. Modules are arranged along the room's local +Z axis
# (same as v1), but the room node is positioned at the world
# coordinates derived from its grid position.
func _create_room_node(room: Dictionary, world_pos: Vector3) -> Node3D:
	var room_id: String = String(room.get("id", "room"))
	var role: String = String(room.get("role", ""))

	var room_node: Node3D = Node3D.new()
	room_node.name = room_id
	room_node.position = world_pos

	var modules: Array[String] = _modules_for_role(role)
	for i in range(modules.size()):
		var stem: String = modules[i]
		var instance: Node3D = _instantiate_module(stem)
		if instance == null:
			continue
		instance.name = "%s_%d" % [stem, i]
		instance.position = Vector3(0.0, 0.0, float(i) * CELL_SIZE)
		room_node.add_child(instance)

	return room_node


func _modules_for_role(role: String) -> Array[String]:
	if not ROOM_MODULES.has(role):
		return FALLBACK_MODULES.duplicate()
	var raw = ROOM_MODULES[role]
	if raw is Array:
		var out: Array[String] = []
		for entry in raw:
			out.append(String(entry))
		return out
	return FALLBACK_MODULES.duplicate()


func _instantiate_module(stem: String) -> Node3D:
	var path: String = MODULE_BASE_PATH + stem + ".tscn"
	if not ResourceLoader.exists(path):
		push_error("STRUCTURAL PLACER FAIL module not found: %s" % path)
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("STRUCTURAL PLACER FAIL module load returned null: %s" % path)
		return null
	if not packed.can_instantiate():
		push_error("STRUCTURAL PLACER FAIL module cannot be instantiated: %s" % path)
		return null
	var instance: Node = packed.instantiate()
	if instance == null:
		push_error("STRUCTURAL PLACER FAIL module instantiate returned null: %s" % path)
		return null
	if not (instance is Node3D):
		push_error("STRUCTURAL PLACER FAIL module root is not Node3D: %s" % path)
		instance.queue_free()
		return null
	return instance
