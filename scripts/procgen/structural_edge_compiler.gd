extends RefCounted
class_name StructuralEdgeCompiler

## Data-only compiler for the canonical ship boundary plan.
##
## Rooms own explicit integer occupancy cells. Floors are emitted once per
## occupied cell in `floor_placements`; walls and portals are emitted once per
## canonical shared edge in `placements`. No scene or wrapper lookup belongs in
## this layer.

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const FLOOR_MODULE: String = "floor_1x1"
const CORRIDOR_FLOOR_MODULE: String = "corridor_floor_1x1"
const WALL_MODULE: String = "wall_straight_1x1"
const DEFAULT_PORTAL_MODULE: String = "doorway_frame_open_1x1"
const DOOR_MODULE: String = "doorway_frame_open_1x1"
const LOCKED_MODULE: String = "doorway_frame_blocked_1x1"
const HATCH_MODULE: String = "bulkhead_portal_2x1"

const DIRECTIONS: Dictionary = {
	"north": Vector2i(0, -1),
	"east": Vector2i(1, 0),
	"south": Vector2i(0, 1),
	"west": Vector2i(-1, 0),
}
const OPPOSITE: Dictionary = {
	"north": "south",
	"east": "west",
	"south": "north",
	"west": "east",
}
const YAW_DEGREES: Dictionary = {
	"south": 0.0,
	"west": 90.0,
	"north": 180.0,
	"east": 270.0,
}
const SUPPORTED_EDGE_KINDS: Array[String] = ["SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"]


func compile(layout: Dictionary) -> Dictionary:
	var occupancy: Dictionary = {}
	var room_by_cell: Dictionary = {}
	var room_by_id: Dictionary = {}
	var room_role_by_id: Dictionary = {}
	var errors: Array[String] = []

	var rooms_variant: Variant = layout.get("rooms", null)
	if typeof(rooms_variant) != TYPE_ARRAY:
		return _empty_plan(["layout rooms must be an array"])
	var rooms: Array = rooms_variant
	if rooms.is_empty():
		return _empty_plan(["layout rooms must be non-empty"])

	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			errors.append("room record must be an object")
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		if room_id.is_empty():
			errors.append("room is missing id")
			continue
		if room_by_id.has(room_id):
			errors.append("duplicate room id: %s" % room_id)
			continue
		if not _is_integer(room.get("deck", null)):
			errors.append("room %s has invalid deck" % room_id)
			continue
		var deck: int = int(room.get("deck"))
		room_by_id[room_id] = room
		room_role_by_id[room_id] = str(room.get("room_role", room.get("role", "")))
		var cells_variant: Variant = room.get("cells", null)
		if typeof(cells_variant) != TYPE_ARRAY or (cells_variant as Array).is_empty():
			errors.append("room %s must declare non-empty cells" % room_id)
			continue
		for raw_cell in (cells_variant as Array):
			var cell_info: Dictionary = _read_cell(raw_cell, deck)
			if not bool(cell_info.get("ok", false)):
				errors.append("room %s has invalid cell: %s" % [room_id, str(raw_cell)])
				continue
			if int(cell_info["deck"]) != deck:
				errors.append("room %s cell deck mismatch" % room_id)
				continue
			var cell: Vector2i = cell_info["cell"]
			var key: String = cell_key(deck, cell)
			if room_by_cell.has(key):
				errors.append("occupied-cell overlap: %s owned by %s and %s" % [key, room_by_cell[key], room_id])
				continue
			room_by_cell[key] = room_id
			var role_name: String = str(room_role_by_id[room_id])
			var occupancy_floor_module: String = CORRIDOR_FLOOR_MODULE if role_name == "corridor" or role_name == "main_spine" else FLOOR_MODULE
			occupancy[key] = {
				"cell_key": key,
				"deck": deck,
				"cell": cell,
				"room_id": room_id,
				"room_ids": [room_id],
				"position": cell_world_position(deck, cell),
				"module_id": occupancy_floor_module,
			}

	var portal_by_edge: Dictionary = _index_portals(layout, room_by_id, room_by_cell, errors)
	var edge_map: Dictionary = {}
	var edge_placements: Array = []
	var floor_placements: Array = []

	for occupancy_key in occupancy.keys():
		var cell_record: Dictionary = occupancy[occupancy_key]
		var deck: int = int(cell_record["deck"])
		var cell: Vector2i = cell_record["cell"]
		var room_id: String = str(cell_record["room_id"])
		var role: String = str(room_role_by_id.get(room_id, ""))
		var floor_module: String = CORRIDOR_FLOOR_MODULE if role == "corridor" or role == "main_spine" else FLOOR_MODULE
		floor_placements.append({
			"id": "floor:%s" % occupancy_key,
			"placement_id": "floor:%s" % occupancy_key,
			"module_id": floor_module,
			"position": cell_world_position(deck, cell),
			"yaw_degrees": 0.0,
			"deck": deck,
			"cell": cell,
			"cell_key": occupancy_key,
			"room_id": room_id,
			"room_ids": [room_id],
		})

		for direction in ["north", "east", "south", "west"]:
			var edge_key_value: String = edge_key(deck, cell, direction)
			if edge_map.has(edge_key_value):
				continue
			var delta: Vector2i = DIRECTIONS[direction]
			var neighbor: Vector2i = cell + delta
			var neighbor_key: String = cell_key(deck, neighbor)
			var other_room: String = str(room_by_cell.get(neighbor_key, ""))
			var portal_variant: Variant = portal_by_edge.get(edge_key_value, null)
			var portal: Dictionary = portal_variant if typeof(portal_variant) == TYPE_DICTIONARY else {}
			var edge_state: String = "SOLID"
			var module_id: String = WALL_MODULE
			var portal_present: bool = not portal.is_empty()
			var edge_other_room: String = other_room
			if portal_present and edge_other_room.is_empty():
				edge_other_room = str(portal.get("edge_other_room", ""))
			var wrapper_required: bool = true
			if not edge_other_room.is_empty() and edge_other_room == room_id and not portal_present:
				edge_state = "OPEN"
				module_id = ""
				wrapper_required = false
			elif portal_present:
				edge_state = _portal_kind(portal, layout)
				module_id = _portal_module(portal, edge_state)
				wrapper_required = edge_state != "BREACH" or not module_id.is_empty()
				if edge_other_room.is_empty() and not bool(portal.get("exterior", false)):
					errors.append("portal endpoint is exterior without explicit exterior flag: %s" % edge_key_value)
			elif not edge_other_room.is_empty() and edge_other_room != room_id:
				edge_state = "SOLID"
				module_id = WALL_MODULE
			else:
				edge_state = "SOLID"
				module_id = WALL_MODULE

			if not SUPPORTED_EDGE_KINDS.has(edge_state):
				errors.append("unsupported edge kind %s at %s" % [edge_state, edge_key_value])
				edge_state = "SOLID"
				module_id = WALL_MODULE
			var source_cells: Array = [cell_with_deck(cell, deck), cell_with_deck(neighbor, deck)]
			var room_ids: Array = [room_id, edge_other_room]
			var edge_position: Vector3 = edge_world_position(deck, cell, direction)
			var edge_record: Dictionary = {
				"id": "edge:%s" % edge_key_value,
				"key": edge_key_value,
				"edge_key": edge_key_value,
				"deck": deck,
				"cell": cell,
				"direction": direction,
				"opposite_direction": str(OPPOSITE[direction]),
				"source_cells": source_cells,
				"room_ids": room_ids,
				"owner_room": room_id,
				"other_room": edge_other_room,
				"kind": edge_state,
				"state": edge_state,
				"module_id": module_id,
				"position": edge_position,
				"yaw_degrees": float(YAW_DEGREES[direction]),
				"portal": portal_present,
				"exterior": edge_other_room.is_empty(),
				"placement_required": wrapper_required,
				"wrapper_required": wrapper_required,
			}
			if portal_present:
				var logical_boundary: bool = bool(portal.get("logical_boundary", false))
				edge_record["logical_boundary"] = logical_boundary
				if logical_boundary:
					edge_record["logical_from_cell"] = portal.get("logical_from_cell", portal.get("from_cell", null))
					edge_record["logical_to_cell"] = portal.get("logical_to_cell", portal.get("to_cell", null))
			edge_map[edge_key_value] = edge_record
			if edge_state == "OPEN" or not wrapper_required:
				continue
			var placement: Dictionary = edge_record.duplicate(true)
			placement["placement_id"] = "edge:%s" % edge_key_value
			edge_placements.append(placement)

	return {
		"occupancy": occupancy,
		"edges": edge_map,
		"placements": edge_placements,
		"floor_placements": floor_placements,
		"errors": errors,
	}


static func cell_key(deck: int, cell: Vector2i) -> String:
	return "%d|%d|%d" % [deck, cell.x, cell.y]


static func edge_key(deck: int, cell: Vector2i, direction: String) -> String:
	if not DIRECTIONS.has(direction):
		return ""
	var neighbor: Vector2i = cell + (DIRECTIONS[direction] as Vector2i)
	if direction == "north" or direction == "south":
		return "%d|h|%d|%d" % [deck, mini(cell.y, neighbor.y), cell.x]
	return "%d|v|%d|%d" % [deck, cell.y, mini(cell.x, neighbor.x)]


static func cell_world_position(deck: int, cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL_SIZE, float(deck) * DECK_HEIGHT, float(cell.y) * CELL_SIZE)


static func edge_world_position(deck: int, cell: Vector2i, direction: String) -> Vector3:
	var center: Vector3 = cell_world_position(deck, cell)
	var delta: Vector2i = DIRECTIONS.get(direction, Vector2i.ZERO)
	return center + Vector3(float(delta.x) * CELL_SIZE * 0.5, 0.0, float(delta.y) * CELL_SIZE * 0.5)


static func cell_with_deck(cell: Vector2i, deck: int) -> Array:
	return [cell.x, cell.y, deck]


func _empty_plan(errors: Array[String]) -> Dictionary:
	return {
		"occupancy": {},
		"edges": {},
		"placements": [],
		"floor_placements": [],
		"errors": errors,
	}


func _index_portals(layout: Dictionary, room_by_id: Dictionary, room_by_cell: Dictionary, errors: Array[String]) -> Dictionary:
	var indexed: Dictionary = {}
	var portals_variant: Variant = layout.get("portals", null)
	if typeof(portals_variant) != TYPE_ARRAY:
		errors.append("layout missing canonical portals array")
		return indexed
	for portal_variant in (portals_variant as Array):
		if typeof(portal_variant) != TYPE_DICTIONARY:
			errors.append("portal record must be an object")
			continue
		var portal: Dictionary = portal_variant
		var from_room: String = str(portal.get("from_room", ""))
		var to_room: String = str(portal.get("to_room", ""))
		if not room_by_id.has(from_room) or not room_by_id.has(to_room) or from_room == to_room:
			errors.append("portal room endpoints are invalid: %s" % str(portal.get("id", "")))
			continue
		var from_deck: int = int(room_by_id[from_room].get("deck", -1))
		var to_deck: int = int(room_by_id[to_room].get("deck", -1))
		var from_info: Dictionary = _read_cell(portal.get("from_cell", null), from_deck)
		var to_info: Dictionary = _read_cell(portal.get("to_cell", null), to_deck)
		if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
			errors.append("portal endpoints are malformed: %s" % str(portal.get("id", "")))
			continue
		if int(from_info["deck"]) != from_deck or int(to_info["deck"]) != to_deck:
			errors.append("portal endpoint deck mismatch: %s" % str(portal.get("id", "")))
			continue
		if from_deck != to_deck:
			errors.append("cross-deck portal must remain a vertical connection: %s" % str(portal.get("id", "")))
			continue
		var from_cell: Vector2i = from_info["cell"]
		var to_cell: Vector2i = to_info["cell"]
		var from_key: String = cell_key(from_deck, from_cell)
		var to_key: String = cell_key(to_deck, to_cell)
		if str(room_by_cell.get(from_key, "")) != from_room or str(room_by_cell.get(to_key, "")) != to_room:
			errors.append("portal endpoints are not owned by declared rooms: %s" % str(portal.get("id", "")))
			continue
		var edge_cell: Vector2i = from_cell
		var direction: String = _direction_between(from_cell, to_cell)
		var logical_boundary: bool = false
		if direction.is_empty() and typeof(portal.get("edge_cell", null)) != TYPE_NIL:
			var edge_info: Dictionary = _read_cell(portal.get("edge_cell", null), from_deck)
			var declared_direction: String = str(portal.get("edge_direction", ""))
			if bool(edge_info.get("ok", false)) and DIRECTIONS.has(declared_direction) and str(room_by_cell.get(cell_key(from_deck, edge_info["cell"]), "")) == from_room:
				edge_cell = edge_info["cell"]
				direction = declared_direction
				logical_boundary = true
		if direction.is_empty():
			errors.append("portal endpoints are not adjacent: %s" % str(portal.get("id", "")))
			continue
		var key: String = edge_key(from_deck, edge_cell, direction)
		if indexed.has(key):
			errors.append("duplicate portal edge: %s" % key)
			continue
		var indexed_portal: Dictionary = portal.duplicate(true)
		indexed_portal["edge_key"] = key
		indexed_portal["direction"] = direction
		indexed_portal["edge_cell"] = edge_cell
		indexed_portal["edge_other_room"] = to_room
		indexed_portal["logical_from_cell"] = from_cell
		indexed_portal["logical_to_cell"] = to_cell
		indexed_portal["logical_boundary"] = logical_boundary
		indexed_portal["from_cell_key"] = from_key
		indexed_portal["to_cell_key"] = to_key
		indexed[key] = indexed_portal
	return indexed


func _direction_between(from_cell: Vector2i, to_cell: Vector2i) -> String:
	var delta: Vector2i = to_cell - from_cell
	for direction in DIRECTIONS.keys():
		if (DIRECTIONS[direction] as Vector2i) == delta:
			return str(direction)
	return ""


func _portal_kind(portal: Dictionary, layout: Dictionary = {}) -> String:
	if _blocked_link_matches(portal, layout):
		return "LOCKED"
	var raw: String = str(portal.get("state", portal.get("portal_type", portal.get("kind", "DOOR")))).to_upper()
	if raw == "OPEN":
		return "DOOR"
	if raw == "DOOR" or raw == "LOCKED" or raw == "HATCH" or raw == "BREACH":
		return raw
	return "DOOR"


func _blocked_link_matches(portal: Dictionary, layout: Dictionary) -> bool:
	var blocked_variant: Variant = layout.get("blocked_links", [])
	if typeof(blocked_variant) != TYPE_ARRAY:
		return false
	var portal_from: String = str(portal.get("from_room", ""))
	var portal_to: String = str(portal.get("to_room", ""))
	var portal_from_cell: Vector2i = _cell_xz(portal.get("from_cell", portal.get("logical_from_cell", null)))
	var portal_to_cell: Vector2i = _cell_xz(portal.get("to_cell", portal.get("logical_to_cell", null)))
	for link_variant in (blocked_variant as Array):
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var rooms_match: bool = (from_room == portal_from and to_room == portal_to) \
			or (from_room == portal_to and to_room == portal_from)
		if not rooms_match:
			continue
		var from_cell: Vector2i = _cell_xz(link.get("from_cell", null))
		var to_cell: Vector2i = _cell_xz(link.get("to_cell", null))
		if from_cell == Vector2i(-99999, -99999) or to_cell == Vector2i(-99999, -99999):
			continue
		if (from_cell == portal_from_cell and to_cell == portal_to_cell) \
				or (from_cell == portal_to_cell and to_cell == portal_from_cell):
			return true
	return false


func _cell_xz(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(-99999, -99999)


func _portal_module(portal: Dictionary, state: String) -> String:
	var declared: String = str(portal.get("module_id", ""))
	if not declared.is_empty():
		return declared
	if state == "LOCKED":
		return LOCKED_MODULE
	if state == "HATCH":
		return HATCH_MODULE
	if state == "BREACH":
		return ""
	return DEFAULT_PORTAL_MODULE


func _read_cell(value: Variant, default_deck: int) -> Dictionary:
	if typeof(value) == TYPE_VECTOR2I:
		return {"ok": default_deck >= 0, "cell": value, "deck": default_deck}
	if typeof(value) != TYPE_ARRAY:
		if typeof(value) == TYPE_STRING:
			var parsed: Array = _parse_vector_string(str(value), 2)
			if parsed.size() == 2 and default_deck >= 0:
				return {"ok": true, "cell": Vector2i(int(parsed[0]), int(parsed[1])), "deck": default_deck}
		return {"ok": false}
	var values: Array = value
	if values.size() < 2 or not _is_integer(values[0]) or not _is_integer(values[1]):
		return {"ok": false}
	var deck: int = default_deck
	if values.size() >= 3:
		if not _is_integer(values[2]):
			return {"ok": false}
		deck = int(values[2])
	if deck < 0:
		return {"ok": false}
	return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1])), "deck": deck}


func _parse_vector_string(value: String, expected: int) -> Array:
	var text: String = value.strip_edges()
	if text.begins_with("(") and text.ends_with(")"):
		text = text.substr(1, text.length() - 2)
	var pieces: PackedStringArray = text.split(",")
	if pieces.size() != expected:
		return []
	var result: Array = []
	for piece in pieces:
		var token: String = piece.strip_edges()
		if not token.is_valid_float():
			return []
		result.append(float(token))
	return result


func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(float(value), roundf(float(value)))
	if typeof(value) == TYPE_STRING:
		return str(value).is_valid_int()
	return false
