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

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const FLOOR_MODULE: String = "floor_1x1"
const CORRIDOR_FLOOR_MODULE: String = "corridor_floor_1x1"
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
			if not edge_other_room.is_empty() and edge_other_room == room_id and not portal_present:
				edge_state = "OPEN"
				module_id = ""
				wrapper_required = false
			elif portal_present:
				edge_state = _portal_kind(portal, layout)
				module_id = _portal_module_from_catalog(catalog, portal, edge_state)
				wrapper_required = edge_state != "BREACH" or not module_id.is_empty()
				if edge_other_room.is_empty() and not bool(portal.get("exterior", false)):
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
				"placement_required": wrapper_required,
				"wrapper_required": wrapper_required,
			}
			if portal_present:
				edge_record["portal_id"] = str(portal.get("id", ""))
				var logical_boundary: bool = bool(portal.get("logical_boundary", false))
				edge_record["logical_boundary"] = logical_boundary
				if logical_boundary:
					edge_record["logical_from_cell"] = portal.get("logical_from_cell", portal.get("from_cell", null))
					edge_record["logical_to_cell"] = portal.get("logical_to_cell", portal.get("to_cell", null))
			edge_map[edge_key_value] = edge_record

	edge_placements = _emit_half_span_edge_placements(
		occupancy, edge_map, catalog, inner_corner_module,
		outer_corner_module, t_junction_module, wall_module, errors)
	var dock_navigation_nodes: Array = _compile_dock_navigation_nodes(
		layout, edge_map, edge_placements, floor_placements, errors)

	var socket_bindings: Array = _emit_socket_bindings(
		catalog,
		floor_placements,
		ceiling_placements,
		edge_placements
	)
	_attach_bindings_to_records(floor_placements, socket_bindings)
	_attach_bindings_to_records(ceiling_placements, socket_bindings)
	_attach_bindings_to_records(edge_placements, socket_bindings)

	return {
		"occupancy": occupancy,
		"edges": edge_map,
		"placements": edge_placements,
		"floor_placements": floor_placements,
		"ceiling_placements": ceiling_placements,
		"socket_bindings": socket_bindings,
		"dock_navigation_nodes": dock_navigation_nodes,
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
		"ceiling_placements": [],
		"socket_bindings": [],
		"dock_navigation_nodes": [],
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
		var scale_a: Vector3 = _as_vector3(record_a.get("scale", Vector3.ONE))
		for j in range(i + 1, all_records.size()):
			if typeof(all_records[j]) != TYPE_DICTIONARY:
				continue
			var record_b: Dictionary = all_records[j]
			var module_b: String = str(record_b.get("module_id", ""))
			var pos_b: Vector3 = _as_vector3(record_b.get("position", Vector3.ZERO))
			var yaw_b: float = float(record_b.get("yaw_degrees", 0.0))
			var scale_b: Vector3 = _as_vector3(record_b.get("scale", Vector3.ONE))
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
					var world_a: Vector3 = catalog.world_socket_position(
						pos_a, yaw_a, catalog.socket_local_position(socket_a), scale_a)
					var world_b: Vector3 = catalog.world_socket_position(
						pos_b, yaw_b, catalog.socket_local_position(socket_b), scale_b)
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


func _emit_half_span_edge_placements(
		occupancy: Dictionary,
		edge_map: Dictionary,
		catalog,
		inner_corner_module: String,
		outer_corner_module: String,
		t_junction_module: String,
		wall_module: String,
		errors: Array[String]) -> Array:
	## Every SOLID 4 m edge owns two canonical 2 m spans. A vertex wrapper may
	## claim the incident span from two or three edges only when its materialized
	## collision projection maps exactly to those rays. Residual spans use scaled
	## straight walls; no search or label-only substitution participates.
	var placements: Array = []
	var claimed_spans: Dictionary = {}
	var vertices: Dictionary = {}
	var edge_keys: Array = edge_map.keys()
	edge_keys.sort()
	for edge_key_variant in edge_keys:
		var edge_key_value: String = str(edge_key_variant)
		var edge: Dictionary = edge_map[edge_key_variant]
		if str(edge.get("kind", "")) == "SOLID":
			var vertex_keys: Array[String] = _edge_vertex_keys(edge_key_value)
			if vertex_keys.size() != 2:
				errors.append("solid edge has malformed canonical vertices: %s" % edge_key_value)
				continue
			var half_span_ids: Array[String] = [
				_half_span_id(edge_key_value, 0),
				_half_span_id(edge_key_value, 1),
			]
			edge["vertex_keys"] = vertex_keys.duplicate()
			edge["half_span_ids"] = half_span_ids.duplicate()
			edge["half_span_placement_ids"] = {}
			edge["placement_ids"] = []
			for vertex_key in vertex_keys:
				vertices[vertex_key] = true
		elif str(edge.get("kind", "")) != "OPEN" \
				and bool(edge.get("wrapper_required", true)):
			var placement: Dictionary = edge.duplicate(true)
			var placement_id: String = "edge:%s" % edge_key_value
			placement["id"] = placement_id
			placement["placement_id"] = placement_id
			placement["anchor_kind"] = "edge"
			placement["edge_keys"] = [edge_key_value]
			placement["covered_half_spans"] = []
			placement["scale"] = Vector3.ONE
			placements.append(placement)
			edge["placement_ids"] = [placement_id]

	var vertex_keys: Array = vertices.keys()
	vertex_keys.sort()
	for vertex_key_variant in vertex_keys:
		var vertex_key: String = str(vertex_key_variant)
		var vertex: Dictionary = _parse_vertex_key(vertex_key)
		if not bool(vertex.get("ok", false)):
			errors.append("solid edge has malformed vertex authority: %s" % vertex_key)
			continue
		var deck: int = int(vertex["deck"])
		var vx: int = int(vertex["x"])
		var vz: int = int(vertex["z"])
		var incident: Dictionary = _incident_solid_rays(edge_map, deck, vx, vz)
		var directions: Array[String] = []
		for direction in CARDINALS:
			if incident.has(direction):
				directions.append(direction)
		var occupied_count: int = _vertex_occupied_count(occupancy, deck, vx, vz)
		var module_id: String = ""
		if directions.size() == 3 and catalog.has_module(t_junction_module):
			module_id = t_junction_module
		elif directions.size() == 2 and _directions_perpendicular(directions):
			if occupied_count == 3 and catalog.has_module(inner_corner_module):
				module_id = inner_corner_module
			elif occupied_count == 1 and catalog.has_module(outer_corner_module):
				module_id = outer_corner_module
		if module_id.is_empty():
			continue
		var yaw_degrees: float = _matching_vertex_module_yaw(
			catalog, module_id, directions)
		if yaw_degrees < 0.0:
			errors.append("vertex module projection does not match incident spans: %s module=%s" % [
				vertex_key, module_id])
			continue
		var incident_edge_keys: Array[String] = []
		var span_ids: Array[String] = []
		for direction in directions:
			var incident_edge_key: String = str(incident[direction])
			var endpoint_index: int = _edge_vertex_keys(incident_edge_key).find(vertex_key)
			if endpoint_index < 0:
				errors.append("incident span endpoint mismatch: %s" % incident_edge_key)
				continue
			var span_id: String = _half_span_id(incident_edge_key, endpoint_index)
			if claimed_spans.has(span_id):
				errors.append("duplicate half-span claim: %s" % span_id)
				continue
			incident_edge_keys.append(incident_edge_key)
			span_ids.append(span_id)
		if span_ids.size() != directions.size():
			continue
		incident_edge_keys.sort()
		span_ids.sort()
		var primary_edge_key: String = incident_edge_keys[0]
		var primary: Dictionary = edge_map[primary_edge_key]
		var vertex_placement_id: String = "vertex:%s" % vertex_key
		var vertex_placement: Dictionary = primary.duplicate(true)
		vertex_placement["id"] = vertex_placement_id
		vertex_placement["placement_id"] = vertex_placement_id
		vertex_placement["module_id"] = module_id
		vertex_placement["position"] = _vertex_world_position(deck, vx, vz)
		vertex_placement["yaw_degrees"] = yaw_degrees
		vertex_placement["scale"] = Vector3.ONE
		vertex_placement["anchor_kind"] = "vertex"
		vertex_placement["anchor_vertex"] = [vx, vz, deck]
		vertex_placement["edge_key"] = primary_edge_key
		vertex_placement["edge_keys"] = incident_edge_keys.duplicate()
		vertex_placement["covered_half_spans"] = span_ids.duplicate()
		vertex_placement["room_ids"] = _placement_room_ids(edge_map, incident_edge_keys)
		placements.append(vertex_placement)
		for span_id in span_ids:
			claimed_spans[span_id] = vertex_placement_id
			var span_edge_key: String = span_id.get_slice("@", 0)
			var span_edge: Dictionary = edge_map[span_edge_key]
			(span_edge["half_span_placement_ids"] as Dictionary)[span_id] = vertex_placement_id
			if not (span_edge["placement_ids"] as Array).has(vertex_placement_id):
				(span_edge["placement_ids"] as Array).append(vertex_placement_id)

	for edge_key_variant in edge_keys:
		var edge_key_value: String = str(edge_key_variant)
		var edge: Dictionary = edge_map[edge_key_variant]
		if str(edge.get("kind", "")) != "SOLID":
			continue
		var edge_vertices: Array[String] = edge.get("vertex_keys", []) as Array[String]
		if edge_vertices.size() != 2:
			continue
		var residual_indices: Array[int] = []
		for endpoint_index in range(2):
			if not claimed_spans.has(_half_span_id(edge_key_value, endpoint_index)):
				residual_indices.append(endpoint_index)
		if residual_indices.is_empty():
			continue
		var residual: Dictionary = edge.duplicate(true)
		var residual_spans: Array[String] = []
		for endpoint_index in residual_indices:
			residual_spans.append(_half_span_id(edge_key_value, endpoint_index))
		var residual_id: String = "edge:%s" % edge_key_value
		if residual_indices.size() == 1:
			var endpoint_index: int = residual_indices[0]
			residual_id = "span:%s" % residual_spans[0]
			var vertex: Dictionary = _parse_vertex_key(edge_vertices[endpoint_index])
			var vertex_position: Vector3 = _vertex_world_position(
				int(vertex["deck"]), int(vertex["x"]), int(vertex["z"]))
			residual["position"] = vertex_position.lerp(
				_as_vector3(edge.get("position", Vector3.ZERO)), 0.5)
			residual["scale"] = Vector3(0.5, 1.0, 1.0)
			residual["anchor_kind"] = "half_span"
			residual["anchor_vertex"] = [int(vertex["x"]), int(vertex["z"]), int(vertex["deck"])]
		else:
			residual["scale"] = Vector3.ONE
			residual["anchor_kind"] = "edge"
		residual["id"] = residual_id
		residual["placement_id"] = residual_id
		residual["module_id"] = wall_module
		residual["edge_keys"] = [edge_key_value]
		residual["covered_half_spans"] = residual_spans.duplicate()
		placements.append(residual)
		for span_id in residual_spans:
			claimed_spans[span_id] = residual_id
			(edge["half_span_placement_ids"] as Dictionary)[span_id] = residual_id
		if not (edge["placement_ids"] as Array).has(residual_id):
			(edge["placement_ids"] as Array).append(residual_id)

	for edge_key_variant in edge_keys:
		var edge: Dictionary = edge_map[edge_key_variant]
		if str(edge.get("kind", "")) != "SOLID":
			continue
		for span_id_variant in edge.get("half_span_ids", []):
			var span_id: String = str(span_id_variant)
			if not claimed_spans.has(span_id):
				errors.append("solid edge half-span has no placement: %s" % span_id)
		(edge["placement_ids"] as Array).sort()
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("placement_id", "")) < str(b.get("placement_id", "")))
	return placements


func _half_span_id(edge_key_value: String, endpoint_index: int) -> String:
	return "%s@%s" % [edge_key_value, "a" if endpoint_index == 0 else "b"]


func _parse_vertex_key(vertex_key: String) -> Dictionary:
	var parts: PackedStringArray = vertex_key.split("|")
	if parts.size() != 3 or not parts[0].is_valid_int() \
			or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {"ok": false}
	return {"ok": true, "deck": int(parts[0]), "x": int(parts[1]), "z": int(parts[2])}


func _vertex_world_position(deck: int, vx: int, vz: int) -> Vector3:
	return Vector3(float(vx) * CELL_SIZE - CELL_SIZE * 0.5,
		float(deck) * DECK_HEIGHT, float(vz) * CELL_SIZE - CELL_SIZE * 0.5)


func _edge_key_for_vertex_ray(deck: int, vx: int, vz: int, direction: String) -> String:
	match direction:
		"north":
			return "%d|v|%d|%d" % [deck, vz - 1, vx - 1]
		"east":
			return "%d|h|%d|%d" % [deck, vz - 1, vx]
		"south":
			return "%d|v|%d|%d" % [deck, vz, vx - 1]
		"west":
			return "%d|h|%d|%d" % [deck, vz - 1, vx - 1]
	return ""


func _incident_solid_rays(edge_map: Dictionary, deck: int, vx: int, vz: int) -> Dictionary:
	var incident: Dictionary = {}
	for direction in CARDINALS:
		var edge_key_value: String = _edge_key_for_vertex_ray(deck, vx, vz, direction)
		var edge_variant: Variant = edge_map.get(edge_key_value, null)
		if edge_variant is Dictionary and str((edge_variant as Dictionary).get("kind", "")) == "SOLID":
			incident[direction] = edge_key_value
	return incident


func _vertex_occupied_count(occupancy: Dictionary, deck: int, vx: int, vz: int) -> int:
	var count: int = 0
	for cell in [Vector2i(vx - 1, vz - 1), Vector2i(vx, vz - 1),
			Vector2i(vx - 1, vz), Vector2i(vx, vz)]:
		if occupancy.has(cell_key(deck, cell)):
			count += 1
	return count


func _directions_perpendicular(directions: Array[String]) -> bool:
	if directions.size() != 2:
		return false
	var first: int = CARDINALS.find(directions[0])
	var second: int = CARDINALS.find(directions[1])
	return first >= 0 and second >= 0 and posmod(first - second, 2) == 1


func _matching_vertex_module_yaw(catalog, module_id: String, desired: Array[String]) -> float:
	var canonical: Array[String] = _projected_module_ray_directions(
		catalog.collision_boxes_of(module_id))
	if canonical.size() != desired.size():
		return -1.0
	for quarter_turns in range(4):
		var rotated: Array[String] = []
		for direction in canonical:
			var direction_index: int = CARDINALS.find(direction)
			if direction_index < 0:
				return -1.0
			rotated.append(CARDINALS[posmod(direction_index - quarter_turns, 4)])
		var matches: bool = true
		for direction in desired:
			matches = matches and rotated.has(direction)
		if matches:
			return float(quarter_turns * 90)
	return -1.0


func _projected_module_ray_directions(boxes: Array) -> Array[String]:
	var directions: Array[String] = []
	for box_variant in boxes:
		if not box_variant is Dictionary:
			return []
		var box: Dictionary = box_variant
		var basis_values_variant: Variant = box.get("basis", null)
		var dimensions_variant: Variant = box.get("dimensions", null)
		if not basis_values_variant is Array or (basis_values_variant as Array).size() != 9 \
				or not dimensions_variant is Array or (dimensions_variant as Array).size() != 3:
			return []
		var basis_values: Array = basis_values_variant
		var dimensions: Vector3 = _as_vector3(dimensions_variant)
		var origin: Vector3 = _as_vector3(box.get("origin", []))
		var basis := Basis(
			Vector3(float(basis_values[0]), float(basis_values[1]), float(basis_values[2])),
			Vector3(float(basis_values[3]), float(basis_values[4]), float(basis_values[5])),
			Vector3(float(basis_values[6]), float(basis_values[7]), float(basis_values[8])))
		if not basis.is_finite() or not dimensions.is_finite() or not origin.is_finite():
			return []
		var projected := AABB(origin, Vector3.ZERO)
		var first: bool = true
		for x_sign in [-0.5, 0.5]:
			for y_sign in [-0.5, 0.5]:
				for z_sign in [-0.5, 0.5]:
					var point: Vector3 = origin + basis * Vector3(
						dimensions.x * x_sign, dimensions.y * y_sign,
						dimensions.z * z_sign)
					if first:
						projected = AABB(point, Vector3.ZERO)
						first = false
					else:
						projected = projected.expand(point)
		if not is_equal_approx(projected.position.y, 0.0) \
				or not is_equal_approx(projected.end.y, 3.0):
			return []
		var direction: String = ""
		if is_equal_approx(projected.size.x, 2.0) and is_equal_approx(projected.size.z, 0.2):
			if is_equal_approx(projected.position.x, 0.0) and is_equal_approx(projected.end.x, 2.0):
				direction = "east"
			elif is_equal_approx(projected.position.x, -2.0) and is_equal_approx(projected.end.x, 0.0):
				direction = "west"
		elif is_equal_approx(projected.size.z, 2.0) and is_equal_approx(projected.size.x, 0.2):
			if is_equal_approx(projected.position.z, -2.0) and is_equal_approx(projected.end.z, 0.0):
				direction = "north"
			elif is_equal_approx(projected.position.z, 0.0) and is_equal_approx(projected.end.z, 2.0):
				direction = "south"
		if direction.is_empty() or directions.has(direction):
			return []
		directions.append(direction)
	return directions


func _placement_room_ids(edge_map: Dictionary, incident_edge_keys: Array[String]) -> Array:
	var room_ids: Array = []
	for edge_key_value in incident_edge_keys:
		var edge: Dictionary = edge_map[edge_key_value]
		for room_id_variant in edge.get("room_ids", []):
			var room_id: String = str(room_id_variant)
			if not room_id.is_empty() and not room_ids.has(room_id):
				room_ids.append(room_id)
	room_ids.sort()
	return room_ids


func _edge_vertex_keys(edge_key_value: String) -> Array[String]:
	var parsed: Dictionary = _parse_edge_key(edge_key_value)
	if not bool(parsed.get("ok", false)):
		return []
	var deck: int = int(parsed.get("deck", 0))
	var axis: String = str(parsed.get("axis", ""))
	var x: int = int(parsed.get("x", 0))
	var y: int = int(parsed.get("y", 0))
	if axis == "h":
		return ["%d|%d|%d" % [deck, x, y + 1],
			"%d|%d|%d" % [deck, x + 1, y + 1]]
	return ["%d|%d|%d" % [deck, x + 1, y],
		"%d|%d|%d" % [deck, x + 1, y + 1]]


func _parse_edge_key(ek: String) -> Dictionary:
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
		if bool(portal.get("exterior", false)):
			_index_exterior_portal(portal, from_room, to_room, room_by_id,
				room_by_cell, indexed, errors)
			continue
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


func _index_exterior_portal(
		portal: Dictionary, from_room: String, to_room: String,
		room_by_id: Dictionary, room_by_cell: Dictionary,
		indexed: Dictionary, errors: Array[String]) -> void:
	var portal_id: String = str(portal.get("id", ""))
	if portal_id.is_empty() or not room_by_id.has(from_room) or not to_room.is_empty():
		errors.append("exterior portal endpoints are invalid: %s" % portal_id)
		return
	var from_deck: int = int((room_by_id[from_room] as Dictionary).get("deck", -1))
	var from_info: Dictionary = _read_cell(portal.get("from_cell", null), from_deck)
	var to_info: Dictionary = _read_cell(portal.get("to_cell", null), from_deck)
	if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)) \
			or int(from_info.get("deck", -1)) != from_deck \
			or int(to_info.get("deck", -1)) != from_deck:
		errors.append("exterior portal cells are malformed: %s" % portal_id)
		return
	var from_cell: Vector2i = from_info["cell"]
	var to_cell: Vector2i = to_info["cell"]
	var from_key: String = cell_key(from_deck, from_cell)
	var to_key: String = cell_key(from_deck, to_cell)
	if str(room_by_cell.get(from_key, "")) != from_room or room_by_cell.has(to_key):
		errors.append("exterior portal cells are not owner/interior-to-empty: %s" % portal_id)
		return
	var direction: String = _direction_between(from_cell, to_cell)
	if direction.is_empty() or str(portal.get("edge_direction", direction)) != direction:
		errors.append("exterior portal cells are not cardinally adjacent: %s" % portal_id)
		return
	var key: String = edge_key(from_deck, from_cell, direction)
	if indexed.has(key):
		errors.append("duplicate portal edge: %s" % key)
		return
	var indexed_portal: Dictionary = portal.duplicate(true)
	indexed_portal["edge_key"] = key
	indexed_portal["direction"] = direction
	indexed_portal["edge_cell"] = from_cell
	indexed_portal["edge_other_room"] = ""
	indexed_portal["logical_boundary"] = false
	indexed_portal["from_cell_key"] = from_key
	indexed_portal["to_cell_key"] = to_key
	indexed[key] = indexed_portal


func _compile_dock_navigation_nodes(
		layout: Dictionary, edges: Dictionary, placements: Array,
		floors: Array, errors: Array[String]) -> Array:
	var source_variant: Variant = layout.get("dock_navigation_nodes_v1", [])
	if not source_variant is Array:
		errors.append("dock_navigation_nodes_v1 must be an array")
		return []
	var source: Array = source_variant
	var exterior_edges: Array[Dictionary] = []
	for edge_variant in edges.values():
		if edge_variant is Dictionary and bool((edge_variant as Dictionary).get(
				"exterior", false)) and bool((edge_variant as Dictionary).get(
				"portal", false)):
			exterior_edges.append(edge_variant as Dictionary)
	if exterior_edges.is_empty() and source.is_empty():
		return []
	if exterior_edges.size() != 1 or source.size() != 2:
		errors.append("exterior portal requires exactly two dock navigation nodes")
		return []
	var edge: Dictionary = exterior_edges[0]
	var edge_key_value: String = str(edge.get("edge_key", ""))
	var cell: Vector2i = edge.get("cell", Vector2i.ZERO) as Vector2i
	var deck: int = int(edge.get("deck", -1))
	var expected_placement_by_kind: Dictionary = {
		"threshold": "edge:%s" % edge_key_value,
		"interior": "floor:%s" % cell_key(deck, cell),
	}
	var placement_ids: Dictionary = {}
	for placement_variant in placements + floors:
		if placement_variant is Dictionary:
			placement_ids[str((placement_variant as Dictionary).get(
				"placement_id", ""))] = true
	var seen_kinds: Dictionary = {}
	var seen_ids: Dictionary = {}
	var compiled: Array = []
	var expected_keys: Array = ["node_id", "kind", "portal_id", "room_id",
		"deck", "cell", "structural_placement_id", "local_position"]
	for node_variant in source:
		if not node_variant is Dictionary:
			errors.append("dock navigation node must be an object")
			continue
		var node: Dictionary = node_variant
		var fields_valid: bool = node.size() == expected_keys.size()
		for field in expected_keys:
			fields_valid = fields_valid and node.has(field)
		var node_id: String = str(node.get("node_id", ""))
		var kind: String = str(node.get("kind", ""))
		var placement_id: String = str(node.get("structural_placement_id", ""))
		var position: Dictionary = _read_position(node.get("local_position", null))
		var node_cell: Dictionary = _read_cell(node.get("cell", null), deck)
		if not fields_valid or node_id.is_empty() or seen_ids.has(node_id) \
				or seen_kinds.has(kind) or not expected_placement_by_kind.has(kind) \
				or placement_id != str(expected_placement_by_kind[kind]) \
				or not placement_ids.has(placement_id) \
				or str(node.get("portal_id", "")) != str(edge.get("portal_id", "")) \
				or str(node.get("room_id", "")) != str(edge.get("owner_room", "")) \
				or int(node.get("deck", -1)) != deck \
				or not bool(node_cell.get("ok", false)) \
				or node_cell.get("cell", Vector2i(-99999, -99999)) != cell \
				or not bool(position.get("ok", false)) \
				or not (position.get("value", Vector3.INF) as Vector3).is_finite():
			errors.append("dock navigation node authority mismatch: %s" % node_id)
			continue
		seen_ids[node_id] = true
		seen_kinds[kind] = true
		compiled.append(node.duplicate(true))
	if seen_kinds.size() != 2:
		errors.append("dock navigation node kinds are incomplete")
	compiled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("kind", "")) > str(b.get("kind", "")))
	return compiled


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


func _read_position(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_VECTOR3:
		return {"ok": true, "value": value}
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false}
	var values: Array = value
	if values.size() != 3 or not _is_number(values[0]) \
			or not _is_number(values[1]) or not _is_number(values[2]):
		return {"ok": false}
	return {"ok": true, "value": Vector3(
		float(values[0]), float(values[1]), float(values[2]))}


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


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
