extends RefCounted
class_name StructuralPlanValidator

## Fail-closed validator for compiler-produced structural plans.
## Edge placements and floor placements are intentionally separate contracts:
## floors identify occupied cells; edge records identify canonical boundaries.

const CompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const ModularSocketCatalogScript: GDScript = preload("res://scripts/procgen/modular_socket_catalog.gd")
const WalkabilityContractScript: GDScript = preload("res://scripts/procgen/walkability_contract.gd")
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const CEILING_MODULES: Array[String] = ["ceiling_cap_1x1"]
const EDGE_KINDS: Array[String] = ["SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"]
const PROJECTED_WALL_HEIGHT_M: float = 3.0
const PROJECTED_WALL_THICKNESS_M: float = 0.2
const PROJECTED_HALF_SPAN_M: float = 2.0
const PROJECTED_GEOMETRY_EPSILON_M: float = 0.00001


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
	_validate_authoritative_compiler_roundtrip(plan, topology, errors)

	_validate_occupancy_records(occupancy, errors)
	_validate_floor_placements(plan, occupancy, topology, errors, stats)
	_validate_ceiling_placements(plan, occupancy, topology, errors, stats)
	_validate_socket_bindings(plan, errors, stats)
	_validate_not_floor_only(plan, occupancy, errors)
	_validate_edge_placements(edges, placements, errors)
	_validate_projected_half_span_coverage(edges, placements, topology, errors)
	_validate_portal_endpoints(topology, occupancy, edges, errors)
	_validate_dock_navigation_nodes(plan, topology, occupancy, edges, placements, errors)
	_validate_walkable_flood_fill(topology, occupancy, edges, errors)

	return _verdict(errors, stats)


func _validate_authoritative_compiler_roundtrip(
		plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void:
	var expected: Dictionary = CompilerScript.new().compile(topology)
	for field in ["occupancy", "edges", "placements", "floor_placements",
			"ceiling_placements", "socket_bindings", "dock_navigation_nodes", "errors"]:
		if not plan.has(field) or plan[field] != expected.get(field, null):
			errors.append("structural plan does not match authoritative compiler output: %s" % field)


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
	var seen_placement_ids: Dictionary = {}
	var span_owners: Dictionary = {}
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			errors.append("edge placement must be an object")
			continue
		var placement: Dictionary = placement_variant
		var placement_id: String = str(placement.get("placement_id", ""))
		if placement_id.is_empty() or seen_placement_ids.has(placement_id):
			errors.append("missing or duplicate edge placement identity: %s" % placement_id)
			continue
		seen_placement_ids[placement_id] = true
		var edge_key_value: String = str(placement.get("edge_key", ""))
		if edge_key_value.is_empty():
			errors.append("edge placement missing edge_key")
			continue
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
		var edge_keys_variant: Variant = placement.get("edge_keys", null)
		if not edge_keys_variant is Array or (edge_keys_variant as Array).is_empty():
			errors.append("edge placement edge_keys malformed: %s" % placement_id)
			continue
		var edge_keys: Array = edge_keys_variant
		if not edge_keys.has(edge_key_value):
			errors.append("edge placement primary edge absent from edge_keys: %s" % placement_id)
		for bound_edge_key_variant in edge_keys:
			var bound_edge_key: String = str(bound_edge_key_variant)
			var bound_edge_variant: Variant = edges.get(bound_edge_key, null)
			if not bound_edge_variant is Dictionary \
					or str((bound_edge_variant as Dictionary).get("kind", "")) != kind:
				errors.append("edge placement bound edge mismatch: %s" % placement_id)
		var covered_variant: Variant = placement.get("covered_half_spans", null)
		if not covered_variant is Array:
			errors.append("edge placement half-span authority malformed: %s" % placement_id)
		else:
			for span_id_variant in covered_variant:
				var span_id: String = str(span_id_variant)
				if span_id.is_empty() or span_owners.has(span_id):
					errors.append("duplicate or empty half-span placement: %s" % span_id)
				else:
					span_owners[span_id] = placement_id
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
		if kind == "SOLID":
			var expected_spans_variant: Variant = edge.get("half_span_ids", null)
			var span_bindings_variant: Variant = edge.get("half_span_placement_ids", null)
			if not expected_spans_variant is Array \
					or (expected_spans_variant as Array).size() != 2 \
					or not span_bindings_variant is Dictionary:
				errors.append("solid edge half-span authority malformed: %s" % edge_key_value)
				continue
			var expected_spans: Array = expected_spans_variant
			var span_bindings: Dictionary = span_bindings_variant
			if span_bindings.size() != 2:
				errors.append("solid edge half-span coverage incomplete: %s" % edge_key_value)
			for span_id_variant in expected_spans:
				var span_id: String = str(span_id_variant)
				var declared_owner: String = str(span_bindings.get(span_id, ""))
				if str(span_owners.get(span_id, "")) != declared_owner \
						or declared_owner.is_empty() \
						or not seen_placement_ids.has(declared_owner):
					errors.append("solid edge half-span owner mismatch: %s" % span_id)
		elif kind != "OPEN" and bool(edge.get("wrapper_required", edge.get("placement_required", true))):
			var placement_ids_variant: Variant = edge.get("placement_ids", null)
			if not placement_ids_variant is Array \
					or (placement_ids_variant as Array).size() != 1 \
					or not seen_placement_ids.has(str((placement_ids_variant as Array)[0])):
				errors.append("required edge has no exact placement: %s" % edge_key_value)


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
	var edge_position: Vector3 = CompilerScript.edge_world_position(deck, cell, direction)
	var expected_position: Vector3 = edge_position
	var position: Dictionary = _read_position(placement.get("position", null))
	var anchor_kind: String = str(placement.get("anchor_kind", ""))
	var expected_scale := Vector3.ONE
	if anchor_kind == "vertex" or anchor_kind == "half_span":
		var anchor_variant: Variant = placement.get("anchor_vertex", null)
		if not anchor_variant is Array or (anchor_variant as Array).size() != 3 \
				or not _is_integer((anchor_variant as Array)[0]) \
				or not _is_integer((anchor_variant as Array)[1]) \
				or not _is_integer((anchor_variant as Array)[2]):
			errors.append("edge placement anchor vertex malformed: %s" % edge_key_value)
			return
		var anchor: Array = anchor_variant
		var vertex_position := Vector3(
			float(int(anchor[0])) * CompilerScript.CELL_SIZE - CompilerScript.CELL_SIZE * 0.5,
			float(int(anchor[2])) * CompilerScript.DECK_HEIGHT,
			float(int(anchor[1])) * CompilerScript.CELL_SIZE - CompilerScript.CELL_SIZE * 0.5)
		expected_position = vertex_position
		if anchor_kind == "half_span":
			expected_position = vertex_position.lerp(edge_position, 0.5)
			expected_scale = Vector3(0.5, 1.0, 1.0)
	elif anchor_kind != "edge":
		errors.append("edge placement anchor kind malformed: %s" % edge_key_value)
	if not bool(position.get("ok", false)) or not (position["value"] as Vector3).is_equal_approx(expected_position):
		errors.append("edge placement position mismatch: %s" % edge_key_value)
	var scale: Dictionary = _read_position(placement.get("scale", null))
	if not bool(scale.get("ok", false)) or not (scale["value"] as Vector3).is_equal_approx(expected_scale):
		errors.append("edge placement scale mismatch: %s" % edge_key_value)
	var expected_yaw: float = float(CompilerScript.YAW_DEGREES[direction])
	if anchor_kind == "vertex":
		expected_yaw = float(placement.get("yaw_degrees", -1.0))
	if not _is_number(placement.get("yaw_degrees", null)) \
			or fposmod(float(placement.get("yaw_degrees")), 90.0) != 0.0 \
			or (anchor_kind != "vertex" and not is_equal_approx(float(placement.get("yaw_degrees")), expected_yaw)):
		errors.append("edge placement yaw mismatch: %s" % edge_key_value)


func _validate_projected_half_span_coverage(
		edges: Dictionary, placements: Array, topology: Dictionary,
		errors: Array[String]) -> void:
	## Reconstruct span ownership from collision geometry independently of the
	## compiler's declared edge_keys/covered_half_spans. This catches a common-mode
	## compiler error where labels are internally consistent but a ray points at a
	## different physical boundary.
	var catalog = ModularSocketCatalogScript.new()
	var kit_id: String = str(topology.get(
		"structural_kit_id", ModularSocketCatalogScript.DEFAULT_KIT_ID))
	if not catalog.load_kit(kit_id):
		errors.append("projected half-span catalog unavailable: %s" % kit_id)
		return
	var expected: Dictionary = _expected_projected_half_spans(edges, errors)
	var reconstructed_owners: Dictionary = {}
	for placement_variant in placements:
		if not placement_variant is Dictionary:
			continue
		var placement: Dictionary = placement_variant
		if str(placement.get("kind", "")) != "SOLID":
			continue
		var placement_id: String = str(placement.get("placement_id", ""))
		var boxes: Array = catalog.collision_boxes_of(str(placement.get("module_id", "")))
		if boxes.is_empty():
			errors.append("solid placement has no collision projection: %s" % placement_id)
			continue
		var reconstructed: Array[String] = []
		for box_variant in boxes:
			if not box_variant is Dictionary:
				errors.append("solid placement projection box malformed: %s" % placement_id)
				continue
			var segment: Dictionary = _projected_centerline_segment(
				placement, box_variant as Dictionary)
			if not bool(segment.get("ok", false)):
				errors.append("solid placement projection is not a governed wall ray: %s" % placement_id)
				continue
			var matches: Array[String] = _matching_expected_half_spans(segment, expected)
			var expected_count: int = int(roundf(
				float(segment.get("length", 0.0)) / PROJECTED_HALF_SPAN_M))
			if matches.size() != expected_count \
					or not _matched_spans_exactly_fill_segment(segment, matches, expected):
				errors.append("solid placement projection has missing or extra centerline span: %s segment=%s matches=%s" % [
					placement_id, str(segment), str(matches)])
				continue
			for span_id in matches:
				if reconstructed.has(span_id):
					errors.append("solid placement projection duplicates its half-span: %s" % span_id)
				else:
					reconstructed.append(span_id)
		reconstructed.sort()
		var declared_variant: Variant = placement.get("covered_half_spans", null)
		var declared: Array[String] = []
		if declared_variant is Array:
			for span_id_variant in declared_variant:
				declared.append(str(span_id_variant))
			declared.sort()
		if declared != reconstructed:
			errors.append("solid placement declared spans do not match collision projection: %s declared=%s reconstructed=%s" % [
				placement_id, str(declared), str(reconstructed)])
		for span_id in reconstructed:
			if reconstructed_owners.has(span_id):
				errors.append("collision projections duplicate half-span: %s" % span_id)
			else:
				reconstructed_owners[span_id] = placement_id
	for span_id_variant in expected.keys():
		var span_id: String = str(span_id_variant)
		if not reconstructed_owners.has(span_id):
			errors.append("collision projection leaves half-span uncovered: %s" % span_id)


func _expected_projected_half_spans(
		edges: Dictionary, errors: Array[String]) -> Dictionary:
	var expected: Dictionary = {}
	for edge_key_variant in edges.keys():
		var edge_key_value: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if not edge_variant is Dictionary \
				or str((edge_variant as Dictionary).get("kind", "")) != "SOLID":
			continue
		var edge: Dictionary = edge_variant
		var position_result: Dictionary = _read_position(edge.get("position", null))
		var spans_variant: Variant = edge.get("half_span_ids", null)
		var direction: String = str(edge.get("direction", ""))
		if not bool(position_result.get("ok", false)) \
				or not spans_variant is Array or (spans_variant as Array).size() != 2 \
				or direction not in ["north", "east", "south", "west"]:
			errors.append("solid edge cannot define projected half-spans: %s" % edge_key_value)
			continue
		var center: Vector3 = position_result.get("value", Vector3.INF) as Vector3
		var along := Vector3.RIGHT if direction in ["north", "south"] \
			else Vector3(0.0, 0.0, 1.0)
		var endpoint_a: Vector3 = center - along * PROJECTED_HALF_SPAN_M
		var endpoint_b: Vector3 = center + along * PROJECTED_HALF_SPAN_M
		var spans: Array = spans_variant as Array
		expected[str(spans[0])] = _centerline_segment(endpoint_a, center)
		expected[str(spans[1])] = _centerline_segment(center, endpoint_b)
	return expected


func _projected_centerline_segment(
		placement: Dictionary, box: Dictionary) -> Dictionary:
	var placement_transform: Dictionary = _projected_placement_transform(placement)
	var shape_transform: Dictionary = _projected_shape_transform(box)
	var dimensions_result: Dictionary = _read_position(box.get("dimensions", null))
	if not bool(placement_transform.get("ok", false)) \
			or not bool(shape_transform.get("ok", false)) \
			or not bool(dimensions_result.get("ok", false)):
		return {"ok": false}
	var dimensions: Vector3 = dimensions_result.get("value", Vector3.INF) as Vector3
	if not dimensions.is_finite() or dimensions.x <= 0.0 \
			or dimensions.y <= 0.0 or dimensions.z <= 0.0:
		return {"ok": false}
	var world_transform: Transform3D = (placement_transform.get("value") as Transform3D) \
		* (shape_transform.get("value") as Transform3D)
	var bounds: AABB = world_transform * AABB(-dimensions * 0.5, dimensions)
	var deck_y: float = float(int(placement.get("deck", -1))) * CompilerScript.DECK_HEIGHT
	if not _projected_close(bounds.position.y, deck_y) \
			or not _projected_close(bounds.size.y, PROJECTED_WALL_HEIGHT_M):
		return {"ok": false}
	var from_point: Vector3
	var to_point: Vector3
	if _projected_close(bounds.size.z, PROJECTED_WALL_THICKNESS_M) \
			and (_projected_close(bounds.size.x, PROJECTED_HALF_SPAN_M) \
				or _projected_close(bounds.size.x, PROJECTED_HALF_SPAN_M * 2.0)):
		var z: float = bounds.position.z + bounds.size.z * 0.5
		from_point = Vector3(bounds.position.x, deck_y, z)
		to_point = Vector3(bounds.end.x, deck_y, z)
	elif _projected_close(bounds.size.x, PROJECTED_WALL_THICKNESS_M) \
			and (_projected_close(bounds.size.z, PROJECTED_HALF_SPAN_M) \
				or _projected_close(bounds.size.z, PROJECTED_HALF_SPAN_M * 2.0)):
		var x: float = bounds.position.x + bounds.size.x * 0.5
		from_point = Vector3(x, deck_y, bounds.position.z)
		to_point = Vector3(x, deck_y, bounds.end.z)
	else:
		return {"ok": false}
	var segment: Dictionary = _centerline_segment(from_point, to_point)
	segment["ok"] = true
	return segment


func _projected_placement_transform(placement: Dictionary) -> Dictionary:
	var position_result: Dictionary = _read_position(placement.get("position", null))
	var scale_result: Dictionary = _read_position(placement.get("scale", null))
	var yaw_variant: Variant = placement.get("yaw_degrees", null)
	if not bool(position_result.get("ok", false)) \
			or not bool(scale_result.get("ok", false)) or not _is_number(yaw_variant):
		return {"ok": false}
	var position: Vector3 = position_result.get("value", Vector3.INF) as Vector3
	var scale: Vector3 = scale_result.get("value", Vector3.INF) as Vector3
	var yaw: float = fposmod(float(yaw_variant), 360.0)
	if not position.is_finite() or not scale.is_finite() or scale.x <= 0.0 \
			or scale.y <= 0.0 or scale.z <= 0.0 \
			or not _projected_close(fposmod(yaw, 90.0), 0.0):
		return {"ok": false}
	var basis := Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(yaw)) \
		* Basis.from_scale(scale)
	return {"ok": true, "value": Transform3D(basis, position)}


func _projected_shape_transform(box: Dictionary) -> Dictionary:
	var basis_variant: Variant = box.get("basis", null)
	var origin_result: Dictionary = _read_position(box.get("origin", null))
	if not basis_variant is Array or (basis_variant as Array).size() != 9 \
			or not bool(origin_result.get("ok", false)):
		return {"ok": false}
	var values: Array = basis_variant as Array
	for value in values:
		if not _is_number(value):
			return {"ok": false}
	var basis := Basis(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3]), float(values[4]), float(values[5])),
		Vector3(float(values[6]), float(values[7]), float(values[8])))
	var origin: Vector3 = origin_result.get("value", Vector3.INF) as Vector3
	if not basis.is_finite() or not origin.is_finite():
		return {"ok": false}
	return {"ok": true, "value": Transform3D(basis, origin)}


func _centerline_segment(from_point: Vector3, to_point: Vector3) -> Dictionary:
	var horizontal: bool = _projected_close(from_point.z, to_point.z)
	return {
		"axis": "h" if horizontal else "v",
		"coordinate": from_point.z if horizontal else from_point.x,
		"minimum": minf(from_point.x, to_point.x) if horizontal \
			else minf(from_point.z, to_point.z),
		"maximum": maxf(from_point.x, to_point.x) if horizontal \
			else maxf(from_point.z, to_point.z),
		"y": from_point.y,
		"length": from_point.distance_to(to_point),
	}


func _matching_expected_half_spans(
		segment: Dictionary, expected: Dictionary) -> Array[String]:
	var matches: Array[String] = []
	for span_id_variant in expected.keys():
		var span_id: String = str(span_id_variant)
		var candidate: Dictionary = expected[span_id_variant]
		if str(candidate.get("axis", "")) == str(segment.get("axis", "")) \
				and _projected_close(float(candidate.get("coordinate", INF)),
					float(segment.get("coordinate", -INF))) \
				and _projected_close(float(candidate.get("y", INF)),
					float(segment.get("y", -INF))) \
				and float(candidate.get("minimum", -INF)) \
					>= float(segment.get("minimum", INF)) - PROJECTED_GEOMETRY_EPSILON_M \
				and float(candidate.get("maximum", INF)) \
					<= float(segment.get("maximum", -INF)) + PROJECTED_GEOMETRY_EPSILON_M:
			matches.append(span_id)
	matches.sort()
	return matches


func _matched_spans_exactly_fill_segment(
		segment: Dictionary, matches: Array[String], expected: Dictionary) -> bool:
	if matches.is_empty():
		return false
	var minimum: float = INF
	var maximum: float = -INF
	var total_length: float = 0.0
	for span_id in matches:
		var candidate: Dictionary = expected.get(span_id, {}) as Dictionary
		minimum = minf(minimum, float(candidate.get("minimum", INF)))
		maximum = maxf(maximum, float(candidate.get("maximum", -INF)))
		total_length += float(candidate.get("length", 0.0))
	return _projected_close(minimum, float(segment.get("minimum", INF))) \
		and _projected_close(maximum, float(segment.get("maximum", -INF))) \
		and _projected_close(total_length, float(segment.get("length", -INF)))


func _projected_close(left: float, right: float) -> bool:
	return is_finite(left) and is_finite(right) \
		and absf(left - right) <= PROJECTED_GEOMETRY_EPSILON_M


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
		if bool(portal.get("exterior", false)):
			_validate_exterior_portal(portal, from_room, to_room, room_decks,
				occupancy, edges, errors)
			continue
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


func _validate_exterior_portal(
		portal: Dictionary, from_room: String, to_room: String,
		room_decks: Dictionary, occupancy: Dictionary, edges: Dictionary,
		errors: Array[String]) -> void:
	var portal_id: String = str(portal.get("id", ""))
	if portal_id.is_empty() or not room_decks.has(from_room) or not to_room.is_empty():
		errors.append("exterior portal endpoints are invalid: %s" % portal_id)
		return
	var deck: int = int(room_decks[from_room])
	var from_info: Dictionary = _read_cell(portal.get("from_cell", null), deck)
	var to_info: Dictionary = _read_cell(portal.get("to_cell", null), deck)
	if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)) \
			or int(from_info.get("deck", -1)) != deck \
			or int(to_info.get("deck", -1)) != deck:
		errors.append("exterior portal cells are malformed: %s" % portal_id)
		return
	var from_cell: Vector2i = from_info["cell"]
	var to_cell: Vector2i = to_info["cell"]
	var from_key: String = CompilerScript.cell_key(deck, from_cell)
	var to_key: String = CompilerScript.cell_key(deck, to_cell)
	if _occupancy_room(occupancy, from_key) != from_room or occupancy.has(to_key):
		errors.append("exterior portal cells are not owner/interior-to-empty: %s" % portal_id)
		return
	var direction: String = ""
	var delta: Vector2i = to_cell - from_cell
	for candidate in CompilerScript.DIRECTIONS:
		if (CompilerScript.DIRECTIONS[candidate] as Vector2i) == delta:
			direction = str(candidate)
			break
	if direction.is_empty() or str(portal.get("edge_direction", direction)) != direction:
		errors.append("exterior portal cells are not cardinally adjacent: %s" % portal_id)
		return
	var edge_key_value: String = CompilerScript.edge_key(deck, from_cell, direction)
	var edge_variant: Variant = edges.get(edge_key_value, null)
	if not edge_variant is Dictionary:
		errors.append("exterior portal has no canonical edge: %s" % edge_key_value)
		return
	var edge: Dictionary = edge_variant
	if not bool(edge.get("portal", false)) or not bool(edge.get("exterior", false)) \
			or not str(edge.get("other_room", "missing")).is_empty() \
			or str(edge.get("portal_id", "")) != portal_id \
			or str(edge.get("kind", "")) != "DOOR" \
			or str(edge.get("module_id", "")) != CompilerScript.DOOR_MODULE:
		errors.append("exterior portal compiled authority mismatch: %s" % portal_id)


func _validate_dock_navigation_nodes(
		plan: Dictionary, topology: Dictionary, occupancy: Dictionary,
		edges: Dictionary, placements: Array, errors: Array[String]) -> void:
	var source_variant: Variant = topology.get("dock_navigation_nodes_v1", [])
	var compiled_variant: Variant = plan.get("dock_navigation_nodes", [])
	if not source_variant is Array or not compiled_variant is Array \
			or source_variant != compiled_variant:
		errors.append("compiled dock navigation nodes do not match authored source")
		return
	var nodes: Array = compiled_variant
	if nodes.is_empty():
		return
	var exterior_edges: Array[Dictionary] = []
	for edge_variant in edges.values():
		if edge_variant is Dictionary and bool((edge_variant as Dictionary).get(
				"portal", false)) and bool((edge_variant as Dictionary).get(
				"exterior", false)):
			exterior_edges.append(edge_variant as Dictionary)
	if exterior_edges.size() != 1 or nodes.size() != 2:
		errors.append("dock navigation node count does not match exterior portal")
		return
	var edge: Dictionary = exterior_edges[0]
	var deck: int = int(edge.get("deck", -1))
	var cell: Vector2i = edge.get("cell", Vector2i.ZERO) as Vector2i
	var expected: Dictionary = {
		"threshold": "edge:%s" % str(edge.get("edge_key", "")),
		"interior": "floor:%s" % CompilerScript.cell_key(deck, cell),
	}
	var placement_ids: Dictionary = {}
	for placement_variant in placements + (plan.get("floor_placements", []) as Array):
		if placement_variant is Dictionary:
			placement_ids[str((placement_variant as Dictionary).get(
				"placement_id", ""))] = true
	var seen: Dictionary = {}
	for node_variant in nodes:
		if not node_variant is Dictionary:
			errors.append("compiled dock navigation node is malformed")
			continue
		var node: Dictionary = node_variant
		var kind: String = str(node.get("kind", ""))
		var placement_id: String = str(node.get("structural_placement_id", ""))
		var position: Dictionary = _read_position(node.get("local_position", null))
		if seen.has(kind) or not expected.has(kind) \
				or placement_id != str(expected[kind]) or not placement_ids.has(placement_id) \
				or str(node.get("portal_id", "")) != str(edge.get("portal_id", "")) \
				or str(node.get("room_id", "")) != str(edge.get("owner_room", "")) \
				or int(node.get("deck", -1)) != deck \
				or not bool(position.get("ok", false)) \
				or not (position.get("value", Vector3.INF) as Vector3).is_finite():
			errors.append("compiled dock navigation node authority mismatch: %s" % str(
				node.get("node_id", "")))
			continue
		seen[kind] = true
	if seen.size() != 2:
		errors.append("compiled dock navigation node kinds are incomplete")


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
