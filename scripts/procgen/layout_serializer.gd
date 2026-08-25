extends RefCounted
class_name LayoutSerializer

# Assembles a complete layout.json Dictionary from pipeline stage outputs.
# Output matches the golden layout schema version 1.2.0 exactly — the emitted
# schema_version below IS the canonical version; layout_schema_coherence_smoke
# asserts the golden fixtures declare the same version and carry every
# top-level key emitted here. Bump both together.

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const StructuralEdgeCompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")

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

	# Build room role / variant lookup
	var room_roles: Dictionary = {}
	var room_variants: Dictionary = {}
	var room_order: Array[String] = []
	for room in room_plan:
		var rid: String = str(room["id"])
		room_roles[rid] = str(room.get("role", ""))
		room_variants[rid] = str(room.get("variant", "standard"))
		room_order.append(rid)

	# Assemble rooms array
	var rooms_array: Array = []
	var all_portals: Array = []
	for rid in room_order:
		if not rooms_data.has(rid):
			continue
		var room_data: Dictionary = rooms_data[rid]
		var role: String = room_roles.get(rid, "")
		var deck: int = int(room_data.get("deck", 0))
		var cells: Array = room_data.get("cells", [])

		var placements: Array = _build_structural_placements(cells, deck, role)
		var geo: Dictionary = geometry.get(rid, {})

		# Serialize cells to plain arrays for JSON round-trip
		var serialized_cells: Array = []
		for cell in cells:
			if cell is Vector2i:
				serialized_cells.append([cell.x, cell.y])
			elif cell is Array:
				serialized_cells.append(cell)
			else:
				serialized_cells.append([int(cell.x), int(cell.y)])

		var room_dict: Dictionary = {
			"id": rid,
			"room_role": role,
			"variant": str(room_variants.get(rid, "standard")),
			"deck": deck,
			"cells": serialized_cells,
			"footprint": _footprint_from_cells(cells),
			"structural_placements": placements,
		}

		# Add wall/portal/interior data if available
		if not geo.is_empty():
			var wall_placements: Array = _build_wall_placements(geo.get("wall_segments", []))
			# Append wall placements to structural_placements
			for wp in wall_placements:
				placements.append(wp)

			var room_portals: Array = _serialize_portals(geo.get("portals", []))
			room_dict["portals"] = room_portals
			for p in room_portals:
				var portal_copy: Dictionary = p.duplicate()
				portal_copy["from_room"] = rid
				all_portals.append(portal_copy)
			room_dict["interior_zones"] = _serialize_interior_zones(geo.get("interior_zones", {}))
		else:
			room_dict["portals"] = []
			room_dict["interior_zones"] = {}

		room_dict["motif_requests"] = ROLE_MOTIFS.get(role, [])
		rooms_array.append(room_dict)

	# Build room_links from adjacencies
	var room_links: Array = _build_room_links(adjacencies, rooms_data)

	# Build canonical portals from room_links (one entry per adjacency)
	# Cross-deck links (ramps/elevators) are excluded — they belong in
	# vertical_connections, not the portals array.
	var canonical_portals: Array = []
	for link in room_links:
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_cell: Array = link.get("from_cell", [0, 0, 0])
		var to_cell: Array = link.get("to_cell", [0, 0, 0])
		# Skip cross-deck links — those are vertical connections
		if from_cell.size() >= 3 and to_cell.size() >= 3 and int(from_cell[2]) != int(to_cell[2]):
			continue
		canonical_portals.append({
			"id": "portal_%s_%s" % [from_room, to_room],
			"from_room": from_room,
			"to_room": to_room,
			"from_cell": from_cell,
			"to_cell": to_cell,
			"state": "DOOR",
		})

	var vertical_connections: Array = _build_vertical_connections(rooms_data, adjacencies, room_roles)
	var structural_layout: Dictionary = {
		"cell_size": CELL_SIZE,
		"rooms": rooms_array,
		"portals": canonical_portals,
		"vertical_connections": vertical_connections,
	}
	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(structural_layout)

	# Build landmarks
	var landmarks: Array = _build_landmarks(rooms_data, room_roles, room_order)

	# Build critical path (BFS from first to last room)
	var entry_id: String = room_order[0] if not room_order.is_empty() else ""
	var dest_id: String = room_order[-1] if not room_order.is_empty() else ""
	var critical_path: Array = _build_critical_path(entry_id, dest_id, adjacencies)

	return {
		"schema_version": "1.2.0",
		"document_kind": "ship_layout",
		"program_id": "procgen-%s-seed-%d" % [archetype_name, seed_value],
		"kit_id": "ship_structural_v0",
		"design_intent": "procedurally generated %s ship" % template_id,
		"cell_size": CELL_SIZE,
		"rooms": rooms_array,
		"room_links": room_links,
		"portals": canonical_portals,
		"blocked_links": [],
		"vertical_connections": vertical_connections,
		"landmarks": landmarks,
		"critical_path": critical_path,
		"fire_zones": [],
		"arc_zones": [],
		"breach_zones": [],
		"encounters": [],  # populated by EncounterInjector (Task 12)
		"structural_plan": structural_plan,
		"prototype": {
			"start_room": entry_id,
			"goal_room": dest_id,
		},
	}


func _footprint_from_cells(cells: Array) -> Array:
	if cells.is_empty():
		return [0, 0]
	var min_x: int = 999999
	var max_x: int = -999999
	var min_z: int = 999999
	var max_z: int = -999999
	for cell in cells:
		var x: int = cell.x if cell is Vector2i else int(cell.x)
		var z: int = cell.y if cell is Vector2i else int(cell.y)
		min_x = mini(min_x, x)
		max_x = maxi(max_x, x)
		min_z = mini(min_z, z)
		max_z = maxi(max_z, z)
	return [max_x - min_x + 1, max_z - min_z + 1]


func _build_structural_placements(cells: Array, deck: int, role: String) -> Array:
	var placements: Array = []
	var floor_module: String = FLOOR_MODULES.get(role, DEFAULT_FLOOR)

	for cell in cells:
		var x: int = cell.x if cell is Vector2i else int(cell.x)
		var z: int = cell.y if cell is Vector2i else int(cell.y)
		var world_x: float = float(x) * CELL_SIZE
		var world_y: float = float(deck) * DECK_HEIGHT
		var world_z: float = float(z) * CELL_SIZE

		var cell_name: String
		if deck == 0:
			cell_name = "floor_cell_x%d_z%d" % [x, z]
		else:
			cell_name = "floor_cell_d%d_x%d_z%d" % [deck, x, z]

		placements.append({
			"name": cell_name,
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


func _serialize_portals(portals: Array) -> Array:
	var result: Array = []
	for portal_variant in portals:
		if typeof(portal_variant) != TYPE_DICTIONARY:
			continue
		var portal: Dictionary = (portal_variant as Dictionary).duplicate()
		var pos: Variant = portal.get("position")
		if pos is Vector3:
			portal["position"] = [pos.x, pos.y, pos.z]
		for cell_key in ["from_cell", "to_cell"]:
			var cell: Variant = portal.get(cell_key)
			if cell is Vector2i:
				portal[cell_key] = [cell.x, cell.y]
		result.append(portal)
	return result


func _serialize_interior_zones(zones: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["reserved_cells"] = _serialize_cell_list(zones.get("reserved_cells", []))
	result["center_slots"] = _serialize_cell_list(zones.get("center_slots", []))
	result["wall_slots"] = _serialize_wall_slots(zones.get("wall_slots", []))
	return result


## Slot cells are always JSON `[x, z]` (deck lives on the room). Parses Vector2i,
## arrays, and leftover "(x, y)" strings from older serializer output.
static func parse_slot_cell(value: Variant) -> Array:
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector2:
		return [int(round((value as Vector2).x)), int(round((value as Vector2).y))]
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return [int(arr[0]), int(arr[1])]
		return []
	if typeof(value) == TYPE_DICTIONARY:
		return parse_slot_cell((value as Dictionary).get("cell", null))
	if typeof(value) != TYPE_STRING:
		return []
	var s: String = (value as String).strip_edges()
	if s.begins_with("floor_cell"):
		return _parse_floor_cell_name(s)
	if s.begins_with("(") and s.ends_with(")") and s.length() >= 5:
		s = s.substr(1, s.length() - 2)
	var parts: PackedStringArray = s.split(",")
	if parts.size() < 2:
		return []
	var xs: String = String(parts[0]).strip_edges()
	var zs: String = String(parts[1]).strip_edges()
	if xs.is_valid_float() and zs.is_valid_float():
		return [int(round(float(xs))), int(round(float(zs)))]
	return []


static func _parse_floor_cell_name(placement_name: String) -> Array:
	var parts: PackedStringArray = placement_name.split("_")
	for i in range(parts.size()):
		if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
			var x_str: String = String(parts[i]).substr(1)
			var z_str: String = String(parts[i + 1]).substr(1)
			if x_str.is_valid_int() and z_str.is_valid_int():
				return [int(x_str), int(z_str)]
	return []


func _serialize_cell_list(cells: Array) -> Array:
	var serialized: Array = []
	for cell in cells:
		var parsed: Array = parse_slot_cell(cell)
		if parsed.size() >= 2:
			serialized.append(parsed)
	return serialized


func _serialize_wall_slots(slots: Array) -> Array:
	var serialized: Array = []
	for slot_variant in slots:
		var cell_value: Variant = slot_variant
		var against_wall: bool = true
		var extra: Dictionary = {}
		if typeof(slot_variant) == TYPE_DICTIONARY:
			var slot: Dictionary = slot_variant
			cell_value = slot.get("cell", null)
			against_wall = bool(slot.get("against_wall", true))
			for key in slot.keys():
				if str(key) == "cell" or str(key) == "against_wall":
					continue
				extra[key] = slot[key]
		var parsed: Array = parse_slot_cell(cell_value)
		if parsed.size() < 2:
			continue
		var entry: Dictionary = {
			"cell": parsed,
			"against_wall": against_wall,
		}
		for key in extra.keys():
			entry[key] = extra[key]
		serialized.append(entry)
	return serialized


func _build_room_links(adjacencies: Array, rooms_data: Dictionary) -> Array:
	var links: Array = []
	for adj in adjacencies:
		var from_room: String = str(adj.get("from_room", ""))
		var to_room: String = str(adj.get("to_room", ""))
		var from_cell: Variant = adj.get("from_cell", Vector2i.ZERO)
		var to_cell: Variant = adj.get("to_cell", Vector2i.ZERO)

		var from_deck: int = int(rooms_data.get(from_room, {}).get("deck", 0))
		var to_deck: int = int(rooms_data.get(to_room, {}).get("deck", 0))
		var from_arr: Array = [from_cell.x, from_cell.y, from_deck] if from_cell is Vector2i else [0, 0, from_deck]
		var to_arr: Array = [to_cell.x, to_cell.y, to_deck] if to_cell is Vector2i else [0, 0, to_deck]

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
	var current_path: String = end_id
	while not current_path.is_empty():
		path.insert(0, current_path)
		current_path = str(visited.get(current_path, ""))
	return path
