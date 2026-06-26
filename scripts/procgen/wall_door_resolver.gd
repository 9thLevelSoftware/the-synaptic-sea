extends RefCounted
class_name WallDoorResolver

# For each room, examines every cell edge:
# - Edge faces empty/boundary -> wall_straight_1x1
# - Edge faces same room -> no wall (interior)
# - Edge faces connected room -> bulkhead_portal_2x1
# Also computes interior zones (reserved, wall_slots, center_slots).

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

# Direction name to Vector2i
const DIRECTIONS: Dictionary = {
	"north": Vector2i(0, -1),
	"east": Vector2i(1, 0),
	"south": Vector2i(0, 1),
	"west": Vector2i(-1, 0),
}

# Wall yaw per direction
const WALL_YAW: Dictionary = {
	"south": 0.0,
	"west": 90.0,
	"north": 180.0,
	"east": 270.0,
}

# Wall position offset from cell center per direction.
# The offset places the wall at the edge of the cell.
const WALL_OFFSET: Dictionary = {
	"south": Vector3(0.0, 0.0, -CELL_SIZE / 2.0),
	"west": Vector3(-CELL_SIZE / 2.0, 0.0, 0.0),
	"north": Vector3(0.0, 0.0, CELL_SIZE / 2.0),
	"east": Vector3(CELL_SIZE / 2.0, 0.0, 0.0),
}


func resolve(cell_grid: Dictionary, room_plan: Array[Dictionary]) -> Dictionary:
	var rooms_data: Dictionary = cell_grid.get("rooms", {})
	var adjacencies: Array = cell_grid.get("adjacencies", [])

	# Build lookup: which room owns each cell
	var cell_to_room: Dictionary = {}
	for rid in rooms_data.keys():
		var room_data: Dictionary = rooms_data[rid]
		for cell in room_data.get("cells", []):
			cell_to_room[cell] = str(rid)

	# Build lookup: which rooms are connected (adjacency pairs)
	var connected_pairs: Dictionary = {}
	for adj in adjacencies:
		var fr: String = str(adj["from_room"])
		var tr: String = str(adj["to_room"])
		connected_pairs[_pair_key(fr, tr)] = adj

	# Build room role lookup
	var room_roles: Dictionary = {}
	for room in room_plan:
		room_roles[str(room["id"])] = str(room.get("role", ""))

	# Process each room
	var geometry: Dictionary = {}
	for rid in rooms_data.keys():
		var room_data: Dictionary = rooms_data[rid]
		var cells: Array = room_data.get("cells", [])
		var deck: int = int(room_data.get("deck", 0))

		var wall_segments: Array[Dictionary] = []
		var portals: Array[Dictionary] = []
		var reserved_cells: Array[Vector2i] = []
		var wall_slot_cells: Array[Dictionary] = []
		var center_cells: Array[Vector2i] = []

		var portal_cell_dirs: Dictionary = {}  # Track which cell+dir has a portal

		for cell in cells:
			var is_wall_adjacent: bool = false
			var is_portal_adjacent: bool = false

			for dir_name in DIRECTIONS.keys():
				var dir_vec: Vector2i = DIRECTIONS[dir_name]
				var neighbor: Vector2i = Vector2i(cell.x + dir_vec.x, cell.y + dir_vec.y)

				if cell_to_room.has(neighbor):
					var neighbor_room: String = cell_to_room[neighbor]
					if neighbor_room == rid:
						# Same room — no wall
						continue
					else:
						# Different room — check if connected
						var pair: String = _pair_key(rid, neighbor_room)
						if connected_pairs.has(pair):
							# Portal
							var cell_world: Vector3 = _cell_world_position(cell, deck)
							var portal_pos: Vector3 = cell_world + WALL_OFFSET[dir_name]
							var portal_id: String = "%s_%s_to_%s" % [dir_name, rid, neighbor_room]

							portals.append({
								"id": portal_id,
								"wall": dir_name,
								"module_id": "bulkhead_portal_2x1",
								"position": portal_pos,
								"yaw_degrees": WALL_YAW[dir_name],
								"to_room": neighbor_room,
								"from_cell": cell,
								"to_cell": neighbor,
							})
							portal_cell_dirs["%d_%d_%s" % [cell.x, cell.y, dir_name]] = true
							is_portal_adjacent = true
							reserved_cells.append(cell)
						else:
							# Adjacent but not connected — wall
							_add_wall(wall_segments, cell, dir_name, deck, rid)
							is_wall_adjacent = true
				else:
					# Empty space — wall
					_add_wall(wall_segments, cell, dir_name, deck, rid)
					is_wall_adjacent = true

			if is_wall_adjacent and not is_portal_adjacent:
				wall_slot_cells.append({"cell": cell, "against_wall": true})
			elif not is_wall_adjacent and not is_portal_adjacent:
				center_cells.append(cell)

		geometry[rid] = {
			"wall_segments": wall_segments,
			"portals": portals,
			"interior_zones": {
				"reserved_cells": reserved_cells,
				"wall_slots": wall_slot_cells,
				"center_slots": center_cells,
			},
		}

	return geometry


func _add_wall(walls: Array[Dictionary], cell: Vector2i, dir_name: String,
		deck: int, room_id: String) -> void:
	var cell_world: Vector3 = _cell_world_position(cell, deck)
	var wall_pos: Vector3 = cell_world + WALL_OFFSET[dir_name]
	var wall_name: String = "wall_%s_%s_x%d_z%d" % [room_id, dir_name, cell.x, cell.y]

	walls.append({
		"name": wall_name,
		"module_id": "wall_straight_1x1",
		"position": wall_pos,
		"yaw_degrees": WALL_YAW[dir_name],
		"cell": cell,
		"direction": dir_name,
	})


func _cell_world_position(cell: Vector2i, deck: int) -> Vector3:
	return Vector3(
		float(cell.x) * CELL_SIZE,
		float(deck) * DECK_HEIGHT,
		float(cell.y) * CELL_SIZE,
	)


func _pair_key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a
