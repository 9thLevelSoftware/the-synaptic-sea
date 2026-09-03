extends RefCounted
class_name StructuralEdgeCompiler

## Data-only compiler for the canonical ship boundary plan.
##
## Rooms own explicit integer occupancy cells. Floors are emitted once per
## occupied cell in `floor_placements`; walls and portals are emitted once per
## canonical shared edge in `placements`. Ceilings and socket_bindings live
## inside the same plan. Module ids are chosen by ModularAssetSpec socket match.
## No scene or wrapper lookup belongs in this layer.

const ModularSocketCatalogScript: GDScript = preload("res://scripts/procgen/modular_socket_catalog.gd")
const StructuralEdgePlanScript: GDScript = preload("res://scripts/procgen/structural_edge_plan.gd")

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const FLOOR_MODULE: String = "floor_1x1"
const CORRIDOR_FLOOR_MODULE: String = "corridor_floor_1x1"
const FLOOR_KIND: String = "FLOOR"
const CEILING_MODULE: String = "ceiling_cap_1x1"
const WALL_MODULE: String = "wall_straight_1x1"
const WALL_END_CAP_MODULE: String = "wall_end_cap"
const WALL_INNER_CORNER_MODULE: String = "wall_inner_corner"
const WALL_OUTER_CORNER_MODULE: String = "wall_outer_corner"
const WALL_T_JUNCTION_MODULE: String = "wall_t_junction"
const DEFAULT_PORTAL_MODULE: String = "doorway_frame_open_1x1"
const DOOR_MODULE: String = "doorway_frame_open_1x1"
const LOCKED_MODULE: String = "doorway_frame_blocked_1x1"
const HATCH_MODULE: String = "bulkhead_portal_2x1"
const INNER_CORNER_MODULE: String = "wall_inner_corner"
const OUTER_CORNER_MODULE: String = "wall_outer_corner"
const T_JUNCTION_MODULE: String = "wall_t_junction"
const DEFAULT_KIT_ID: String = "ship_structural_v0"

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
const CARDINALS: Array[String] = ["north", "east", "south", "west"]
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

	var catalog = ModularSocketCatalogScript.new()
	var kit_id: String = str(layout.get("kit_id", DEFAULT_KIT_ID))
	if kit_id.is_empty():
		kit_id = DEFAULT_KIT_ID
	if not catalog.load_kit(kit_id):
		errors.append("structural kit contracts missing: %s" % kit_id)

	var floor_module_default: String = catalog.choose_module(["floor_edge", "floor_top"], FLOOR_MODULE)
	if floor_module_default.is_empty():
		floor_module_default = FLOOR_MODULE
	var corridor_floor_module: String = catalog.choose_module(["floor_edge", "floor_top"], CORRIDOR_FLOOR_MODULE)
	if corridor_floor_module.is_empty():
		corridor_floor_module = CORRIDOR_FLOOR_MODULE
	var ceiling_module: String = catalog.choose_module(["ceiling_edge", "ceiling_bottom"], CEILING_MODULE)
	if ceiling_module.is_empty():
		ceiling_module = CEILING_MODULE
	var wall_module: String = catalog.choose_module(["wall_base", "wall_end"], WALL_MODULE)
	if wall_module.is_empty():
		wall_module = WALL_MODULE
	var inner_corner_module: String = catalog.choose_module(["inner_corner_vertex"], INNER_CORNER_MODULE)
	if inner_corner_module.is_empty():
		inner_corner_module = INNER_CORNER_MODULE
	var outer_corner_module: String = catalog.choose_module(["outer_corner_vertex"], OUTER_CORNER_MODULE)
	if outer_corner_module.is_empty():
		outer_corner_module = OUTER_CORNER_MODULE
	var t_junction_module: String = T_JUNCTION_MODULE if catalog.has_module(T_JUNCTION_MODULE) else catalog.choose_module(["wall_face"], T_JUNCTION_MODULE)

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
			var occupancy_floor_module: String = corridor_floor_module if role_name == "corridor" or role_name == "main_spine" else floor_module_default
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
	var opening_keys: Dictionary = _vertical_opening_keys(layout, room_by_id)
	var edge_map: Dictionary = {}
	var edge_placements: Array = []
	var floor_placements: Array = []
	var ceiling_placements: Array = []

	for occupancy_key in occupancy.keys():
		var cell_record: Dictionary = occupancy[occupancy_key]
		var deck: int = int(cell_record["deck"])
		var cell: Vector2i = cell_record["cell"]
		var room_id: String = str(cell_record["room_id"])
		var role: String = str(room_role_by_id.get(room_id, ""))
		var floor_module: String = corridor_floor_module if role == "corridor" or role == "main_spine" else floor_module_default
		floor_placements.append({
			"id": "floor:%s" % occupancy_key,
			"placement_id": "floor:%s" % occupancy_key,
			"module_id": floor_module,
			"position": cell_world_position(deck, cell),
			"yaw_degrees": 0.0,
			"deck": deck,
			"cell": cell,
			"cell_key": occupancy_key,
			"kind": FLOOR_KIND,
			"room_id": room_id,
			"room_ids": [room_id],
		})
		if not opening_keys.has(occupancy_key):
			ceiling_placements.append({
				"id": "ceiling:%s" % occupancy_key,
				"placement_id": "ceiling:%s" % occupancy_key,
				"module_id": ceiling_module,
				"position": cell_world_position(deck, cell),
				"yaw_degrees": 0.0,
				"deck": deck,
				"cell": cell,
				"cell_key": occupancy_key,
				"room_id": room_id,
				"room_ids": [room_id],
			})

		for direction in CARDINALS:
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
			var module_id: String = wall_module
			var portal_present: bool = not portal.is_empty()
			var edge_other_room: String = other_room
			if portal_present and edge_other_room.is_empty():
				edge_other_room = str(portal.get("edge_other_room", ""))
			var wrapper_required: bool = true
			var placement_required: bool = true
			if not edge_other_room.is_empty() and edge_other_room == room_id and not portal_present:
				edge_state = "OPEN"
				module_id = ""
				wrapper_required = false
				placement_required = false
			elif portal_present:
				edge_state = _portal_kind(portal, layout)
				module_id = _portal_module_from_catalog(catalog, portal, edge_state)
				if edge_state == "BREACH":
					# BREACH is a non-wrapper exterior state — no module, no placement.
					module_id = ""
					wrapper_required = false
					placement_required = false
				elif edge_state == "LOCKED":
					if module_id.is_empty():
						module_id = LOCKED_MODULE
					wrapper_required = true
					placement_required = true
				else:
					wrapper_required = true
					placement_required = true
				if edge_other_room.is_empty() and not bool(portal.get("exterior", false)) and edge_state != "BREACH" and edge_state != "HATCH":
					errors.append("portal endpoint is exterior without explicit exterior flag: %s" % edge_key_value)
			elif not edge_other_room.is_empty() and edge_other_room != room_id:
				edge_state = "SOLID"
				module_id = wall_module
			else:
				edge_state = "SOLID"
				module_id = wall_module

			if not SUPPORTED_EDGE_KINDS.has(edge_state):
				errors.append("unsupported edge kind %s at %s" % [edge_state, edge_key_value])
				edge_state = "SOLID"
				module_id = wall_module
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
				"placement_required": placement_required,
				"wrapper_required": wrapper_required,
			}
			if portal_present:
				var logical_boundary: bool = bool(portal.get("logical_boundary", false))
				edge_record["logical_boundary"] = logical_boundary
				if logical_boundary:
					edge_record["logical_from_cell"] = portal.get("logical_from_cell", portal.get("from_cell", null))
					edge_record["logical_to_cell"] = portal.get("logical_to_cell", portal.get("to_cell", null))
			edge_map[edge_key_value] = edge_record

	_apply_vertex_modules(
		occupancy,
		edge_map,
		catalog,
		inner_corner_module,
		outer_corner_module,
		t_junction_module,
		wall_module
	)

	for occupancy_key in occupancy.keys():
		var cell_record: Dictionary = occupancy[occupancy_key]
		var deck: int = int(cell_record["deck"])
		var cell: Vector2i = cell_record["cell"]
		for direction in CARDINALS:
			var edge_key_value: String = edge_key(deck, cell, direction)
			if not edge_map.has(edge_key_value):
				continue
			var edge_record: Dictionary = edge_map[edge_key_value]
			if str(edge_record.get("kind", "")) == "OPEN" or not bool(edge_record.get("wrapper_required", true)):
				continue
			var already: bool = false
			for existing_variant in edge_placements:
				if typeof(existing_variant) == TYPE_DICTIONARY and str((existing_variant as Dictionary).get("edge_key", "")) == edge_key_value:
					already = true
					break
			if already:
				continue
			var placement: Dictionary = edge_record.duplicate(true)
			placement["placement_id"] = "edge:%s" % edge_key_value
			edge_placements.append(placement)

	_refine_wall_modules(edge_map, edge_placements)

	var socket_bindings: Array = _emit_socket_bindings(
		catalog,
		floor_placements,
		ceiling_placements,
		edge_placements
	)
	_attach_bindings_to_records(floor_placements, socket_bindings)
	_attach_bindings_to_records(ceiling_placements, socket_bindings)
	_attach_bindings_to_records(edge_placements, socket_bindings)

	# Build the deterministic emitted_edge_keys diagnostic so validators and
	# callers can detect duplicate canonical edges without re-walking edge_map.
	var emitted_edge_keys: Array = []
	for ek in edge_map.keys():
		emitted_edge_keys.append(str(ek))
	emitted_edge_keys.sort()

	return {
		"occupancy": occupancy,
		"edges": edge_map,
		"placements": edge_placements,
		"floor_placements": floor_placements,
		"ceiling_placements": ceiling_placements,
		"socket_bindings": socket_bindings,
		"emitted_edge_keys": emitted_edge_keys,
		"errors": errors,
	}


static func cell_key(deck: int, cell: Vector2i) -> String:
	return StructuralEdgePlanScript.cell_key(deck, cell)


static func edge_key(deck: int, cell: Vector2i, direction: String) -> String:
	return StructuralEdgePlanScript.edge_key(deck, cell, direction)


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
		"ceiling_placements": [],
		"socket_bindings": [],
		"errors": errors,
	}


func _vertical_opening_keys(layout: Dictionary, room_by_id: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var vertical_variant: Variant = layout.get("vertical_connections", [])
	if typeof(vertical_variant) != TYPE_ARRAY:
		return keys
	for link_variant in (vertical_variant as Array):
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_deck: int = -1
		var to_deck: int = -1
		if room_by_id.has(from_room):
			from_deck = int((room_by_id[from_room] as Dictionary).get("deck", -1))
		if room_by_id.has(to_room):
			to_deck = int((room_by_id[to_room] as Dictionary).get("deck", -1))
		var from_info: Dictionary = _read_cell(link.get("from_cell", null), from_deck)
		var to_info: Dictionary = _read_cell(link.get("to_cell", null), to_deck)
		if bool(from_info.get("ok", false)):
			keys[cell_key(int(from_info["deck"]), from_info["cell"])] = true
		if bool(to_info.get("ok", false)):
			keys[cell_key(int(to_info["deck"]), to_info["cell"])] = true
	return keys


func _apply_vertex_modules(
		occupancy: Dictionary,
		edge_map: Dictionary,
		catalog,
		inner_corner_module: String,
		outer_corner_module: String,
		t_junction_module: String,
		wall_module: String) -> void:
	var seen_vertices: Dictionary = {}
	for occupancy_key in occupancy.keys():
		var cell_record: Dictionary = occupancy[occupancy_key]
		var deck: int = int(cell_record["deck"])
		var cell: Vector2i = cell_record["cell"]
		for dx in range(2):
			for dz in range(2):
				var vx: int = cell.x + dx
				var vz: int = cell.y + dz
				var vertex_key: String = "%d|%d|%d" % [deck, vx, vz]
				if seen_vertices.has(vertex_key):
					continue
				seen_vertices[vertex_key] = true
				var solid_keys: Array[String] = []
				var candidate_edges: Array[String] = [
					edge_key(deck, Vector2i(vx - 1, vz - 1), "east"),
					edge_key(deck, Vector2i(vx - 1, vz), "east"),
					edge_key(deck, Vector2i(vx - 1, vz - 1), "south"),
					edge_key(deck, Vector2i(vx, vz - 1), "south"),
				]
				for candidate in candidate_edges:
					if candidate.is_empty() or not edge_map.has(candidate):
						continue
					var edge: Dictionary = edge_map[candidate]
					var kind: String = str(edge.get("kind", ""))
					if kind == "SOLID":
						solid_keys.append(candidate)
				if solid_keys.is_empty():
					continue
				var occupied_count: int = 0
				for cell_offset in [Vector2i(vx - 1, vz - 1), Vector2i(vx, vz - 1), Vector2i(vx - 1, vz), Vector2i(vx, vz)]:
					if occupancy.has(cell_key(deck, cell_offset)):
						occupied_count += 1
				var assigned_module: String = ""
				if solid_keys.size() >= 3 and catalog.has_module(t_junction_module):
					assigned_module = t_junction_module
				elif occupied_count == 3 and solid_keys.size() >= 2 and catalog.has_module(inner_corner_module):
					assigned_module = inner_corner_module
				elif occupied_count == 1 and solid_keys.size() >= 2 and catalog.has_module(outer_corner_module):
					assigned_module = outer_corner_module
				if assigned_module.is_empty():
					continue
				var target_key: String = _first_replaceable_wall(edge_map, solid_keys, wall_module)
				if target_key.is_empty():
					continue
				var target: Dictionary = edge_map[target_key]
				target["module_id"] = assigned_module


func _first_replaceable_wall(edge_map: Dictionary, solid_keys: Array[String], wall_module: String) -> String:
	for edge_key_value in solid_keys:
		var edge: Dictionary = edge_map[edge_key_value]
		if bool(edge.get("portal", false)):
			continue
		var module_id: String = str(edge.get("module_id", ""))
		if module_id == wall_module or module_id == WALL_MODULE:
			return edge_key_value
	for edge_key_value in solid_keys:
		var edge: Dictionary = edge_map[edge_key_value]
		if not bool(edge.get("portal", false)):
			return edge_key_value
	return ""


func _emit_socket_bindings(
		catalog,
		floor_placements: Array,
		ceiling_placements: Array,
		edge_placements: Array) -> Array:
	var bindings: Array = []
	var all_records: Array = []
	all_records.append_array(floor_placements)
	all_records.append_array(ceiling_placements)
	all_records.append_array(edge_placements)
	for i in range(all_records.size()):
		if typeof(all_records[i]) != TYPE_DICTIONARY:
			continue
		var record_a: Dictionary = all_records[i]
		var module_a: String = str(record_a.get("module_id", ""))
		var pos_a: Vector3 = _as_vector3(record_a.get("position", Vector3.ZERO))
		var yaw_a: float = float(record_a.get("yaw_degrees", 0.0))
		for j in range(i + 1, all_records.size()):
			if typeof(all_records[j]) != TYPE_DICTIONARY:
				continue
			var record_b: Dictionary = all_records[j]
			var module_b: String = str(record_b.get("module_id", ""))
			var pos_b: Vector3 = _as_vector3(record_b.get("position", Vector3.ZERO))
			var yaw_b: float = float(record_b.get("yaw_degrees", 0.0))
			if pos_a.distance_to(pos_b) > CELL_SIZE * 1.5:
				continue
			for socket_a_variant in catalog.sockets_of(module_a):
				if typeof(socket_a_variant) != TYPE_DICTIONARY:
					continue
				var socket_a: Dictionary = socket_a_variant
				for socket_b_variant in catalog.sockets_of(module_b):
					if typeof(socket_b_variant) != TYPE_DICTIONARY:
						continue
					var socket_b: Dictionary = socket_b_variant
					if not _sockets_match(catalog, socket_a, socket_b):
						continue
					var world_a: Vector3 = catalog.world_socket_position(pos_a, yaw_a, catalog.socket_local_position(socket_a))
					var world_b: Vector3 = catalog.world_socket_position(pos_b, yaw_b, catalog.socket_local_position(socket_b))
					if not catalog.positions_agree(world_a, world_b):
						continue
					bindings.append(_binding_record(record_a, socket_a, record_b, socket_b))
					bindings.append(_binding_record(record_b, socket_b, record_a, socket_a))
	return bindings


func _sockets_match(catalog, socket_a: Dictionary, socket_b: Dictionary) -> bool:
	# A pair matches when each socket's kind is in the other's compatible_kinds
	# (or the kinds are equal) and world positions agree after yaw.
	return catalog.sockets_compatible(socket_a, socket_b)


func _binding_record(local_record: Dictionary, local_socket: Dictionary, neighbor_record: Dictionary, neighbor_socket: Dictionary) -> Dictionary:
	return {
		"placement_id": str(local_record.get("placement_id", local_record.get("id", ""))),
		"socket_id": str(local_socket.get("id", "")),
		"neighbor_placement_id": str(neighbor_record.get("placement_id", neighbor_record.get("id", ""))),
		"neighbor_socket_id": str(neighbor_socket.get("id", "")),
		"kind": str(local_socket.get("kind", "")),
	}


func _attach_bindings_to_records(records: Array, bindings: Array) -> void:
	var by_id: Dictionary = {}
	for binding_variant in bindings:
		if typeof(binding_variant) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_variant
		var placement_id: String = str(binding.get("placement_id", ""))
		if placement_id.is_empty():
			continue
		if not by_id.has(placement_id):
			by_id[placement_id] = []
		(by_id[placement_id] as Array).append(binding)
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var placement_id: String = str(record.get("placement_id", record.get("id", "")))
		record["socket_bindings"] = (by_id.get(placement_id, []) as Array).duplicate(true)


func _portal_module_from_catalog(catalog, portal: Dictionary, state: String) -> String:
	var declared: String = str(portal.get("module_id", ""))
	if not declared.is_empty() and catalog.has_module(declared) and catalog.has_kind(declared, "portal_edge"):
		return declared
	var preferred: String = DEFAULT_PORTAL_MODULE
	if state == "LOCKED":
		preferred = LOCKED_MODULE
	elif state == "HATCH":
		preferred = HATCH_MODULE
	elif state == "BREACH":
		return declared
	var chosen: String = catalog.choose_module(["portal_edge", "wall_base"], preferred)
	if chosen.is_empty():
		return _portal_module(portal, state)
	return chosen


func _as_vector3(value: Variant) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO


func _refine_wall_modules(edge_map: Dictionary, edge_placements: Array) -> void:
	## Post-pass: replace wall_straight_1x1 with corner/end-cap/t-junction
	## based on neighboring SOLID edge topology at each endpoint.
	for placement in edge_placements:
		var kind: String = str(placement.get("kind", ""))
		if kind != "SOLID":
			continue
		var module_id: String = str(placement.get("module_id", ""))
		if module_id != WALL_MODULE:
			continue  # already a portal or special module
		var ek: String = str(placement.get("edge_key", ""))
		if ek.is_empty():
			continue
		var parsed: Dictionary = _parse_edge_key(ek)
		if not bool(parsed.get("ok", false)):
			continue
		var connections: int = _count_perpendicular_connections(edge_map, parsed)
		var new_module: String = _wall_module_for_connections(connections, parsed, edge_map, placement)
		if new_module != WALL_MODULE:
			placement["module_id"] = new_module
			# Also update the edge_map record
			if edge_map.has(ek):
				edge_map[ek]["module_id"] = new_module


static func _parse_edge_key(ek: String) -> Dictionary:
	## Parse edge key into structured data.
	## Horizontal: "{deck}|h|{y}|{x}" — edge between rows y and y+1, at column x
	## Vertical:   "{deck}|v|{y}|{x}" — edge between columns x and x+1, at row y
	var parts: PackedStringArray = ek.split("|")
	if parts.size() < 4:
		return {"ok": false}
	var deck: int = int(parts[0])
	var axis: String = parts[1]
	var a: int = int(parts[2])
	var b: int = int(parts[3])
	if axis == "h":
		# Horizontal edge at grid point (b, a) to (b+1, a)
		return {"ok": true, "axis": "h", "deck": deck, "x": b, "y": a}
	elif axis == "v":
		# Vertical edge at grid point (b, a) to (b, a+1)
		return {"ok": true, "axis": "v", "deck": deck, "x": b, "y": a}
	return {"ok": false}


func _count_perpendicular_connections(edge_map: Dictionary, parsed: Dictionary) -> int:
	## Count how many SOLID perpendicular edges connect at the endpoints
	## of the given edge. Returns a bitmask:
	##   bit 0 (1): connection at endpoint A, side 1
	##   bit 1 (2): connection at endpoint A, side 2
	##   bit 2 (4): connection at endpoint B, side 1
	##   bit 3 (8): connection at endpoint B, side 2
	##
	## Edge key formats:
	##   Horizontal h|Y|X: boundary between rows Y and Y+1, at column X.
	##     Runs from grid-point (X, Y+1) to (X+1, Y+1).
	##     West endpoint (X, Y+1): perpendicular = v|Y|X-1 (north), v|Y+1|X-1 (south)
	##     East endpoint (X+1, Y+1): perpendicular = v|Y|X (north), v|Y+1|X (south)
	##   Vertical v|Y|X: east boundary of cell (X, Y).
	##     Runs from grid-point (X+1, Y) to (X+1, Y+1).
	##     North endpoint (X+1, Y): perpendicular = h|Y-1|X (west), h|Y-1|X+1 (east)
	##     South endpoint (X+1, Y+1): perpendicular = h|Y|X (west), h|Y|X+1 (east)
	var axis: String = parsed["axis"]
	var deck: int = parsed["deck"]
	var x: int = parsed["x"]
	var y: int = parsed["y"]
	var mask: int = 0

	if axis == "h":
		# West endpoint (x, y+1): vertical edges at x-1
		var vn_key: String = "%d|v|%d|%d" % [deck, y, x - 1]
		var vs_key: String = "%d|v|%d|%d" % [deck, y + 1, x - 1]
		if edge_map.has(vn_key) and str(edge_map[vn_key].get("kind", "")) == "SOLID":
			mask |= 1
		if edge_map.has(vs_key) and str(edge_map[vs_key].get("kind", "")) == "SOLID":
			mask |= 2
		# East endpoint (x+1, y+1): vertical edges at x
		var ven_key: String = "%d|v|%d|%d" % [deck, y, x]
		var ves_key: String = "%d|v|%d|%d" % [deck, y + 1, x]
		if edge_map.has(ven_key) and str(edge_map[ven_key].get("kind", "")) == "SOLID":
			mask |= 4
		if edge_map.has(ves_key) and str(edge_map[ves_key].get("kind", "")) == "SOLID":
			mask |= 8
	else:
		# North endpoint (x+1, y): horizontal edges at y-1
		var hw_key: String = "%d|h|%d|%d" % [deck, y - 1, x]
		var he_key: String = "%d|h|%d|%d" % [deck, y - 1, x + 1]
		if edge_map.has(hw_key) and str(edge_map[hw_key].get("kind", "")) == "SOLID":
			mask |= 1
		if edge_map.has(he_key) and str(edge_map[he_key].get("kind", "")) == "SOLID":
			mask |= 2
		# South endpoint (x+1, y+1): horizontal edges at y
		var hsw_key: String = "%d|h|%d|%d" % [deck, y, x]
		var hse_key: String = "%d|h|%d|%d" % [deck, y, x + 1]
		if edge_map.has(hsw_key) and str(edge_map[hsw_key].get("kind", "")) == "SOLID":
			mask |= 4
		if edge_map.has(hse_key) and str(edge_map[hse_key].get("kind", "")) == "SOLID":
			mask |= 8

	return mask


func _wall_module_for_connections(mask: int, parsed: Dictionary, edge_map: Dictionary, placement: Dictionary) -> String:
	## Select wall module based on connection bitmask.
	## mask bits: 0-1 = endpoint A connections, 2-3 = endpoint B connections
	## For horizontal edges: A=west, B=east; bits 0=north, 1=south
	## For vertical edges: A=north, B=south; bits 0=west, 1=east
	var count: int = 0
	for i in range(4):
		if mask & (1 << i):
			count += 1

	if count == 0:
		# Isolated wall — end cap
		return WALL_END_CAP_MODULE

	if count == 1:
		# One perpendicular connection at an endpoint — this is a corner
		# (two walls meeting at a room corner each have count=1)
		return _pick_corner_type(mask, parsed, edge_map, placement)

	# Check if connections are at same endpoint or different
	var a_connections: int = mask & 3   # bits 0-1 (endpoint A)
	var b_connections: int = mask & 12  # bits 2-3 (endpoint B)
	var a_count: int = 0
	var b_count: int = 0
	if a_connections & 1: a_count += 1
	if a_connections & 2: a_count += 1
	if b_connections & 4: b_count += 1
	if b_connections & 8: b_count += 1

	if count == 2:
		if a_count == 2 or b_count == 2:
			# Both connections at same endpoint — T-junction
			return WALL_T_JUNCTION_MODULE
		if a_count == 1 and b_count == 1:
			# Connections at different endpoints
			# Check if same side (straight) or different sides (corner)
			var axis: String = parsed["axis"]
			if axis == "h":
				# Horizontal: bit 0=north, bit 1=south at A; bit 4=north, bit 8=south at B
				var a_north: bool = (mask & 1) != 0
				var b_north: bool = (mask & 4) != 0
				if a_north == b_north:
					return WALL_MODULE  # straight — same side
				else:
					return _pick_corner_type(mask, parsed, edge_map, placement)
			else:
				# Vertical: bit 0=west, bit 1=east at A; bit 4=west, bit 8=east at B
				var a_west: bool = (mask & 1) != 0
				var b_west: bool = (mask & 4) != 0
				if a_west == b_west:
					return WALL_MODULE  # straight — same side
				else:
					return _pick_corner_type(mask, parsed, edge_map, placement)

	if count == 3:
		# Three connections — T-junction
		return WALL_T_JUNCTION_MODULE

	# Four connections — cross (no cross module, use T-junction as best fit)
	return WALL_T_JUNCTION_MODULE


func _pick_corner_type(mask: int, parsed: Dictionary, edge_map: Dictionary, placement: Dictionary) -> String:
	## Determine inner vs outer corner based on which side of the wall
	## the room interior is on. The owner_room side is the interior.
	## If the corner L opens toward the interior → inner corner
	## If the corner L opens away from the interior → outer corner
	var axis: String = parsed["axis"]
	var owner_room: String = str(placement.get("owner_room", ""))
	var other_room: String = str(placement.get("other_room", ""))

	# For simplicity: if the edge is exterior (no other room), use outer corner.
	# If it's between two rooms, use inner corner (the L opens into the owner room).
	if other_room.is_empty():
		return WALL_OUTER_CORNER_MODULE
	return WALL_INNER_CORNER_MODULE


func _index_portals(layout: Dictionary, room_by_id: Dictionary, room_by_cell: Dictionary, errors: Array[String]) -> Dictionary:
	var indexed: Dictionary = {}
	var emitted_edge_keys: Array = []
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
		var portal_kind: String = _portal_kind(portal, layout)
		var is_exterior_kind: bool = portal_kind == "BREACH" or portal_kind == "HATCH"

		# Door/Locked portals must declare both rooms.
		if not is_exterior_kind and (from_room.is_empty() or to_room.is_empty()):
			errors.append("portal endpoints are invalid: %s" % str(portal.get("id", "")))
			continue
		# Exterior BREACH/HATCH require from_room.
		if is_exterior_kind and from_room.is_empty():
			errors.append("portal endpoints are invalid: %s" % str(portal.get("id", "")))
			continue
		# Exterior BREACH/HATCH may have empty to_room but never point to a non-empty room.
		if is_exterior_kind and not to_room.is_empty():
			to_room = ""
		if not from_room.is_empty() and not room_by_id.has(from_room):
			errors.append("portal room endpoints are invalid: %s" % str(portal.get("id", "")))
			continue
		if not to_room.is_empty() and not room_by_id.has(to_room):
			errors.append("portal room endpoints are invalid: %s" % str(portal.get("id", "")))
			continue
		if not from_room.is_empty() and not to_room.is_empty() and from_room == to_room:
			errors.append("portal room endpoints are invalid: %s" % str(portal.get("id", "")))
			continue

		var from_deck: int = int(room_by_id[from_room].get("deck", -1)) if not from_room.is_empty() else 0
		var to_deck: int = int(room_by_id[to_room].get("deck", -1)) if not to_room.is_empty() else from_deck

		# Resolve edge geometry. Either the portal has an explicit edge_key,
		# or we derive one from from_cell/to_cell adjacency (legacy schema).
		var explicit_edge_key: String = str(portal.get("edge_key", ""))
		var direction: String = ""
		var edge_cell: Vector2i = Vector2i.ZERO
		var from_cell: Vector2i = Vector2i.ZERO
		var to_cell: Vector2i = Vector2i.ZERO
		var from_key: String = ""
		var to_key: String = ""
		var logical_boundary: bool = false

		if not explicit_edge_key.is_empty():
			# Validate declared edge_key resolves to a direction in the deck.
			var parsed: Dictionary = _parse_edge_key(explicit_edge_key)
			if not bool(parsed.get("ok", false)) or int(parsed.get("deck", -1)) != from_deck:
				errors.append("portal endpoints are malformed: %s" % str(portal.get("id", "")))
				continue
			# Identify which cell the from_room owns that touches the edge.
			var resolved_cell: Dictionary = _cell_for_edge_in_room(from_room, room_by_cell, from_deck, parsed)
			if bool(resolved_cell.get("ok", false)):
				edge_cell = resolved_cell["cell"]
				direction = str(resolved_cell["direction"])
				# For doors/locks, derive neighbor cell from direction.
				var delta: Vector2i = DIRECTIONS[direction]
				var neighbor_cell: Vector2i = edge_cell + delta
				to_cell = neighbor_cell
				from_cell = edge_cell
				from_key = cell_key(from_deck, from_cell)
				to_key = cell_key(from_deck, to_cell)
				# Determine to_room from occupancy when missing (interior).
				if to_room.is_empty() and not is_exterior_kind:
					var inferred: String = str(room_by_cell.get(to_key, ""))
					if not inferred.is_empty() and inferred != from_room:
						to_room = inferred
					elif is_exterior_kind:
						pass
					else:
						errors.append("portal endpoints are invalid: %s" % str(portal.get("id", "")))
						continue
				# Skip the legacy adjacency path; fall through to key/index.
			else:
				# Fallback: trust the legacy from_cell/to_cell fields and
				# derive the canonical edge_key from them. This keeps the
				# compiler honest with portals produced by older layout code
				# whose from_room doesn't strictly border the declared edge.
				var from_info: Dictionary = _read_cell(portal.get("from_cell", null), from_deck)
				var to_info: Dictionary = _read_cell(portal.get("to_cell", null), to_deck)
				if bool(from_info.get("ok", false)) and bool(to_info.get("ok", false)) and int(from_info["deck"]) == from_deck and int(to_info["deck"]) == from_deck:
					from_cell = from_info["cell"]
					to_cell = to_info["cell"]
					direction = _direction_between(from_cell, to_cell)
					if not direction.is_empty():
						edge_cell = from_cell
						from_key = cell_key(from_deck, from_cell)
						to_key = cell_key(from_deck, to_cell)
						if not to_room.is_empty() and str(room_by_cell.get(to_key, "")) != to_room:
							errors.append("portal endpoints are not owned by declared rooms: %s" % str(portal.get("id", "")))
							continue
					else:
						errors.append("portal endpoints are malformed: %s" % str(portal.get("id", "")))
						continue
				else:
					errors.append("portal endpoints are malformed: %s" % str(portal.get("id", "")))
					continue
		else:
			# Legacy path: portal declares from_cell/to_cell adjacency.
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
			from_cell = from_info["cell"]
			to_cell = to_info["cell"]
			from_key = cell_key(from_deck, from_cell)
			to_key = cell_key(to_deck, to_cell)
			if str(room_by_cell.get(from_key, "")) != from_room or (not to_room.is_empty() and str(room_by_cell.get(to_key, "")) != to_room):
				errors.append("portal endpoints are not owned by declared rooms: %s" % str(portal.get("id", "")))
				continue
			direction = _direction_between(from_cell, to_cell)
			edge_cell = from_cell
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
		indexed_portal["portal_kind"] = portal_kind
		indexed[key] = indexed_portal
		emitted_edge_keys.append(key)
	return indexed


# Resolve the integer (cell, direction) pair for an explicit edge_key whose
# endpoint owner is `room_id`. Returns ok=false if the room does not border
# the edge or the edge is mis-oriented for the canonical scheme.
func _cell_for_edge_in_room(room_id: String, room_by_cell: Dictionary, deck: int, parsed: Dictionary) -> Dictionary:
	var x: int = int(parsed.get("x", -1))
	var y: int = int(parsed.get("y", -1))
	if x < 0 or y < 0:
		return {"ok": false}
	var direction: String = ""
	var primary: Vector2i = Vector2i.ZERO
	var secondary: Vector2i = Vector2i.ZERO
	if parsed.get("axis", "") == "h":
		# Horizontal edge sits between rows y and y+1 at column x.
		var cell_high: Vector2i = Vector2i(x, y + 1)
		var cell_low: Vector2i = Vector2i(x, y)
		var has_high: bool = str(room_by_cell.get(cell_key(deck, cell_high), "")) == room_id
		var has_low: bool = str(room_by_cell.get(cell_key(deck, cell_low), "")) == room_id
		if has_high and has_low:
			return {"ok": false}
		if has_high:
			primary = cell_high
			secondary = cell_low
			direction = "north"
		elif has_low:
			primary = cell_low
			secondary = cell_high
			direction = "south"
		else:
			return {"ok": false}
	else:
		# Vertical edge sits between columns x and x+1 at row y.
		var cell_high: Vector2i = Vector2i(x + 1, y)
		var cell_low: Vector2i = Vector2i(x, y)
		var has_high: bool = str(room_by_cell.get(cell_key(deck, cell_high), "")) == room_id
		var has_low: bool = str(room_by_cell.get(cell_key(deck, cell_low), "")) == room_id
		if has_high and has_low:
			return {"ok": false}
		if has_high:
			primary = cell_high
			secondary = cell_low
			direction = "west"
		elif has_low:
			primary = cell_low
			secondary = cell_high
			direction = "east"
		else:
			return {"ok": false}
	return {"ok": true, "cell": primary, "direction": direction, "secondary": secondary}


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
