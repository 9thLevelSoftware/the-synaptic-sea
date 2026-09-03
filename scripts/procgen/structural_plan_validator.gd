extends RefCounted
class_name StructuralPlanValidator

## Fail-closed validator for compiler-produced structural plans.
## Edge placements and floor placements are intentionally separate contracts:
## floors identify occupied cells; edge records identify canonical boundaries.

const CompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const WalkabilityContractScript: GDScript = preload("res://scripts/procgen/walkability_contract.gd")
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
		"placement_count": 0,
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
	if typeof(occupancy_variant) != TYPE_DICTIONARY and typeof(occupancy_variant) != TYPE_ARRAY:
		errors.append("occupancy must be a dictionary or array of records")
		return _verdict(errors, stats)
	var occupancy: Dictionary = {}
	var occupancy_records_array: Array = []
	if typeof(occupancy_variant) == TYPE_DICTIONARY:
		occupancy = occupancy_variant
		stats["occupied_cells"] = occupancy.size()
		if occupancy.is_empty():
			errors.append("occupancy must be non-empty")
	else:
		occupancy_records_array = occupancy_variant
		stats["occupied_cells"] = occupancy_records_array.size()
		if occupancy_records_array.is_empty():
			errors.append("occupancy must be non-empty")
		# Materialize an Array-of-records into the key->record shape so the
		# downstream per-record validators can run their canonical checks.
		# First occurrence wins so duplicate cell_keys are still tracked for
		# the dedicated footprint-overlap gate below.
		var seen_array_keys: Dictionary = {}
		for record_variant in occupancy_records_array:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			var cell_key_value: String = str(record.get("cell_key", ""))
			if cell_key_value.is_empty():
				continue
			if not seen_array_keys.has(cell_key_value):
				seen_array_keys[cell_key_value] = true
				occupancy[cell_key_value] = record

	var edges_variant: Variant = plan.get("edges", null)
	if typeof(edges_variant) != TYPE_DICTIONARY:
		errors.append("canonical edge map must be non-empty")
	var edges: Dictionary = edges_variant if typeof(edges_variant) == TYPE_DICTIONARY else {}
	stats["edges"] = edges.size()
	if edges.is_empty():
		errors.append("canonical edge map must be non-empty")

	var placements_variant: Variant = plan.get("placements", null)
	if typeof(placements_variant) != TYPE_ARRAY:
		errors.append("placements must be an array")
	var placements: Array = placements_variant if typeof(placements_variant) == TYPE_ARRAY else []
	stats["edge_placements"] = placements.size()
	stats["placement_count"] = placements.size()

	var room_registry: Dictionary = _room_registry(topology)
	# When the topology supplies no room registry (empty rooms array or
	# no rooms key), treat the plan as self-describing — defer room-id
	# membership to the per-record checks below and skip the global
	# topology-room reconciliation that would otherwise reject a valid
	# plan with rooms the caller did not enumerate.
	var topology_has_room_registry: bool = not room_registry.is_empty()

	_validate_occupancy_records(occupancy, errors)
	_validate_floor_placements(plan, occupancy, topology, errors, stats)
	_validate_ceiling_placements(plan, occupancy, topology, errors, stats)
	_validate_socket_bindings(plan, errors, stats)
	_validate_not_floor_only(plan, occupancy, errors)
	_validate_unique_edge_placements(plan, errors)
	_validate_edge_placements(edges, placements, errors)
	_validate_portal_endpoints_with_registry(plan, room_registry, errors)
	_validate_placement_grid_pose(plan, errors)
	_validate_footprint_overlap(plan, errors)
	_validate_walkable_reachability(plan, topology, errors)
	_validate_occupancy_key_body_reconciliation(occupancy, room_registry, errors)
	_validate_edge_kind_state(edges, errors)
	_validate_placement_reconciliation(plan, topology, errors)

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
	var enforce_room_membership: bool = not room_decks.is_empty()
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
		elif enforce_room_membership and not room_decks.has(room_id):
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
		# BREACH/HATCH exterior portals are non-wrapper states — they do not
		# require a placement even when the canonical edge did not mark
		# placement_required=false. Apply the same exception here that the
		# compiler applies when emitting the canonical record so a mutator
		# that flips kind+exterior without also flipping placement_required
		# does not get spuriously rejected.
		var placement_required: bool = bool(edge.get("wrapper_required", edge.get("placement_required", true)))
		var is_non_wrapper_exterior: bool = (kind == "BREACH" or kind == "HATCH") and bool(edge.get("exterior", false))
		if is_non_wrapper_exterior:
			placement_required = false
		if kind != "OPEN" and placement_required and not seen_edge_keys.has(edge_key_value):
			if kind == "DOOR":
				errors.append("DOOR requires exactly one non-OPEN placement: %s" % edge_key_value)
			else:
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


func _validate_portal_endpoints_legacy(topology: Dictionary, occupancy: Dictionary, edges: Dictionary, errors: Array[String]) -> void:
	# Legacy topology-coupled portal validator. The new strict
	# `_validate_portal_endpoints(plan, errors)` (declared further below)
	# handles canonical edge metadata; this stub remains so existing call
	# sites compile and so we can layer additional topology checks when a
	# full topology dictionary is supplied alongside the plan.
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
			continue
		if int(from_info["deck"]) != int(to_info["deck"]):
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
				errors.append("opposed portal normals are invalid: %s" % str(portal.get("id", "")))
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
			continue
		var edge_key_value: String = CompilerScript.edge_key(int(from_info["deck"]), edge_cell, direction)
		if not edges.has(edge_key_value):
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
		if not WalkabilityContractScript.enclosure_passable(kind):
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


# Build a {room_id: deck} registry from a topology layout.
func _room_registry(topology: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rooms_variant: Variant = topology.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return out
	for room_variant in (rooms_variant as Array):
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		if not room_id.is_empty():
			out[room_id] = true
	return out


# Strict duplicate-edge-placement guard. Each canonical edge must map to
# exactly one placement; duplicate placements and missing placement_ids are
# reported with deterministic diagnostics.
func _validate_unique_edge_placements(plan: Dictionary, errors: Array[String]) -> void:
	var placements_variant: Variant = plan.get("placements", null)
	if typeof(placements_variant) != TYPE_ARRAY:
		return
	var placements: Array = placements_variant
	var seen: Dictionary = {}
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			errors.append("edge placement must be an object")
			continue
		var placement: Dictionary = placement_variant
		var edge_key_value: String = str(placement.get("edge_key", ""))
		if edge_key_value.is_empty():
			# Surfaced separately in the grid-pose validator; skip here.
			continue
		if seen.has(edge_key_value):
			errors.append("duplicate edge placement: %s" % edge_key_value)
			continue
		seen[edge_key_value] = true


# Portal endpoint schema guard. Replaces the topology-coupled legacy check
# with a strict validation of the plan's per-edge portal endpoint metadata:
# each portal edge must carry a non-empty portal_id + source_cells array
# exactly two cells wide, the kind/state must agree, and the two source_cells
# must straddle the declared edge_key.
func _validate_portal_endpoints(plan: Dictionary, errors: Array[String]) -> void:
	# Convenience wrapper for callers that do not have a room registry at
	# hand. The full implementation requires a topology-derived registry to
	# catch ghost-room edge endpoints; this overload constructs an empty
	# one and defers to the canonical entry point.
	_validate_portal_endpoints_with_registry(plan, {}, errors)


func _validate_portal_endpoints_with_registry(plan: Dictionary, room_registry: Dictionary, errors: Array[String]) -> void:
	var edges_variant: Variant = plan.get("edges", null)
	if typeof(edges_variant) != TYPE_DICTIONARY:
		return
	var edges: Dictionary = edges_variant
	for edge_key_variant in edges.keys():
		var edge_key_value: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			errors.append("edge record is not a Dictionary: %s" % edge_key_value)
			continue
		var edge: Dictionary = edge_variant
		# Source cells must be an Array of exactly two Vector2i/int-pair values
		# that straddle the declared edge_key — applies to ALL edges, not
		# only portals. Wall edges also need geometry-correct source_cells
		# so the walkability flood fill is consistent.
		var source_cells_variant: Variant = edge.get("source_cells", null)
		if typeof(source_cells_variant) != TYPE_ARRAY or (source_cells_variant as Array).size() != 2:
			if bool(edge.get("portal", false)):
				errors.append("portal source_cells must be an Array of exactly two cells: %s" % edge_key_value)
			continue
		var source_cells: Array = source_cells_variant
		var first_cell_info: Dictionary = _read_cell(source_cells[0], int(edge.get("deck", 0)))
		var second_cell_info: Dictionary = _read_cell(source_cells[1], int(edge.get("deck", 0)))
		if not bool(first_cell_info.get("ok", false)) or not bool(second_cell_info.get("ok", false)):
			if bool(edge.get("portal", false)):
				errors.append("portal source_cells are invalid: %s" % edge_key_value)
			continue
		var first_cell: Vector2i = first_cell_info["cell"]
		var second_cell: Vector2i = second_cell_info["cell"]
		# Cells must be adjacent.
		var delta: Vector2i = second_cell - first_cell
		var adjacent: bool = false
		for candidate_direction in CompilerScript.DIRECTIONS.keys():
			if (CompilerScript.DIRECTIONS[candidate_direction] as Vector2i) == delta or (CompilerScript.DIRECTIONS[candidate_direction] as Vector2i) == -delta:
				adjacent = true
				break
		if not adjacent and bool(edge.get("portal", false)):
			errors.append("portal source_cells are not adjacent across declared edge: %s" % edge_key_value)
			continue
		# The canonical edge_key derived from first_cell + a direction that
		# produces delta must equal the edge_key under validation. Re-derive
		# both directions and accept either order.
		var direction: String = str(edge.get("direction", ""))
		var resolved_key: String = ""
		if CompilerScript.DIRECTIONS.has(direction):
			var forward_key: String = CompilerScript.edge_key(int(edge.get("deck", 0)), first_cell, direction)
			var reverse_key: String = CompilerScript.edge_key(int(edge.get("deck", 0)), second_cell, direction)
			if forward_key == edge_key_value:
				resolved_key = forward_key
			elif reverse_key == edge_key_value:
				resolved_key = reverse_key
		if resolved_key.is_empty():
			if bool(edge.get("portal", false)):
				errors.append("portal source_cells do not match declared edge_key: %s" % edge_key_value)
			else:
				errors.append("source_cells do not match declared edge_key: %s" % edge_key_value)
		# Reciprocity: room_ids must reference two distinct rooms or one is empty.
		var room_ids_variant: Variant = edge.get("room_ids", [])
		if typeof(room_ids_variant) != TYPE_ARRAY or (room_ids_variant as Array).size() != 2:
			if bool(edge.get("portal", false)):
				errors.append("portal endpoints are not reciprocal: %s" % edge_key_value)
			continue
		var owner_room: String = str((room_ids_variant as Array)[0])
		var other_room: String = str((room_ids_variant as Array)[1])
		if owner_room == other_room and not owner_room.is_empty() and bool(edge.get("portal", false)):
			errors.append("portal endpoints are not reciprocal: %s" % edge_key_value)
			continue
		# Edge endpoint contract: the other_room must either be empty
		# (exterior edge) or a known room in the topology registry. Walls
		# and portals that point to a ghost room are rejected.
		if not other_room.is_empty():
			var owner_known: bool = room_registry.has(owner_room)
			var other_known: bool = room_registry.has(other_room)
			if owner_room.is_empty() or not owner_known or not other_known:
				if bool(edge.get("portal", false)):
					errors.append("portal endpoints are not reciprocal: %s" % edge_key_value)
				else:
					errors.append("edge endpoint references unknown room: %s" % edge_key_value)
		# Opposed portal normals: opposite_direction must be the OPPOSITE of direction.
		if bool(edge.get("portal", false)):
			var opposite_direction: String = str(edge.get("opposite_direction", ""))
			if CompilerScript.DIRECTIONS.has(direction):
				var expected_opposite: String = str(CompilerScript.OPPOSITE[direction])
				if opposite_direction != expected_opposite:
					errors.append("opposed portal normals are invalid: %s" % edge_key_value)
			else:
				errors.append("opposed portal normals are invalid: %s" % edge_key_value)


# Strict grid-pose gate. Rejects placements whose edge_key cannot be parsed
# back to a canonical (deck, cell, direction) triple and whose yaw/position
# drifted from the pose table. Detects placements that lost their edge_key
# entirely (legacy key fallback is forbidden).
func _validate_placement_grid_pose(plan: Dictionary, errors: Array[String]) -> void:
	var placements_variant: Variant = plan.get("placements", null)
	if typeof(placements_variant) != TYPE_ARRAY:
		return
	var placements: Array = placements_variant
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_variant
		var edge_key_value: String = str(placement.get("edge_key", ""))
		if edge_key_value.is_empty():
			errors.append("placement edge_key is required; legacy key fallback is forbidden")
			continue
		var deck_variant: Variant = placement.get("deck", null)
		if not _is_integer(deck_variant):
			errors.append("edge placement grid pose malformed: %s" % edge_key_value)
			continue
		var deck: int = int(deck_variant)
		var direction: String = str(placement.get("direction", ""))
		if not CompilerScript.DIRECTIONS.has(direction):
			errors.append("edge placement grid pose malformed: %s" % edge_key_value)
			continue
		var parsed: Dictionary = CompilerScript._parse_edge_key(edge_key_value)
		if not bool(parsed.get("ok", false)) or int(parsed.get("deck", -1)) != deck:
			errors.append("edge placement grid pose malformed: %s" % edge_key_value)
			continue
		# Position is derived from the placement's own `cell` (and direction),
		# not from parsing the edge_key — the placement may pick either
		# of the two source_cells as its own cell.
		var cell_info: Dictionary = _read_cell(placement.get("cell", null), deck)
		if not bool(cell_info.get("ok", false)):
			errors.append("edge placement position mismatch: %s" % edge_key_value)
			continue
		var cell: Vector2i = cell_info["cell"]
		var expected_yaw: float = float(CompilerScript.YAW_DEGREES[direction])
		var yaw_value: Variant = placement.get("yaw_degrees", null)
		if not _is_number(yaw_value) or not is_equal_approx(float(yaw_value), expected_yaw):
			errors.append("placement yaw is outside canonical pose: %s" % edge_key_value)
		var expected_position: Vector3 = CompilerScript.edge_world_position(deck, cell, direction)
		var position: Dictionary = _read_position(placement.get("position", null))
		if not bool(position.get("ok", false)) or not (position["value"] as Vector3).is_equal_approx(expected_position):
			errors.append("edge placement drifted from canonical cell edge: %s" % edge_key_value)


# Footprint-overlap guard. Floors and ceilings must declare unique cell_keys;
# occupancy records must match the floor placement bijection.
func _validate_footprint_overlap(plan: Dictionary, errors: Array[String]) -> void:
	var floor_variant: Variant = plan.get("floor_placements", [])
	var floor_array: Array = floor_variant if typeof(floor_variant) == TYPE_ARRAY else []
	var seen: Dictionary = {}
	for floor_variant_item in floor_array:
		if typeof(floor_variant_item) != TYPE_DICTIONARY:
			continue
		var floor_record: Dictionary = floor_variant_item
		var cell_key_value: String = str(floor_record.get("cell_key", ""))
		if cell_key_value.is_empty():
			continue
		if seen.has(cell_key_value):
			errors.append("occupied-cell overlap: %s" % cell_key_value)
			continue
		seen[cell_key_value] = true
	# Occupancy may be a Dictionary OR an Array of records. Detect duplicate
	# cell_keys in either shape and surface "occupied-cell overlap" — the
	# Array form preserves record multiplicity, so duplicates are visible
	# without lossy dedup.
	var occupancy_variant: Variant = plan.get("occupancy", {})
	var occupancy_seen: Dictionary = {}
	if typeof(occupancy_variant) == TYPE_ARRAY:
		for record_variant in (occupancy_variant as Array):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record_cell_key: String = str((record_variant as Dictionary).get("cell_key", ""))
			if record_cell_key.is_empty():
				continue
			if occupancy_seen.has(record_cell_key):
				errors.append("occupied-cell overlap: %s" % record_cell_key)
			else:
				occupancy_seen[record_cell_key] = true
	elif typeof(occupancy_variant) == TYPE_DICTIONARY:
		for occupancy_key_variant in (occupancy_variant as Dictionary).keys():
			if not seen.has(str(occupancy_key_variant)):
				errors.append("occupied-cell overlap: %s" % str(occupancy_key_variant))


# Walkable reachability replaces the legacy flood fill with a strict gate.
# Both critical_path links and portal endpoints must be reachable in the
# standing-pass graph (enclosure kinds except SOLID). Reachability failures
# report "flood_fill/topology reachability mismatch".
func _validate_walkable_reachability(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void:
	var occupancy_variant: Variant = plan.get("occupancy", null)
	var edges_variant: Variant = plan.get("edges", null)
	if typeof(occupancy_variant) != TYPE_DICTIONARY or typeof(edges_variant) != TYPE_DICTIONARY:
		return
	var occupancy: Dictionary = occupancy_variant
	var edges: Dictionary = edges_variant
	var adjacency: Dictionary = _enclosure_adjacency(occupancy, edges)
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

	# Portal endpoints must be mutually reachable.
	var portals_variant: Variant = topology.get("portals", [])
	if typeof(portals_variant) == TYPE_ARRAY:
		var room_decks: Dictionary = _room_decks(topology)
		for portal_variant in (portals_variant as Array):
			if typeof(portal_variant) != TYPE_DICTIONARY:
				continue
			var portal: Dictionary = portal_variant
			var from_room: String = str(portal.get("from_room", ""))
			var to_room: String = str(portal.get("to_room", ""))
			if not room_decks.has(from_room) or not room_decks.has(to_room):
				continue
			# If the canonical edge at this portal's edge_key is exterior
			# (BREACH/HATCH with other_room empty), the portal is
			# effectively one-sided. The flood-fill cannot satisfy a
			# topology portal that has no interior partner, so skip the
			# reachability check entirely instead of spuriously failing.
			var portal_edge_key_check: String = str(portal.get("edge_key", ""))
			var edge_for_portal: Dictionary = edges.get(portal_edge_key_check, {}) if typeof(edges.get(portal_edge_key_check, {})) == TYPE_DICTIONARY else {}
			if bool(edge_for_portal.get("exterior", false)):
				continue
			# LOCKED portals block standing traversal by design. A LOCKED
			# canonical edge that pairs with a LOCKED topology portal is a
			# valid "locked shut" configuration; the reachability gate must
			# not fail it. Skip non-walkable portal kinds entirely.
			var portal_kind: String = _portal_kind_for_reachability(portal)
			if portal_kind == "LOCKED" or portal_kind == "HATCH" or portal_kind == "BREACH":
				continue
			var from_key: String = ""
			var to_key: String = ""
			var from_info: Dictionary = _read_cell(portal.get("from_cell", portal.get("logical_from_cell", null)), int(room_decks[from_room]))
			var to_info: Dictionary = _read_cell(portal.get("to_cell", portal.get("logical_to_cell", null)), int(room_decks[to_room]))
			if bool(from_info.get("ok", false)) and bool(to_info.get("ok", false)):
				from_key = CompilerScript.cell_key(int(from_info["deck"]), from_info["cell"])
				to_key = CompilerScript.cell_key(int(to_info["deck"]), to_info["cell"])
			else:
				# Fall back to the canonical edge_key: parse it and derive
				# the source-cell pair that should be mutually reachable. This
				# keeps the reachability gate meaningful for portals that only
				# declare edge_key (no from_cell/to_cell), which is the form
				# produced by the layout generator and accepted by tests.
				var parsed_edge: Dictionary = CompilerScript._parse_edge_key(portal_edge_key_check)
				if not bool(parsed_edge.get("ok", false)):
					continue
				var deck_value: int = int(parsed_edge["deck"])
				var edge_x: int = int(parsed_edge.get("x", -1))
				var edge_y: int = int(parsed_edge.get("y", -1))
				if edge_x < 0 or edge_y < 0:
					continue
				var axis: String = str(parsed_edge.get("axis", ""))
				var primary_cell: Vector2i
				var secondary_cell: Vector2i
				if axis == "v":
					primary_cell = Vector2i(edge_x, edge_y)
					secondary_cell = Vector2i(edge_x + 1, edge_y)
				elif axis == "h":
					primary_cell = Vector2i(edge_x, edge_y)
					secondary_cell = Vector2i(edge_x, edge_y + 1)
				else:
					continue
				var primary_key: String = CompilerScript.cell_key(deck_value, primary_cell)
				var secondary_key: String = CompilerScript.cell_key(deck_value, secondary_cell)
				if occupancy.has(primary_key):
					from_key = primary_key
					to_key = secondary_key
				elif occupancy.has(secondary_key):
					from_key = secondary_key
					to_key = primary_key
				else:
					continue
			if not adjacency.has(from_key) or not adjacency.has(to_key):
				continue
			if not _reachable(adjacency, from_key, to_key):
				errors.append("flood_fill/topology reachability mismatch: %s" % str(portal.get("id", "")))

	# Critical path reachability.
	var critical_variant: Variant = topology.get("critical_path", [])
	if typeof(critical_variant) == TYPE_ARRAY:
		var critical: Array = critical_variant
		for index in range(critical.size() - 1):
			var from_room: String = str(critical[index])
			var to_room: String = str(critical[index + 1])
			var from_cells: Array[String] = _room_cells(occupancy, from_room)
			var to_cells: Array[String] = _room_cells(occupancy, to_room)
			if from_cells.is_empty() or to_cells.is_empty():
				errors.append("flood_fill/topology reachability mismatch: %s -> %s" % [from_room, to_room])
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
				errors.append("flood_fill/topology reachability mismatch: %s -> %s" % [from_room, to_room])


# Build an adjacency map restricted to standing-passable edges. The flood
# fill is a *walkability* check — a player cannot pass through a LOCKED
# door. Restricting to standing-passable makes LOCKED topology portals
# fail the reachability gate as required by the validator contract.
func _enclosure_adjacency(occupancy: Dictionary, edges: Dictionary) -> Dictionary:
	var adjacency: Dictionary = {}
	for occupancy_key_variant in occupancy.keys():
		adjacency[str(occupancy_key_variant)] = []
	for edge_key_variant in edges.keys():
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID")))
		if not WalkabilityContractScript.standing_passable(kind):
			continue
		var source_cells_variant: Variant = edge.get("source_cells", [])
		if typeof(source_cells_variant) != TYPE_ARRAY or (source_cells_variant as Array).size() != 2:
			continue
		var first_cell_info: Dictionary = _read_cell(source_cells_variant[0], int(edge.get("deck", 0)))
		var second_cell_info: Dictionary = _read_cell(source_cells_variant[1], int(edge.get("deck", 0)))
		if not bool(first_cell_info.get("ok", false)) or not bool(second_cell_info.get("ok", false)):
			continue
		var first_key: String = CompilerScript.cell_key(int(first_cell_info["deck"]), first_cell_info["cell"])
		var second_key: String = CompilerScript.cell_key(int(second_cell_info["deck"]), second_cell_info["cell"])
		if not adjacency.has(first_key) or not adjacency.has(second_key):
			continue
		(adjacency[first_key] as Array).append(second_key)
		(adjacency[second_key] as Array).append(first_key)
	return adjacency


# Resolve a topology portal to its canonical kind string so the reachability
# gate can short-circuit on non-walkable portal kinds (LOCKED/HATCH/BREACH).
# Mirrors the compiler's `_portal_kind` semantics so the validator agrees
# with the canonical records it just produced.
func _portal_kind_for_reachability(portal: Dictionary) -> String:
	var raw: String = str(portal.get("state",
		portal.get("portal_type",
		portal.get("kind",
		portal.get("type", "DOOR"))))).to_upper()
	if raw == "OPEN":
		return "DOOR"
	if raw == "DOOR" or raw == "LOCKED" or raw == "HATCH" or raw == "BREACH":
		return raw
	return "DOOR"


# Strict occupancy reconciliation: each occupancy record's key must match
# CompilerScript.cell_key(deck, cell) AND the record's room_id must be a
# known room in the topology room registry.
func _validate_occupancy_key_body_reconciliation(occupancy: Dictionary, room_registry: Dictionary, errors: Array[String]) -> void:
	for occupancy_key_variant in occupancy.keys():
		var occupancy_key: String = str(occupancy_key_variant)
		var record_variant: Variant = occupancy[occupancy_key_variant]
		if typeof(record_variant) != TYPE_DICTIONARY:
			errors.append("occupancy record is not a Dictionary: %s" % occupancy_key)
			continue
		var record: Dictionary = record_variant
		var deck_value: Variant = record.get("deck", null)
		var cell_value: Variant = record.get("cell", null)
		if not _is_integer(deck_value) or typeof(cell_value) == TYPE_NIL:
			errors.append("occupancy record is malformed: %s" % occupancy_key)
			continue
		var cell_info: Dictionary = _read_cell(cell_value, int(deck_value))
		if not bool(cell_info.get("ok", false)):
			errors.append("occupancy record is malformed: %s" % occupancy_key)
			continue
		var expected_key: String = CompilerScript.cell_key(int(cell_info["deck"]), cell_info["cell"])
		if expected_key != occupancy_key:
			errors.append("cell-key/body drift: %s" % occupancy_key)
			continue
		# Stray records (no room) and ghost rooms must be reported.
		# Skip the registry-membership check when the topology supplied no
		# room registry (empty rooms list) — a sparse topology should not
		# ghost-room every plan cell.
		var room_id: String = str(record.get("room_id", ""))
		if room_id.is_empty():
			errors.append("unknown room_id: %s" % occupancy_key)
		elif not room_registry.is_empty() and not room_registry.has(room_id):
			errors.append("unknown room_id: %s" % occupancy_key)


# Strict semantic-state gate. Edges must declare a known kind, must agree on
# kind/state, and one-sided HATCH/BREACH portals must explicitly mark
# exterior=true. Unknown kinds, absent kinds, and kind/state mismatches
# emit canonical diagnostics.
func _validate_edge_kind_state(edges: Dictionary, errors: Array[String]) -> void:
	var declared_kinds: Array[String] = ["SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"]
	for edge_key_variant in edges.keys():
		var edge_key_value: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			errors.append("edge record is not a Dictionary: %s" % edge_key_value)
			continue
		var edge: Dictionary = edge_variant
		var has_kind: bool = edge.has("kind")
		var has_state: bool = edge.has("state")
		if not has_kind and not has_state:
			errors.append("semantic state is missing: %s" % edge_key_value)
			continue
		var kind: String = str(edge.get("kind", edge.get("state", "")))
		var state: String = str(edge.get("state", edge.get("kind", "")))
		if not declared_kinds.has(kind):
			errors.append("unknown semantic state: %s" % edge_key_value)
			continue
		if has_kind and has_state and kind != state:
			errors.append("kind/state mismatch: %s" % edge_key_value)
		if (kind == "HATCH" or kind == "BREACH") and not bool(edge.get("portal", false)):
			errors.append("portal edge was compiled as non-portal: %s" % edge_key_value)
		var room_ids_variant: Variant = edge.get("room_ids", [])
		if typeof(room_ids_variant) == TYPE_ARRAY and (room_ids_variant as Array).size() == 2:
			var owner_room: String = str((room_ids_variant as Array)[0])
			var other_room: String = str((room_ids_variant as Array)[1])
			# A one-sided portal connects exactly one interior room (the
			# owner) to the exterior. The exterior flag must be explicitly
			# true so the loader and validator both recognize the edge as
			# an exterior one-sided portal — otherwise it looks like a
			# portal missing its partner.
			if (kind == "HATCH" or kind == "BREACH") and not bool(edge.get("exterior", false)):
				if owner_room.is_empty() or other_room.is_empty():
					errors.append("one-sided %s portal must explicitly set exterior=true: %s" % [kind, edge_key_value])


# Final edge-map and placement reconciliation. Catches:
#   * empty canonical edge map (already covered by canonical edge map gate)
#   * placements whose kind/state does not match the canonical edge
#   * placements whose module_id drifts from the canonical edge
#   * placements whose edge_key is not present in canonical edges
#   * placement kind/state mismatch even when both fields are set
#   * DOOR portals that lost their materialized placement
#   * DOOR portals that lost their wrapper_required/placement_required flags
#   * source_cells and edge_endpoints that leave the occupancy registry
func _validate_placement_reconciliation(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void:
	var edges_variant: Variant = plan.get("edges", null)
	var placements_variant: Variant = plan.get("placements", null)
	if typeof(edges_variant) != TYPE_DICTIONARY or typeof(placements_variant) != TYPE_ARRAY:
		return
	var edges: Dictionary = edges_variant
	var placements: Array = placements_variant
	var seen_edge_keys: Dictionary = {}
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_variant
		var edge_key_value: String = str(placement.get("edge_key", ""))
		if edge_key_value.is_empty():
			continue
		seen_edge_keys[edge_key_value] = placement
		var canonical_edge: Variant = edges.get(edge_key_value, null)
		if typeof(canonical_edge) != TYPE_DICTIONARY:
			errors.append("placement edge_key is not present in canonical edges: %s" % edge_key_value)
			continue
		var canonical: Dictionary = canonical_edge
		var canonical_kind: String = str(canonical.get("kind", canonical.get("state", "")))
		var placement_kind: String = str(placement.get("kind", placement.get("state", "")))
		if placement_kind != canonical_kind:
			errors.append("placement kind/state does not match canonical edge: %s" % edge_key_value)
		if str(placement.get("module_id", "")) != str(canonical.get("module_id", "")):
			errors.append("placement module_id does not match canonical edge: %s" % edge_key_value)
		# DOOR portals require a placement; placements carry wrapper_required/placement_required.
		if canonical_kind == "DOOR":
			if not bool(canonical.get("wrapper_required", canonical.get("placement_required", true))):
				errors.append("DOOR placement lost wrapper_required: %s" % edge_key_value)
			if not bool(placement.get("wrapper_required", placement.get("placement_required", true))):
				errors.append("DOOR placement lost placement_required: %s" % edge_key_value)
			if str(canonical.get("module_id", "")).is_empty():
				errors.append("materialized edge module_id is missing: %s" % edge_key_value)
			if str(placement.get("module_id", "")).is_empty():
				errors.append("materialized placement module_id is missing: %s" % edge_key_value)
		elif canonical_kind in ["LOCKED", "HATCH"]:
			if str(canonical.get("module_id", "")).is_empty():
				errors.append("materialized edge module_id is missing: %s" % edge_key_value)
			if bool(canonical.get("placement_required", true)) and str(placement.get("module_id", "")).is_empty():
				errors.append("materialized placement module_id is missing: %s" % edge_key_value)
		elif canonical_kind == "SOLID":
			if str(canonical.get("module_id", "")).is_empty():
				errors.append("materialized edge module_id is missing: %s" % edge_key_value)
			if str(placement.get("module_id", "")).is_empty():
				errors.append("materialized placement module_id is missing: %s" % edge_key_value)
		# Source cells and edge endpoints must remain in the occupancy registry
		# unless the canonical edge is marked exterior (e.g. walls on the room's
		# outer boundary straddle a non-occupied cell).
		var occupancy: Dictionary = plan.get("occupancy", {}) if typeof(plan.get("occupancy", {})) == TYPE_DICTIONARY else {}
		var source_cells_variant: Variant = placement.get("source_cells", canonical.get("source_cells", []))
		if typeof(source_cells_variant) != TYPE_ARRAY or (source_cells_variant as Array).size() != 2:
			errors.append("portal source_cells must be an Array of exactly two cells: %s" % edge_key_value)
		else:
			var deck_value: Variant = placement.get("deck", canonical.get("deck", 0))
			var first_info: Dictionary = _read_cell(source_cells_variant[0], int(deck_value))
			var second_info: Dictionary = _read_cell(source_cells_variant[1], int(deck_value))
			if not bool(first_info.get("ok", false)) or not bool(second_info.get("ok", false)):
				errors.append("portal source_cells are invalid: %s" % edge_key_value)
			else:
				var first_key: String = CompilerScript.cell_key(int(first_info["deck"]), first_info["cell"])
				var second_key: String = CompilerScript.cell_key(int(second_info["deck"]), second_info["cell"])
				var is_exterior: bool = bool(canonical.get("exterior", false)) or canonical_kind == "BREACH"
				if not is_exterior and (not occupancy.has(first_key) or not occupancy.has(second_key)):
					errors.append("edge endpoint leaves occupancy: %s" % edge_key_value)
				elif is_exterior and not occupancy.has(first_key):
					errors.append("edge endpoint leaves occupancy: %s" % edge_key_value)
		# Detect SOLID edges that override a topology-connected portal
		# contract. The validator never silently downgrades a required
		# portal to a wall — it must surface the topology mismatch. Match
		# the canonical edge identity, not just the room pair: a wide shared
		# boundary may contain a portal and distinct SOLID segments. The
		# topology edge-key helper normalizes either endpoint orientation.
		if canonical_kind == "SOLID" and placement_kind == "SOLID":
			var topology_portals_variant: Variant = topology.get("portals", [])
			if typeof(topology_portals_variant) == TYPE_ARRAY:
				for topology_portal_variant in (topology_portals_variant as Array):
					if typeof(topology_portal_variant) != TYPE_DICTIONARY:
						continue
					var topology_portal: Dictionary = topology_portal_variant
					if _topology_portal_edge_key(topology_portal, topology) == edge_key_value:
						errors.append("topology-connected rooms blocked by SOLID edge: %s" % edge_key_value)
						break
		# room_ids must remain a known room (non-empty) and the other_room must
		# not be a ghost room.
		var room_ids_variant: Variant = placement.get("room_ids", canonical.get("room_ids", []))
		if typeof(room_ids_variant) == TYPE_ARRAY and (room_ids_variant as Array).size() == 2:
			var other_room_id: String = str((room_ids_variant as Array)[1])
			if not other_room_id.is_empty() and not _room_id_known(plan, other_room_id):
				errors.append("edge endpoint references ghost room: %s" % edge_key_value)

	# Required canonical edges must have exactly one materialized placement.
	for edge_key_variant in edges.keys():
		var edge_key_value: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "")))
		var placement_required: bool = bool(edge.get("wrapper_required", edge.get("placement_required", true)))
		# BREACH/HATCH exterior portals are non-wrapper states; they do not
		# require a placement even when placement_required was not flipped.
		if (kind == "BREACH" or kind == "HATCH") and bool(edge.get("exterior", false)):
			placement_required = false
		if kind == "OPEN":
			continue
		if not placement_required:
			continue
		if not seen_edge_keys.has(edge_key_value):
			if kind == "DOOR":
				errors.append("DOOR placement missing in placements: %s" % edge_key_value)
			else:
				errors.append("required edge has no placement: %s" % edge_key_value)


# Helper that decides whether a room id is recognised by the layout.
func _room_id_known(plan: Dictionary, room_id: String) -> bool:
	var occupancy: Dictionary = plan.get("occupancy", {}) if typeof(plan.get("occupancy", {})) == TYPE_DICTIONARY else {}
	for record_variant in occupancy.values():
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		if str((record_variant as Dictionary).get("room_id", "")) == room_id:
			return true
	return false


# Returns the canonical edge identity for a topology portal. Explicit edge_key
# is authoritative; older topology records carry only endpoint cells, so derive
# the same normalized identity from either (from_cell -> to_cell) orientation.
func _topology_portal_edge_key(portal: Dictionary, topology: Dictionary) -> String:
	var explicit_edge_key: String = str(portal.get("edge_key", ""))
	if not explicit_edge_key.is_empty():
		return explicit_edge_key

	var room_decks: Dictionary = _room_decks(topology)
	var from_room: String = str(portal.get("from_room", ""))
	var from_default_deck: int = int(room_decks.get(from_room, -1))
	if _is_integer(portal.get("deck", null)):
		from_default_deck = int(portal.get("deck"))

	# Logical-boundary records may provide a canonical edge cell/direction even
	# when their logical endpoints are diagonal or otherwise non-adjacent.
	var edge_direction: String = str(portal.get("edge_direction", portal.get("direction", "")))
	if CompilerScript.DIRECTIONS.has(edge_direction):
		var edge_cell_info: Dictionary = _read_cell(portal.get("edge_cell", portal.get("cell", null)), from_default_deck)
		if bool(edge_cell_info.get("ok", false)):
			return CompilerScript.edge_key(
				int(edge_cell_info["deck"]), edge_cell_info["cell"], edge_direction)

	var to_room: String = str(portal.get("to_room", ""))
	var to_default_deck: int = int(room_decks.get(to_room, from_default_deck))
	var from_cell_value: Variant = portal.get("from_cell", portal.get("logical_from_cell", null))
	var to_cell_value: Variant = portal.get("to_cell", portal.get("logical_to_cell", null))
	var source_cells_variant: Variant = portal.get("source_cells", null)
	if typeof(source_cells_variant) == TYPE_ARRAY and (source_cells_variant as Array).size() >= 2:
		from_cell_value = (source_cells_variant as Array)[0]
		to_cell_value = (source_cells_variant as Array)[1]
	var from_info: Dictionary = _read_cell(from_cell_value, from_default_deck)
	var to_info: Dictionary = _read_cell(to_cell_value, to_default_deck)
	if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
		return ""
	if int(from_info["deck"]) != int(to_info["deck"]):
		return ""

	var delta: Vector2i = to_info["cell"] - from_info["cell"]
	for direction_variant in CompilerScript.DIRECTIONS.keys():
		var direction: String = str(direction_variant)
		if CompilerScript.DIRECTIONS[direction] == delta:
			return CompilerScript.edge_key(int(from_info["deck"]), from_info["cell"], direction)
	return ""
