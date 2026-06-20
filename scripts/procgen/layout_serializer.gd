extends RefCounted
class_name LayoutSerializer

# Assembles a complete layout.json Dictionary from pipeline stage outputs.
# Output matches the golden layout schema version 1.1.0 exactly.

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

# Default motif requests per role
const ROLE_MOTIFS: Dictionary = {
	"airlock": ["mot-airlock-entry-locker"],
	"dock": ["mot-airlock-entry-locker"],
	"corridor": ["mot-maintenance-workbench-corner"],
	"engineering": ["mot-engineering-console"],
}

# Floor module per role
const FLOOR_MODULES: Dictionary = {
	"corridor": "corridor_floor_1x1",
	"main_spine": "corridor_floor_1x1",
}
const DEFAULT_FLOOR: String = "floor_1x1"


func serialize(cell_grid: Dictionary, geometry: Dictionary,
		room_plan: Array[Dictionary], template_id: String,
		seed_value: int, archetype_name: String) -> Dictionary:

	var rooms_data: Dictionary = cell_grid.get("rooms", {})
	var adjacencies: Array = cell_grid.get("adjacencies", [])

	# Build room role lookup
	var room_roles: Dictionary = {}
	var room_order: Array[String] = []
	for room in room_plan:
		var rid: String = str(room["id"])
		room_roles[rid] = str(room.get("role", ""))
		room_order.append(rid)

	# Assemble rooms array
	var rooms_array: Array = []
	for rid in room_order:
		if not rooms_data.has(rid):
			continue
		var room_data: Dictionary = rooms_data[rid]
		var role: String = room_roles.get(rid, "")
		var deck: int = int(room_data.get("deck", 0))
		var cells: Array = room_data.get("cells", [])

		var placements: Array = _build_structural_placements(cells, deck, role)
		var geo: Dictionary = geometry.get(rid, {})

		var room_dict: Dictionary = {
			"id": rid,
			"room_role": role,
			"deck": deck,
			"structural_placements": placements,
		}

		# Add wall/portal/interior data if available
		if not geo.is_empty():
			var wall_placements: Array = _build_wall_placements(geo.get("wall_segments", []))
			# Append wall placements to structural_placements
			for wp in wall_placements:
				placements.append(wp)

			room_dict["portals"] = geo.get("portals", [])
			room_dict["interior_zones"] = _serialize_interior_zones(geo.get("interior_zones", {}))
		else:
			room_dict["portals"] = []
			room_dict["interior_zones"] = {}

		room_dict["motif_requests"] = ROLE_MOTIFS.get(role, [])
		rooms_array.append(room_dict)

	# Build room_links from adjacencies
	var room_links: Array = _build_room_links(adjacencies)

	# Build vertical_connections
	var vertical_connections: Array = _build_vertical_connections(rooms_data, adjacencies, room_roles)

	# Build landmarks
	var landmarks: Array = _build_landmarks(rooms_data, room_roles, room_order)

	# Build critical path (BFS from first to last room)
	var entry_id: String = room_order[0] if not room_order.is_empty() else ""
	var dest_id: String = room_order[-1] if not room_order.is_empty() else ""
	var critical_path: Array = _build_critical_path(entry_id, dest_id, adjacencies)

	return {
		"schema_version": "1.1.0",
		"document_kind": "ship_layout",
		"program_id": "procgen-%s-seed-%d" % [archetype_name, seed_value],
		"kit_id": "ship_structural_v0",
		"design_intent": "procedurally generated %s ship" % template_id,
		"cell_size": CELL_SIZE,
		"rooms": rooms_array,
		"room_links": room_links,
		"blocked_links": [],
		"vertical_connections": vertical_connections,
		"landmarks": landmarks,
		"critical_path": critical_path,
		"fire_zones": [],
		"arc_zones": [],
		"breach_zones": [],
		"prototype": {
			"start_room": entry_id,
			"goal_room": dest_id,
		},
	}


func _build_structural_placements(cells: Array, deck: int, role: String) -> Array:
	var placements: Array = []
	var floor_module: String = FLOOR_MODULES.get(role, DEFAULT_FLOOR)

	for cell in cells:
		var x: int = cell.x if cell is Vector2i else int(cell.x)
		var z: int = cell.y if cell is Vector2i else int(cell.y)
		var world_x: float = float(x) * CELL_SIZE
		var world_y: float = float(deck) * DECK_HEIGHT
		var world_z: float = float(z) * CELL_SIZE

		var name: String
		if deck == 0:
			name = "floor_cell_x%d_z%d" % [x, z]
		else:
			name = "floor_cell_d%d_x%d_z%d" % [deck, x, z]

		placements.append({
			"name": name,
			"module": floor_module,
			"world_position": [world_x, world_y, world_z],
		})

	# Add ramp module for ramp rooms
	if role == "ramp" and not cells.is_empty():
		var first_cell = cells[0]
		var x: int = first_cell.x if first_cell is Vector2i else int(first_cell.x)
		var z: int = first_cell.y if first_cell is Vector2i else int(first_cell.y)
		placements.append({
			"name": "ramp_up_1x2",
			"module": "ramp_up_1x2",
			"world_position": [float(x) * CELL_SIZE, float(deck) * DECK_HEIGHT, float(z) * CELL_SIZE],
		})

	return placements


func _build_wall_placements(wall_segments: Array) -> Array:
	var placements: Array = []
	for wall in wall_segments:
		var pos: Variant = wall.get("position", Vector3.ZERO)
		var world_pos: Array
		if pos is Vector3:
			world_pos = [pos.x, pos.y, pos.z]
		else:
			world_pos = [0.0, 0.0, 0.0]

		placements.append({
			"name": str(wall.get("name", "")),
			"module": str(wall.get("module_id", "wall_straight_1x1")),
			"world_position": world_pos,
			"yaw_degrees": float(wall.get("yaw_degrees", 0.0)),
		})
	return placements


func _serialize_interior_zones(zones: Dictionary) -> Dictionary:
	var result: Dictionary = {}

	var reserved: Array = zones.get("reserved_cells", [])
	var serialized_reserved: Array = []
	for cell in reserved:
		if cell is Vector2i:
			serialized_reserved.append([cell.x, cell.y])
	result["reserved_cells"] = serialized_reserved

	var wall_slots: Array = zones.get("wall_slots", [])
	result["wall_slots"] = wall_slots

	var center: Array = zones.get("center_slots", [])
	var serialized_center: Array = []
	for cell in center:
		if cell is Vector2i:
			serialized_center.append([cell.x, cell.y])
	result["center_slots"] = serialized_center

	return result


func _build_room_links(adjacencies: Array) -> Array:
	var links: Array = []
	for adj in adjacencies:
		var from_room: String = str(adj.get("from_room", ""))
		var to_room: String = str(adj.get("to_room", ""))
		var from_cell: Variant = adj.get("from_cell", Vector2i.ZERO)
		var to_cell: Variant = adj.get("to_cell", Vector2i.ZERO)

		var from_arr: Array = [from_cell.x, from_cell.y, 0] if from_cell is Vector2i else [0, 0, 0]
		var to_arr: Array = [to_cell.x, to_cell.y, 0] if to_cell is Vector2i else [0, 0, 0]

		links.append({
			"id": "%s_to_%s" % [from_room, to_room],
			"from_room": from_room,
			"to_room": to_room,
			"from_cell": from_arr,
			"to_cell": to_arr,
			"module_id": "doorway_frame_open_1x1",
		})
	return links


func _build_vertical_connections(rooms_data: Dictionary, adjacencies: Array,
		room_roles: Dictionary) -> Array:
	var connections: Array = []
	for adj in adjacencies:
		var from_room: String = str(adj.get("from_room", ""))
		var to_room: String = str(adj.get("to_room", ""))
		if not rooms_data.has(from_room) or not rooms_data.has(to_room):
			continue
		var from_deck: int = int(rooms_data[from_room].get("deck", 0))
		var to_deck: int = int(rooms_data[to_room].get("deck", 0))
		if from_deck == to_deck:
			continue

		var from_role: String = room_roles.get(from_room, "")
		var module: String = "ramp_up_1x2" if from_role == "ramp" else "floor_1x1"

		var from_cell: Variant = adj.get("from_cell", Vector2i.ZERO)
		var to_cell: Variant = adj.get("to_cell", Vector2i.ZERO)
		var from_arr: Array = [from_cell.x, from_cell.y, from_deck] if from_cell is Vector2i else [0, 0, from_deck]
		var to_arr: Array = [to_cell.x, to_cell.y, to_deck] if to_cell is Vector2i else [0, 0, to_deck]

		connections.append({
			"id": "%s_to_%s" % [from_room, to_room],
			"type": "ramp" if from_role == "ramp" else "elevator",
			"module_id": module,
			"from_room": from_room,
			"from_cell": from_arr,
			"to_room": to_room,
			"to_cell": to_arr,
		})
	return connections


func _build_landmarks(rooms_data: Dictionary, room_roles: Dictionary,
		room_order: Array[String]) -> Array:
	var landmarks: Array = []

	# Find first hub/spine room — blue beacon
	for rid in room_order:
		var role: String = room_roles.get(rid, "")
		if role in ["hub", "main_spine"]:
			var pos: Array = _room_center_position(rooms_data.get(rid, {}))
			landmarks.append({
				"id": "%s_blue_beacon" % rid,
				"room_id": rid,
				"kind": "orientation_beacon",
				"position": pos,
				"color": "blue",
			})
			break

	# Destination room — green beacon
	if not room_order.is_empty():
		var dest_id: String = room_order[-1]
		var pos: Array = _room_center_position(rooms_data.get(dest_id, {}))
		landmarks.append({
			"id": "%s_green_core" % dest_id,
			"room_id": dest_id,
			"kind": "destination_core",
			"position": pos,
			"color": "green",
		})

	return landmarks


func _room_center_position(room_data: Dictionary) -> Array:
	var cells: Array = room_data.get("cells", [])
	var deck: int = int(room_data.get("deck", 0))
	if cells.is_empty():
		return [0.0, 0.0, 0.0]

	var sum_x: float = 0.0
	var sum_z: float = 0.0
	for cell in cells:
		var x: int = cell.x if cell is Vector2i else int(cell.x)
		var z: int = cell.y if cell is Vector2i else int(cell.y)
		sum_x += float(x) * CELL_SIZE
		sum_z += float(z) * CELL_SIZE
	var count: float = float(cells.size())
	return [sum_x / count, float(deck) * DECK_HEIGHT + 0.15, sum_z / count]


func _build_critical_path(start_id: String, end_id: String, adjacencies: Array) -> Array:
	if start_id.is_empty() or end_id.is_empty():
		return []

	# Build adjacency map
	var adj_map: Dictionary = {}
	for adj in adjacencies:
		var fr: String = str(adj["from_room"])
		var tr: String = str(adj["to_room"])
		if not adj_map.has(fr):
			adj_map[fr] = []
		adj_map[fr].append(tr)
		if not adj_map.has(tr):
			adj_map[tr] = []
		adj_map[tr].append(fr)

	# BFS
	var visited: Dictionary = {start_id: ""}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == end_id:
			break
		for neighbor in adj_map.get(current, []):
			if not visited.has(neighbor):
				visited[neighbor] = current
				queue.append(neighbor)

	if not visited.has(end_id):
		return [start_id]

	# Reconstruct path
	var path: Array = []
	var current: String = end_id
	while not current.is_empty():
		path.insert(0, current)
		current = str(visited.get(current, ""))
	return path
