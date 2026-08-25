extends RefCounted
class_name StructuralPlanValidator

## Fail-closed validator for compiler-produced structural plans.
## Edge placements and floor placements are intentionally separate contracts:
## floors identify occupied cells; edge records identify canonical boundaries.

const CompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const CEILING_MODULES: Array[String] = ["ceiling_cap_1x1"]
const EDGE_KINDS: Array[String] = ["SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"]


func validate(plan: Dictionary, topology: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var stats: Dictionary = {
		"occupied_cells": 0,
		"floor_placements": 0,
		"ceiling_placements": 0,
		"socket_bindings": 0,
		"edges": 0,
		"edge_placements": 0,
	}
	if plan.is_empty():
		errors.append("structural plan must be a non-empty object")
		return _verdict(errors, stats)

	var compiler_errors_variant: Variant = plan.get("errors", null)
	if typeof(compiler_errors_variant) != TYPE_ARRAY:
		errors.append("structural plan errors must be an array")
	elif not (compiler_errors_variant as Array).is_empty():
		for compiler_error in (compiler_errors_variant as Array):
			errors.append("compiler error: %s" % str(compiler_error))

	var occupancy_variant: Variant = plan.get("occupancy", null)
	if typeof(occupancy_variant) != TYPE_DICTIONARY:
		errors.append("occupancy must be a dictionary")
		return _verdict(errors, stats)
	var occupancy: Dictionary = occupancy_variant
	stats["occupied_cells"] = occupancy.size()
	if occupancy.is_empty():
		errors.append("occupancy must be non-empty")

	var edges_variant: Variant = plan.get("edges", null)
	if typeof(edges_variant) != TYPE_DICTIONARY:
		errors.append("edges must be a dictionary")
	var edges: Dictionary = edges_variant if typeof(edges_variant) == TYPE_DICTIONARY else {}
	stats["edges"] = edges.size()

	var placements_variant: Variant = plan.get("placements", null)
	if typeof(placements_variant) != TYPE_ARRAY:
		errors.append("placements must be an array")
	var placements: Array = placements_variant if typeof(placements_variant) == TYPE_ARRAY else []
	stats["edge_placements"] = placements.size()

	_validate_occupancy_records(occupancy, errors)
	_validate_floor_placements(plan, occupancy, topology, errors, stats)
	_validate_ceiling_placements(plan, occupancy, topology, errors, stats)
	_validate_socket_bindings(plan, errors, stats)
	_validate_not_floor_only(plan, occupancy, errors)
	_validate_edge_placements(edges, placements, errors)
	_validate_portal_endpoints(topology, occupancy, edges, errors)
	_validate_walkable_flood_fill(topology, occupancy, edges, errors)

	return _verdict(errors, stats)


func _verdict(errors: Array[String], stats: Dictionary) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"stats": stats,
	}


func _validate_occupancy_records(occupancy: Dictionary, errors: Array[String]) -> void:
	for occupancy_key_variant in occupancy.keys():
		var occupancy_key: String = str(occupancy_key_variant)
		var record_variant: Variant = occupancy[occupancy_key_variant]
		if typeof(record_variant) != TYPE_DICTIONARY:
			errors.append("occupancy record must be an object: %s" % occupancy_key)
			continue
		var record: Dictionary = record_variant
		var parsed_cell: Dictionary = _read_cell(record.get("cell", null), int(record.get("deck", -1)))
		if not bool(parsed_cell.get("ok", false)):
			errors.append("occupancy cell is malformed: %s" % occupancy_key)
			continue
		var deck: int = int(parsed_cell["deck"])
		var cell: Vector2i = parsed_cell["cell"]
		if not _is_integer(record.get("deck", null)) or int(record.get("deck")) != deck:
			errors.append("occupancy deck mismatch: %s" % occupancy_key)
		if str(record.get("cell_key", occupancy_key)) != occupancy_key:
			errors.append("occupancy cell_key mismatch: %s" % occupancy_key)
		if CompilerScript.cell_key(deck, cell) != occupancy_key:
			errors.append("occupancy canonical key mismatch: %s" % occupancy_key)
		if str(record.get("room_id", "")).is_empty():
			errors.append("occupancy room_id missing: %s" % occupancy_key)


func _validate_floor_placements(
		plan: Dictionary,
		occupancy: Dictionary,
		topology: Dictionary,
		errors: Array[String],
		stats: Dictionary) -> void:
	var floor_variant: Variant = plan.get("floor_placements", null)
	if typeof(floor_variant) != TYPE_ARRAY:
		errors.append("floor_placements must be a non-empty array")
		return
	var floors: Array = floor_variant
	stats["floor_placements"] = floors.size()
	if floors.is_empty():
		errors.append("floor_placements must be non-empty")
		return

	var seen_cell_keys: Dictionary = {}
	# The floor contract is exactly one record for each occupied cell.
	var room_decks: Dictionary = _room_decks(topology)
	for floor_record_variant in floors:
		if typeof(floor_record_variant) != TYPE_DICTIONARY:
			errors.append("floor placement must be an object")
			continue
		var floor: Dictionary = floor_record_variant
		var cell_key_value: String = str(floor.get("cell_key", ""))
		if cell_key_value.is_empty():
			errors.append("floor placement cell_key missing")
			continue
		if seen_cell_keys.has(cell_key_value):
			errors.append("duplicate floor placement cell_key: %s" % cell_key_value)
			continue
		seen_cell_keys[cell_key_value] = true
		if floor.has("edge_key") and not str(floor.get("edge_key", "")).is_empty():
			errors.append("floor placement must not declare edge_key: %s" % cell_key_value)
		var room_id: String = str(floor.get("room_id", ""))
		if room_id.is_empty():
			errors.append("floor placement room_id missing: %s" % cell_key_value)
		elif not room_decks.has(room_id):
			errors.append("floor placement room unknown: %s" % room_id)
		var deck_value: Variant = floor.get("deck", null)
		if not _is_integer(deck_value):
			errors.append("floor placement deck malformed: %s" % cell_key_value)
			continue
		var deck: int = int(deck_value)
		var parsed_cell: Dictionary = _read_cell(floor.get("cell", null), deck)
		if not bool(parsed_cell.get("ok", false)):
			errors.append("floor placement cell malformed: %s" % cell_key_value)
			continue
		var cell: Vector2i = parsed_cell["cell"]
		if int(parsed_cell["deck"]) != deck:
			errors.append("floor placement deck/cell mismatch: %s" % cell_key_value)
		var expected_key: String = CompilerScript.cell_key(deck, cell)
		if expected_key != cell_key_value:
			errors.append("floor placement cell mismatch: expected=%s got=%s" % [expected_key, cell_key_value])
		if not occupancy.has(cell_key_value):
			errors.append("floor placement has no occupancy cell: %s" % cell_key_value)
		else:
			var occupancy_record_variant: Variant = occupancy[cell_key_value]
			if typeof(occupancy_record_variant) == TYPE_DICTIONARY:
				var occupancy_record: Dictionary = occupancy_record_variant
				if str(occupancy_record.get("room_id", "")) != room_id:
					errors.append("floor placement room mismatch: %s" % cell_key_value)
				var occupancy_module: String = str(occupancy_record.get("module_id", ""))
				if not occupancy_module.is_empty() and str(floor.get("module_id", "")) != occupancy_module:
					errors.append("floor placement module mismatch: %s" % cell_key_value)
		if room_decks.has(room_id) and int(room_decks[room_id]) != deck:
			errors.append("floor placement room deck mismatch: %s" % cell_key_value)
		var module_id: String = str(floor.get("module_id", ""))
		if not FLOOR_MODULES.has(module_id):
			errors.append("unsupported floor placement module: %s" % module_id)
		var position: Dictionary = _read_position(floor.get("position", null))
		if not bool(position.get("ok", false)):
			errors.append("floor placement position malformed: %s" % cell_key_value)
		else:
			var expected_position: Vector3 = CompilerScript.cell_world_position(deck, cell)
			if not (position["value"] as Vector3).is_equal_approx(expected_position):
				errors.append("floor placement position mismatch: %s" % cell_key_value)
		if not _is_zero(floor.get("yaw_degrees", null)):
			errors.append("floor placement yaw must be zero: %s" % cell_key_value)

	if seen_cell_keys.size() != occupancy.size():
		errors.append("floor placements are not an exact occupancy bijection: floors=%d occupancy=%d" % [seen_cell_keys.size(), occupancy.size()])
	for occupancy_key in occupancy.keys():
		if not seen_cell_keys.has(str(occupancy_key)):
			errors.append("occupancy cell has no floor placement: %s" % str(occupancy_key))


func _validate_ceiling_placements(
		plan: Dictionary,
		occupancy: Dictionary,
		topology: Dictionary,
		errors: Array[String],
		stats: Dictionary) -> void:
	var ceiling_variant: Variant = plan.get("ceiling_placements", null)
	if typeof(ceiling_variant) != TYPE_ARRAY:
		errors.append("ceiling_placements must be an array")
		return
	var ceilings: Array = ceiling_variant
	stats["ceiling_placements"] = ceilings.size()
	var opening_keys: Dictionary = _vertical_opening_keys(topology)
	var required_count: int = 0
	for occupancy_key_variant in occupancy.keys():
		if not opening_keys.has(str(occupancy_key_variant)):
			required_count += 1
	if occupancy.size() > 0 and required_count > 0 and ceilings.is_empty():
		errors.append("ceiling_placements missing for occupied cells")
		return

	var seen_cell_keys: Dictionary = {}
	for ceiling_record_variant in ceilings:
		if typeof(ceiling_record_variant) != TYPE_DICTIONARY:
			errors.append("ceiling placement must be an object")
			continue
		var ceiling: Dictionary = ceiling_record_variant
		var cell_key_value: String = str(ceiling.get("cell_key", ""))
		if cell_key_value.is_empty():
			errors.append("ceiling placement cell_key missing")
			continue
		if seen_cell_keys.has(cell_key_value):
			errors.append("duplicate ceiling placement cell_key: %s" % cell_key_value)
			continue
		seen_cell_keys[cell_key_value] = true
		if opening_keys.has(cell_key_value):
			errors.append("ceiling placement on authored vertical opening: %s" % cell_key_value)
		if not occupancy.has(cell_key_value):
			errors.append("ceiling placement has no occupancy cell: %s" % cell_key_value)
			continue
		var occupancy_record_variant: Variant = occupancy[cell_key_value]
		if typeof(occupancy_record_variant) == TYPE_DICTIONARY:
			var occupancy_record: Dictionary = occupancy_record_variant
			if str(ceiling.get("room_id", "")) != str(occupancy_record.get("room_id", "")):
				errors.append("ceiling placement room mismatch: %s" % cell_key_value)
		var deck_value: Variant = ceiling.get("deck", null)
		if not _is_integer(deck_value):
			errors.append("ceiling placement deck malformed: %s" % cell_key_value)
			continue
		var deck: int = int(deck_value)
		var parsed_cell: Dictionary = _read_cell(ceiling.get("cell", null), deck)
		if not bool(parsed_cell.get("ok", false)):
			errors.append("ceiling placement cell malformed: %s" % cell_key_value)
			continue
		var cell: Vector2i = parsed_cell["cell"]
		if CompilerScript.cell_key(deck, cell) != cell_key_value:
			errors.append("ceiling placement cell mismatch: %s" % cell_key_value)
		var module_id: String = str(ceiling.get("module_id", ""))
		if not CEILING_MODULES.has(module_id) and module_id.find("ceiling") < 0:
			errors.append("unsupported ceiling placement module: %s" % module_id)
		var position: Dictionary = _read_position(ceiling.get("position", null))
		if not bool(position.get("ok", false)):
			errors.append("ceiling placement position malformed: %s" % cell_key_value)
		else:
			var expected_position: Vector3 = CompilerScript.cell_world_position(deck, cell)
			if not (position["value"] as Vector3).is_equal_approx(expected_position):
				errors.append("ceiling placement position mismatch: %s" % cell_key_value)

	for occupancy_key_variant in occupancy.keys():
		var occupancy_key: String = str(occupancy_key_variant)
		if opening_keys.has(occupancy_key):
			continue
		if not seen_cell_keys.has(occupancy_key):
			errors.append("occupancy cell has no ceiling placement: %s" % occupancy_key)


func _validate_socket_bindings(plan: Dictionary, errors: Array[String], stats: Dictionary) -> void:
	var bindings_variant: Variant = plan.get("socket_bindings", null)
	var bound_count: int = 0
	if typeof(bindings_variant) == TYPE_ARRAY:
		bound_count = (bindings_variant as Array).size()
		for binding_variant in (bindings_variant as Array):
			if typeof(binding_variant) != TYPE_DICTIONARY:
				errors.append("socket_binding must be an object")
				continue
			var binding: Dictionary = binding_variant
			if str(binding.get("placement_id", "")).is_empty() or str(binding.get("socket_id", "")).is_empty():
				errors.append("socket_binding missing placement_id or socket_id")
			if str(binding.get("neighbor_placement_id", "")).is_empty() or str(binding.get("neighbor_socket_id", "")).is_empty():
				errors.append("socket_binding missing neighbor ids")
	elif typeof(bindings_variant) == TYPE_DICTIONARY:
		bound_count = (bindings_variant as Dictionary).size()
	else:
		errors.append("socket_bindings must be an array")
		return
	stats["socket_bindings"] = bound_count
	if bound_count <= 0:
		var placement_bound: int = 0
		for record_variant in (plan.get("placements", []) as Array) + (plan.get("floor_placements", []) as Array) + (plan.get("ceiling_placements", []) as Array):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			if (record_variant as Dictionary).has("socket_bindings"):
				var nested: Variant = (record_variant as Dictionary).get("socket_bindings", [])
				if typeof(nested) == TYPE_ARRAY:
					placement_bound += (nested as Array).size()
		if placement_bound <= 0:
			errors.append("socket_bindings missing")


func _validate_not_floor_only(plan: Dictionary, occupancy: Dictionary, errors: Array[String]) -> void:
	if occupancy.is_empty():
		return
	var placements_variant: Variant = plan.get("placements", [])
	if typeof(placements_variant) != TYPE_ARRAY:
		errors.append("floor-only structural plan: missing edge placements")
		return
	var enclosure_count: int = 0
	for placement_variant in (placements_variant as Array):
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var module_id: String = str((placement_variant as Dictionary).get("module_id", ""))
		if module_id.find("wall") >= 0 or module_id.find("door") >= 0 or module_id.find("portal") >= 0:
			enclosure_count += 1
	if enclosure_count <= 0:
		errors.append("floor-only structural plan: no wall or portal placements")


func _vertical_opening_keys(topology: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var vertical_variant: Variant = topology.get("vertical_connections", [])
	if typeof(vertical_variant) != TYPE_ARRAY:
		return keys
	var room_decks: Dictionary = _room_decks(topology)
	for link_variant in (vertical_variant as Array):
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_deck: int = int(room_decks.get(from_room, -1))
		var to_deck: int = int(room_decks.get(to_room, -1))
		var from_info: Dictionary = _read_cell(link.get("from_cell", null), from_deck)
		var to_info: Dictionary = _read_cell(link.get("to_cell", null), to_deck)
		if bool(from_info.get("ok", false)):
			keys[CompilerScript.cell_key(int(from_info["deck"]), from_info["cell"])] = true
		if bool(to_info.get("ok", false)):
			keys[CompilerScript.cell_key(int(to_info["deck"]), to_info["cell"])] = true
	return keys


func _validate_edge_placements(edges: Dictionary, placements: Array, errors: Array[String]) -> void:
	var seen_edge_keys: Dictionary = {}
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			errors.append("edge placement must be an object")
			continue
		var placement: Dictionary = placement_variant
		var edge_key_value: String = str(placement.get("edge_key", ""))
		if edge_key_value.is_empty():
			errors.append("edge placement missing edge_key")
			continue
		if seen_edge_keys.has(edge_key_value):
			errors.append("duplicate edge placement: %s" % edge_key_value)
			continue
		seen_edge_keys[edge_key_value] = true
		if not edges.has(edge_key_value):
			errors.append("edge placement references missing edge: %s" % edge_key_value)
			continue
		var edge_variant: Variant = edges[edge_key_value]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			errors.append("edge record must be an object: %s" % edge_key_value)
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(placement.get("kind", ""))
		if not EDGE_KINDS.has(kind):
			errors.append("unsupported edge kind: %s" % kind)
		if kind == "OPEN":
			errors.append("OPEN edge must not have a placement: %s" % edge_key_value)
		if FLOOR_MODULES.has(str(placement.get("module_id", ""))):
			errors.append("floor module cannot be an edge placement: %s" % edge_key_value)
		if str(edge.get("kind", edge.get("state", ""))) != kind:
			errors.append("edge placement kind mismatch: %s" % edge_key_value)
		if str(edge.get("module_id", "")) != str(placement.get("module_id", "")):
			errors.append("edge placement module mismatch: %s" % edge_key_value)
		_validate_edge_pose(placement, edge_key_value, errors)

	for edge_key_variant in edges.keys():
		var edge_key_value: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			errors.append("edge record must be an object: %s" % edge_key_value)
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "")))
		if not EDGE_KINDS.has(kind):
			errors.append("unsupported edge kind: %s" % kind)
		if kind != "OPEN" and bool(edge.get("wrapper_required", edge.get("placement_required", true))) and not seen_edge_keys.has(edge_key_value):
			errors.append("required edge has no placement: %s" % edge_key_value)


func _validate_edge_pose(placement: Dictionary, edge_key_value: String, errors: Array[String]) -> void:
	var deck_variant: Variant = placement.get("deck", null)
	var direction: String = str(placement.get("direction", ""))
	if not _is_integer(deck_variant) or not CompilerScript.DIRECTIONS.has(direction):
		errors.append("edge placement grid pose malformed: %s" % edge_key_value)
		return
	var deck: int = int(deck_variant)
	var parsed_cell: Dictionary = _read_cell(placement.get("cell", null), deck)
	if not bool(parsed_cell.get("ok", false)):
		errors.append("edge placement cell malformed: %s" % edge_key_value)
		return
	var cell: Vector2i = parsed_cell["cell"]
	var expected_key: String = CompilerScript.edge_key(deck, cell, direction)
	if expected_key != edge_key_value:
		errors.append("edge placement edge_key mismatch: %s" % edge_key_value)
	var expected_position: Vector3 = CompilerScript.edge_world_position(deck, cell, direction)
	var position: Dictionary = _read_position(placement.get("position", null))
	if not bool(position.get("ok", false)) or not (position["value"] as Vector3).is_equal_approx(expected_position):
		errors.append("edge placement position mismatch: %s" % edge_key_value)
	var expected_yaw: float = float(CompilerScript.YAW_DEGREES[direction])
	if not _is_number(placement.get("yaw_degrees", null)) or not is_equal_approx(float(placement.get("yaw_degrees")), expected_yaw):
		errors.append("edge placement yaw mismatch: %s" % edge_key_value)


func _validate_portal_endpoints(topology: Dictionary, occupancy: Dictionary, edges: Dictionary, errors: Array[String]) -> void:
	var portals_variant: Variant = topology.get("portals", null)
	if typeof(portals_variant) != TYPE_ARRAY:
		errors.append("topology portals must be an array")
		return
	var room_decks: Dictionary = _room_decks(topology)
	for portal_variant in (portals_variant as Array):
		if typeof(portal_variant) != TYPE_DICTIONARY:
			errors.append("portal record must be an object")
			continue
		var portal: Dictionary = portal_variant
		var from_room: String = str(portal.get("from_room", ""))
		var to_room: String = str(portal.get("to_room", ""))
		if not room_decks.has(from_room) or not room_decks.has(to_room):
			errors.append("portal room endpoints are not reciprocal: %s" % str(portal.get("id", "")))
			continue
		var from_info: Dictionary = _read_cell(portal.get("from_cell", null), int(room_decks[from_room]))
		var to_info: Dictionary = _read_cell(portal.get("to_cell", null), int(room_decks[to_room]))
		if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
			errors.append("portal endpoints are malformed: %s" % str(portal.get("id", "")))
			continue
		if int(from_info["deck"]) != int(to_info["deck"]):
			errors.append("portal endpoints must be same-deck: %s" % str(portal.get("id", "")))
			continue
		var from_cell: Vector2i = from_info["cell"]
		var to_cell: Vector2i = to_info["cell"]
		var from_key: String = CompilerScript.cell_key(int(from_info["deck"]), from_cell)
		var to_key: String = CompilerScript.cell_key(int(to_info["deck"]), to_cell)
		if _occupancy_room(occupancy, from_key) != from_room or _occupancy_room(occupancy, to_key) != to_room:
			errors.append("portal endpoints are not reciprocal: %s" % str(portal.get("id", "")))
			continue
		var declared_from_direction: String = str(portal.get("from_direction", ""))
		var declared_to_direction: String = str(portal.get("to_direction", ""))
		if not declared_from_direction.is_empty() or not declared_to_direction.is_empty():
			if not CompilerScript.OPPOSITE.has(declared_from_direction) or declared_to_direction != str(CompilerScript.OPPOSITE[declared_from_direction]):
				errors.append("opposed portal normals mismatch: %s" % str(portal.get("id", "")))
		var delta: Vector2i = to_cell - from_cell
		var edge_cell: Vector2i = from_cell
		var direction: String = ""
		for candidate in CompilerScript.DIRECTIONS.keys():
			if (CompilerScript.DIRECTIONS[candidate] as Vector2i) == delta:
				direction = str(candidate)
				break
		var logical_boundary: bool = false
		if direction.is_empty() and typeof(portal.get("edge_cell", null)) != TYPE_NIL:
			var edge_info: Dictionary = _read_cell(portal.get("edge_cell", null), int(from_info["deck"]))
			var declared_direction: String = str(portal.get("edge_direction", ""))
			if bool(edge_info.get("ok", false)) and CompilerScript.DIRECTIONS.has(declared_direction):
				edge_cell = edge_info["cell"]
				direction = declared_direction
				logical_boundary = true
		if direction.is_empty():
			errors.append("portal endpoints are not adjacent: %s" % str(portal.get("id", "")))
			continue
		var edge_key_value: String = CompilerScript.edge_key(int(from_info["deck"]), edge_cell, direction)
		if not edges.has(edge_key_value):
			errors.append("portal has no canonical edge: %s" % edge_key_value)
			continue
		var edge: Dictionary = edges[edge_key_value]
		if not bool(edge.get("portal", false)):
			errors.append("portal edge was compiled as non-portal: %s" % edge_key_value)
		if str(edge.get("kind", "SOLID")) == "SOLID":
			errors.append("topology-connected rooms blocked by SOLID edge: %s" % edge_key_value)
		if logical_boundary and str(edge.get("other_room", "")) != to_room:
			errors.append("logical portal room endpoint mismatch: %s" % edge_key_value)


func _occupancy_room(occupancy: Dictionary, cell_key_value: String) -> String:
	if not occupancy.has(cell_key_value):
		return ""
	var record_variant: Variant = occupancy[cell_key_value]
	if typeof(record_variant) != TYPE_DICTIONARY:
		return ""
	return str((record_variant as Dictionary).get("room_id", ""))


func _validate_walkable_flood_fill(topology: Dictionary, occupancy: Dictionary, edges: Dictionary, errors: Array[String]) -> void:
	var adjacency: Dictionary = {}
	for occupancy_key_variant in occupancy.keys():
		adjacency[str(occupancy_key_variant)] = []
	for edge_key_variant in edges.keys():
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID")))
		if kind == "SOLID":
			continue
		var source_cells: Array = edge.get("source_cells", []) if typeof(edge.get("source_cells", [])) == TYPE_ARRAY else []
		if source_cells.size() < 2:
			continue
		var first: Dictionary = _cell_key_from_value(source_cells[0], int(edge.get("deck", -1)))
		var second: Dictionary = _cell_key_from_value(source_cells[1], int(edge.get("deck", -1)))
		if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
			continue
		var first_key: String = str(first["key"])
		var second_key: String = str(second["key"])
		if not adjacency.has(first_key) or not adjacency.has(second_key):
			continue
		(adjacency[first_key] as Array).append(second_key)
		(adjacency[second_key] as Array).append(first_key)

	var vertical_variant: Variant = topology.get("vertical_connections", [])
	if typeof(vertical_variant) == TYPE_ARRAY:
		var room_decks: Dictionary = _room_decks(topology)
		for link_variant in (vertical_variant as Array):
			if typeof(link_variant) != TYPE_DICTIONARY:
				continue
			var link: Dictionary = link_variant
			var from_room: String = str(link.get("from_room", ""))
			var to_room: String = str(link.get("to_room", ""))
			if not room_decks.has(from_room) or not room_decks.has(to_room):
				continue
			var from_info: Dictionary = _read_cell(link.get("from_cell", null), int(room_decks[from_room]))
			var to_info: Dictionary = _read_cell(link.get("to_cell", null), int(room_decks[to_room]))
			if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
				continue
			var from_key: String = CompilerScript.cell_key(int(from_info["deck"]), from_info["cell"])
			var to_key: String = CompilerScript.cell_key(int(to_info["deck"]), to_info["cell"])
			if adjacency.has(from_key) and adjacency.has(to_key):
				(adjacency[from_key] as Array).append(to_key)
				(adjacency[to_key] as Array).append(from_key)

	var portals_variant: Variant = topology.get("portals", [])
	if typeof(portals_variant) == TYPE_ARRAY:
		for portal_variant in (portals_variant as Array):
			if typeof(portal_variant) != TYPE_DICTIONARY:
				continue
			var portal: Dictionary = portal_variant
			var room_decks: Dictionary = _room_decks(topology)
			var from_room: String = str(portal.get("from_room", ""))
			var to_room: String = str(portal.get("to_room", ""))
			if not room_decks.has(from_room) or not room_decks.has(to_room):
				continue
			var from_info: Dictionary = _read_cell(portal.get("from_cell", null), int(room_decks[from_room]))
			var to_info: Dictionary = _read_cell(portal.get("to_cell", null), int(room_decks[to_room]))
			if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
				continue
			var from_key: String = CompilerScript.cell_key(int(from_info["deck"]), from_info["cell"])
			var to_key: String = CompilerScript.cell_key(int(to_info["deck"]), to_info["cell"])
			if not adjacency.has(from_key) or not adjacency.has(to_key):
				continue
			if not _reachable(adjacency, from_key, to_key):
				# A diagonal legacy link has an explicit rendered boundary, but
				# must still participate in logical flood fill exactly once.
				if bool(portal.get("logical_boundary", false)):
					(adjacency[from_key] as Array).append(to_key)
					(adjacency[to_key] as Array).append(from_key)
				if not _reachable(adjacency, from_key, to_key):
					errors.append("flood-fill/topology reachability disagreement: %s" % str(portal.get("id", "")))

	_validate_critical_path_reachability(topology, occupancy, adjacency, errors)

func _validate_critical_path_reachability(topology: Dictionary, occupancy: Dictionary, adjacency: Dictionary, errors: Array[String]) -> void:
	var critical_variant: Variant = topology.get("critical_path", [])
	if typeof(critical_variant) != TYPE_ARRAY:
		return
	var critical: Array = critical_variant
	for index in range(critical.size() - 1):
		var from_room: String = str(critical[index])
		var to_room: String = str(critical[index + 1])
		var from_cells: Array[String] = _room_cells(occupancy, from_room)
		var to_cells: Array[String] = _room_cells(occupancy, to_room)
		if from_cells.is_empty() or to_cells.is_empty():
			errors.append("topology reachability room missing: %s -> %s" % [from_room, to_room])
			continue
		var connected: bool = false
		for from_key in from_cells:
			for to_key in to_cells:
				if _reachable(adjacency, from_key, to_key):
					connected = true
					break
			if connected:
				break
		if not connected:
			errors.append("flood-fill/topology reachability disagreement: %s -> %s" % [from_room, to_room])


func _room_cells(occupancy: Dictionary, room_id: String) -> Array[String]:
	var cells: Array[String] = []
	for key_variant in occupancy.keys():
		var key: String = str(key_variant)
		if _occupancy_room(occupancy, key) == room_id:
			cells.append(key)
	return cells


func _reachable(adjacency: Dictionary, start_key: String, goal_key: String) -> bool:
	var queue: Array[String] = [start_key]
	var visited: Dictionary = {start_key: true}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal_key:
			return true
		for neighbor_variant in (adjacency.get(current, []) as Array):
			var neighbor: String = str(neighbor_variant)
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


func _room_decks(topology: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rooms_variant: Variant = topology.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return out
	for room_variant in (rooms_variant as Array):
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		if not room_id.is_empty() and _is_integer(room.get("deck", null)):
			out[room_id] = int(room.get("deck"))
	return out


func _cell_key_from_value(value: Variant, default_deck: int) -> Dictionary:
	var info: Dictionary = _read_cell(value, default_deck)
	if not bool(info.get("ok", false)):
		return {"ok": false}
	return {"ok": true, "key": CompilerScript.cell_key(int(info["deck"]), info["cell"]), "cell": info["cell"], "deck": int(info["deck"])}


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
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() < 3 or not _is_number(values[0]) or not _is_number(values[1]) or not _is_number(values[2]):
			return {"ok": false}
		return {"ok": true, "value": Vector3(float(values[0]), float(values[1]), float(values[2]))}
	if typeof(value) == TYPE_STRING:
		var parsed: Array = _parse_vector_string(str(value), 3)
		if parsed.size() == 3:
			return {"ok": true, "value": Vector3(float(parsed[0]), float(parsed[1]), float(parsed[2]))}
	return {"ok": false}


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


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or (typeof(value) == TYPE_STRING and str(value).is_valid_float())


func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(float(value), roundf(float(value)))
	if typeof(value) == TYPE_STRING:
		return str(value).is_valid_int()
	return false


func _is_zero(value: Variant) -> bool:
	return _is_number(value) and is_equal_approx(float(value), 0.0)
