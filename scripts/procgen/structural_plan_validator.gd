extends RefCounted
class_name StructuralPlanValidator

## Pure, fail-closed validation for the data-only canonical structural plan.
##
## This class deliberately accepts the compiler's plain Dictionary/Array output
## and the original topology dictionary. It never loads a scene or touches the
## scene tree, so generation can reject bad geometry before instantiation.

const StructuralEdgePlanScript: GDScript = preload("res://scripts/procgen/structural_edge_plan.gd")

const EDGE_SOLID: String = "SOLID"
const EDGE_OPEN: String = "OPEN"
const EDGE_DOOR: String = "DOOR"
const EDGE_LOCKED: String = "LOCKED"
const EDGE_HATCH: String = "HATCH"
const EDGE_BREACH: String = "BREACH"
const ALLOWED_EDGE_STATES: Array[String] = [
	EDGE_SOLID,
	EDGE_OPEN,
	EDGE_DOOR,
	EDGE_LOCKED,
	EDGE_HATCH,
	EDGE_BREACH,
]
const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const POSITION_EPSILON: float = 0.001
const CARDINAL_DIRECTIONS: Array[String] = ["north", "east", "south", "west"]


## Validates a compiler plan before any wrapper/scene instantiation.
func validate(plan: Dictionary, topology: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var compiler_errors: Variant = plan.get("errors", [])
	if compiler_errors is Array:
		for compiler_error in compiler_errors:
			errors.append("compiler plan error: %s" % String(compiler_error))
	elif compiler_errors != null:
		errors.append("compiler plan errors must be an Array")

	_validate_semantic_states(plan, errors)
	_validate_occupancy(plan, topology, errors)
	_validate_canonical_edge_map_presence(plan, errors)
	_validate_unique_edge_placements(plan, errors)
	_validate_placement_edge_reconciliation(plan, errors)
	_validate_materialization_records(plan, errors)
	_validate_portal_endpoints(plan, errors)
	_validate_placement_grid_pose(plan, errors)
	_validate_edge_occupancy_consistency(plan, errors)
	var overlap_plan: Dictionary = plan
	if topology.has("rooms"):
		overlap_plan = plan.duplicate(true)
		overlap_plan["rooms"] = topology["rooms"]
	_validate_footprint_overlap(overlap_plan, errors)
	_validate_walkable_reachability(plan, topology, errors)

	var stats: Dictionary = _build_stats(plan, topology, errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"stats": stats,
	}


func _validate_semantic_states(plan: Dictionary, errors: Array[String]) -> void:
	var edges: Variant = plan.get("edges", null)
	if edges is Dictionary:
		for edge_key_variant in edges.keys():
			var edge_variant: Variant = edges[edge_key_variant]
			if edge_variant is Dictionary:
				_validate_semantic_state_record(edge_variant, "edge %s" % String(edge_key_variant), errors)

	var placements: Variant = plan.get("placements", null)
	if placements is Array:
		var index: int = 0
		for placement_variant in placements:
			if placement_variant is Dictionary:
				_validate_semantic_state_record(placement_variant, "placement index %d" % index, errors)
			index += 1


func _validate_semantic_state_record(record: Dictionary, label: String, errors: Array[String]) -> void:
	# The current compiler emits `kind` as the canonical state and older records
	# may omit the redundant `state` alias. Require one semantic field; when both
	# are present they must be equal and both must be from the strict allowlist.
	var has_kind: bool = record.has("kind")
	var has_state: bool = record.has("state")
	if not has_kind and not has_state:
		errors.append("%s semantic state is missing: kind/state is required" % label)
		return
	var kind: String = ""
	var state: String = ""
	if has_kind:
		var raw_kind: Variant = record["kind"]
		if not (raw_kind is String):
			errors.append("%s unknown semantic state: kind must be a string" % label)
		else:
			kind = String(raw_kind)
	if has_state:
		var raw_state: Variant = record["state"]
		if not (raw_state is String):
			errors.append("%s unknown semantic state: state must be a string" % label)
		else:
			state = String(raw_state)
	if kind.is_empty() and not state.is_empty():
		kind = state
	if state.is_empty() and not kind.is_empty():
		state = kind
	if not ALLOWED_EDGE_STATES.has(kind):
		errors.append("%s unknown semantic state kind: %s" % [label, kind])
	if not ALLOWED_EDGE_STATES.has(state):
		errors.append("%s unknown semantic state state: %s" % [label, state])
	if has_kind and has_state and kind != state:
		errors.append("%s kind/state mismatch: kind=%s state=%s" % [label, kind, state])


## A non-empty footprint or any non-OPEN placement must be backed by a
## non-empty canonical edge map. An empty map otherwise makes reconciliation
## vacuously succeed and allows structural geometry to disappear.
func _validate_canonical_edge_map_presence(plan: Dictionary, errors: Array[String]) -> void:
	var occupancy: Variant = plan.get("occupancy", null)
	var has_occupancy: bool = false
	if occupancy is Dictionary or occupancy is Array:
		has_occupancy = occupancy.size() > 0

	var placements: Variant = plan.get("placements", null)
	var has_non_open_placement: bool = false
	if placements is Array:
		for placement_variant in placements:
			if placement_variant is Dictionary and _record_kind(placement_variant) != EDGE_OPEN:
				has_non_open_placement = true
				break

	if not has_occupancy and not has_non_open_placement:
		return

	var edges: Variant = plan.get("edges", null)
	if not (edges is Dictionary) or edges.is_empty():
		errors.append(
			"canonical edge map must be non-empty when occupancy or non-OPEN placements exist"
		)


## Every placement must reconcile to the exact canonical edge record. `key` is
## an edge-record compatibility field only; it is never a placement identity.
func _validate_placement_edge_reconciliation(plan: Dictionary, errors: Array[String]) -> void:
	var edges: Variant = plan.get("edges", null)
	if not (edges is Dictionary):
		return
	var placements: Variant = plan.get("placements", null)
	if not (placements is Array):
		return

	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			continue
		var placement: Dictionary = placement_variant
		if not placement.has("edge_key") or not _has_nonempty_string(placement.get("edge_key", null)):
			errors.append("placement edge_key is required; legacy key fallback is forbidden")
			continue

		var edge_key: String = String(placement["edge_key"])
		if not edges.has(edge_key):
			continue
		var edge_variant: Variant = edges[edge_key]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if not _record_field_matches_exactly(edge, placement, "kind") or not _record_field_matches_exactly(edge, placement, "state"):
			errors.append(
				"placement kind/state does not match canonical edge: %s" % edge_key
			)
		if not _record_field_matches_exactly(edge, placement, "module_id"):
			errors.append(
				"placement module_id does not match canonical edge: %s" % edge_key
			)


func _record_field_matches_exactly(first: Dictionary, second: Dictionary, field: String) -> bool:
	var first_has: bool = first.has(field)
	var second_has: bool = second.has(field)
	if first_has != second_has:
		return false
	if not first_has:
		return true
	var first_value: Variant = first[field]
	var second_value: Variant = second[field]
	if typeof(first_value) != typeof(second_value):
		return false
	return first_value == second_value


## Every wrapper-backed canonical edge owns exactly one non-OPEN placement.
func _validate_unique_edge_placements(plan: Dictionary, errors: Array[String]) -> void:
	var placements: Variant = plan.get("placements", null)
	if not (placements is Array):
		errors.append("structural plan placements must be an Array")
		return

	var edges: Variant = plan.get("edges", {})
	if not (edges is Dictionary):
		errors.append("structural plan edges must be a Dictionary")
		return

	var counts: Dictionary = {}
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			errors.append("structural placement is not a Dictionary")
			continue
		var placement: Dictionary = placement_variant
		var edge_key: String = String(placement.get("edge_key", ""))
		if edge_key.is_empty():
			errors.append("placement is missing edge_key")
			continue
		if not edges.has(edge_key):
			errors.append("placement edge_key is not present in canonical edges: %s" % edge_key)
		if placement.has("key") and String(placement.get("key", "")) != edge_key:
			errors.append("placement key/body drift: %s != %s" % [String(placement.get("key", "")), edge_key])

		var kind: String = _record_kind(placement)
		if kind == EDGE_OPEN:
			continue
		var count: int = int(counts.get(edge_key, 0)) + 1
		counts[edge_key] = count
		if count > 1:
			errors.append(
				"duplicate edge placement: %s; exactly one non-OPEN placement is required" % edge_key
			)

	for edge_key_variant in edges.keys():
		var edge_key: String = String(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if not (edge_variant is Dictionary):
			errors.append("edge record is not a Dictionary: %s" % edge_key)
			continue
		var edge: Dictionary = edge_variant
		var kind: String = _record_kind(edge)
		var requires_placement: bool = _requires_materialization(kind)
		if requires_placement:
			var count: int = int(counts.get(edge_key, 0))
			if count != 1:
				errors.append(
					"edge %s requires exactly one non-OPEN placement; found %d" % [edge_key, count]
				)


func _validate_occupancy(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void:
	var occupancy: Variant = plan.get("occupancy", null)
	if not (occupancy is Dictionary) and not (occupancy is Array):
		errors.append("structural plan occupancy must be a non-empty Dictionary or Array")
		return
	if occupancy.size() == 0:
		errors.append("structural plan occupancy must be a non-empty Dictionary or Array")
		return

	var has_room_registry: bool = topology.has("rooms") and (
		topology.get("rooms") is Array or topology.get("rooms") is Dictionary
	)
	var room_registry: Dictionary = _room_registry(topology.get("rooms", null))
	var topology_cells: Dictionary = _topology_cell_registry(topology.get("rooms", null))
	var occupied_keys: Dictionary = {}

	if occupancy is Dictionary:
		for cell_key_variant in occupancy.keys():
			var label: String = String(cell_key_variant)
			var record_variant: Variant = occupancy[cell_key_variant]
			_validate_occupancy_record(record_variant, label, errors)
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			var parsed: Dictionary = _cell_record_geometry(record)
			if not bool(parsed.get("ok", false)):
				continue
			var expected_key: String = StructuralEdgePlanScript.cell_key(int(parsed["deck"]), parsed["cell"])
			if typeof(cell_key_variant) != TYPE_STRING or label != expected_key:
				errors.append("occupancy cell-key/body drift: map key %s != %s" % [label, expected_key])
			if record.has("key") and String(record.get("key", "")) != expected_key:
				errors.append("occupancy cell-key/body drift: record key %s != %s" % [String(record.get("key", "")), expected_key])
			_occupancy_matches_topology(expected_key, record, topology_cells, has_room_registry, room_registry, errors)
			occupied_keys[expected_key] = true
	else:
		var index: int = 0
		for record_variant in occupancy:
			_validate_occupancy_record(record_variant, "index %d" % index, errors)
			if record_variant is Dictionary:
				var record: Dictionary = record_variant
				var parsed: Dictionary = _cell_record_geometry(record)
				if bool(parsed.get("ok", false)):
					var expected_key: String = StructuralEdgePlanScript.cell_key(int(parsed["deck"]), parsed["cell"])
					if record.has("key") and String(record.get("key", "")) != expected_key:
						errors.append("occupancy cell-key/body drift: record key %s != %s" % [String(record.get("key", "")), expected_key])
					_occupancy_matches_topology(expected_key, record, topology_cells, has_room_registry, room_registry, errors)
					occupied_keys[expected_key] = true
			index += 1

	if not topology_cells.is_empty():
		for topology_key_variant in topology_cells.keys():
			var topology_key: String = String(topology_key_variant)
			if not occupied_keys.has(topology_key):
				errors.append("topology cell has no matching occupancy record: %s" % topology_key)


func _room_registry(raw_rooms: Variant) -> Dictionary:
	var registry: Dictionary = {}
	for room_variant in _room_records(raw_rooms):
		if room_variant is Dictionary:
			var room: Dictionary = room_variant
			var room_id: String = String(room.get("id", ""))
			if not room_id.is_empty():
				registry[room_id] = room
	return registry


func _topology_cell_registry(raw_rooms: Variant) -> Dictionary:
	var registry: Dictionary = {}
	for room_variant in _room_records(raw_rooms):
		if not room_variant is Dictionary:
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		var deck_result: Dictionary = _parse_integer(room.get("deck", null))
		var raw_cells: Variant = room.get("cells", null)
		if room_id.is_empty() or not bool(deck_result.get("ok", false)) or not (raw_cells is Array):
			continue
		for raw_cell in raw_cells:
			var cell_result: Dictionary = _parse_cell(raw_cell)
			if not bool(cell_result.get("ok", false)):
				continue
			var cell: Vector2i = cell_result["cell"]
			var key: String = StructuralEdgePlanScript.cell_key(int(deck_result["value"]), cell)
			registry[key] = {"room_id": room_id, "deck": int(deck_result["value"]), "cell": cell}
	return registry


func _occupancy_matches_topology(
		cell_key: String,
		record: Dictionary,
		topology_cells: Dictionary,
		has_room_registry: bool,
		room_registry: Dictionary,
		errors: Array[String]) -> void:
	var room_id: String = String(record.get("room_id", ""))
	if has_room_registry and not room_registry.has(room_id):
		errors.append("occupancy record has unknown room_id: %s" % room_id)
	if topology_cells.is_empty():
		return
	if not topology_cells.has(cell_key):
		errors.append("occupied cell has no matching cell record in topology: %s" % cell_key)
		return
	var topology_record: Dictionary = topology_cells[cell_key]
	if String(topology_record.get("room_id", "")) != room_id:
		errors.append(
			"occupied cell room_id does not match topology cell record: %s != %s for %s" % [room_id, String(topology_record.get("room_id", "")), cell_key]
		)


func _validate_occupancy_record(record_variant: Variant, label: String, errors: Array[String]) -> void:
	if not (record_variant is Dictionary):
		errors.append("occupancy record is not a Dictionary: %s" % label)
		return
	var record: Dictionary = record_variant
	var parsed: Dictionary = _cell_record_geometry(record)
	if not bool(parsed.get("ok", false)):
		errors.append(
			"occupancy record is malformed: %s; integer deck and cell are required" % label
		)
		return
	if not _has_nonempty_string(record.get("room_id", null)):
		errors.append("occupancy record is malformed: %s; nonempty room_id is required" % label)


func _validate_materialization_records(plan: Dictionary, errors: Array[String]) -> void:
	var edges: Variant = plan.get("edges", null)
	if edges is Dictionary:
		for edge_key_variant in edges.keys():
			var edge_variant: Variant = edges[edge_key_variant]
			if not (edge_variant is Dictionary):
				continue
			var edge: Dictionary = edge_variant
			var kind: String = _record_kind(edge)
			if _requires_materialization(kind) and not _has_nonempty_string(edge.get("module_id", null)):
				errors.append(
					"materialized edge module_id is missing: %s" % String(edge_key_variant)
				)

	var placements: Variant = plan.get("placements", null)
	if not (placements is Array):
		return
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			continue
		var placement: Dictionary = placement_variant
		var kind: String = _record_kind(placement)
		if _requires_materialization(kind) and not _has_nonempty_string(placement.get("module_id", null)):
			errors.append(
				"materialized placement module_id is missing: %s" % String(
					placement.get("edge_key", "")
				)
			)


## exterior BREACH/HATCH records may have one room side and one exterior side.
func _validate_portal_endpoints(plan: Dictionary, errors: Array[String]) -> void:
	var edges: Variant = plan.get("edges", {})
	if not (edges is Dictionary):
		return
	for edge_key_variant in edges.keys():
		var edge_variant: Variant = edges[edge_key_variant]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = _record_kind(edge)
		var is_open_portal: bool = kind == EDGE_OPEN and bool(edge.get("portal", false))
		if not _is_portal_kind(kind) and not is_open_portal:
			continue
		var edge_key: String = String(edge.get("edge_key", edge_key_variant))
		var room_ids: Array = _room_ids_for_record(edge)
		var exterior: bool = _is_explicit_exterior(edge, kind, room_ids)
		var is_one_sided_hatch_or_breach: bool = (
			(kind == EDGE_BREACH or kind == EDGE_HATCH)
			and _nonempty_room_count(room_ids) == 1
		)
		if exterior:
			if (room_ids.size() != 1 and room_ids.size() != 2) or _nonempty_room_count(room_ids) != 1:
				errors.append(
					"portal endpoints are not reciprocal: %s; exterior BREACH/HATCH requires exactly one room side" % edge_key
				)
		elif is_one_sided_hatch_or_breach:
			errors.append(
				"one-sided %s portal must explicitly set exterior=true: %s" % [kind, edge_key]
			)
		elif room_ids.size() != 2 or room_ids[0].is_empty() or room_ids[1].is_empty() or room_ids[0] == room_ids[1]:
			errors.append(
				"portal endpoints are not reciprocal: %s; exactly two reciprocal room sides are required" % edge_key
			)

		_validate_portal_source_cells(edge_key, edge, errors)

		var endpoint_data: Variant = edge.get("endpoints", edge.get("portal_endpoints", null))
		if endpoint_data != null:
			_validate_explicit_endpoint_normals(edge_key, endpoint_data, errors)
		else:
			var direction: String = String(edge.get("direction", ""))
			var opposite_direction: String = String(edge.get("opposite_direction", ""))
			if not _is_direction(direction) or String(StructuralEdgePlanScript.OPPOSITE.get(direction, "")) != opposite_direction:
				errors.append(
					"opposed portal normals are invalid for %s; canonical direction/opposite_direction are required" % edge_key
			)
		var normals: Variant = edge.get("normals", null)
		if normals != null:
			_validate_explicit_endpoint_normals(edge_key, normals, errors)


func _validate_portal_source_cells(edge_key: String, edge: Dictionary, errors: Array[String]) -> void:
	_validate_source_edge_correspondence(edge_key, edge, errors, "portal")


func _validate_source_edge_correspondence(
		edge_key: String,
		record: Dictionary,
		errors: Array[String],
		record_label: String) -> void:
	var raw_source_cells: Variant = record.get("source_cells", null)
	if not (raw_source_cells is Array) or raw_source_cells.size() != 2:
		errors.append(
			"%s source_cells must be an Array of exactly two cells: %s" % [record_label, edge_key]
		)
		return

	var first_result: Dictionary = _parse_cell(raw_source_cells[0])
	var second_result: Dictionary = _parse_cell(raw_source_cells[1])
	if not bool(first_result.get("ok", false)) or not bool(second_result.get("ok", false)):
		errors.append(
			"%s source_cells are invalid: %s; both cells must be integer Vector2i values" % [record_label, edge_key]
		)
		return

	var direction: String = String(record.get("direction", ""))
	if not _is_direction(direction):
		errors.append(
			"%s source_cells cannot be checked without a declared cardinal edge direction: %s" % [record_label, edge_key]
		)
		return

	var source_a: Vector2i = first_result["cell"]
	var source_b: Vector2i = second_result["cell"]
	var expected_second: Vector2i = source_a + StructuralEdgePlanScript.DIRECTIONS[direction]
	if source_b != expected_second:
		errors.append(
			"%s source_cells are not adjacent across declared edge: %s" % [record_label, edge_key]
		)

	var deck_result: Dictionary = _parse_integer(record.get("deck", null))
	if not bool(deck_result.get("ok", false)):
		errors.append(
			"%s source/deck does not match edge record: deck must be an integer for %s" % [record_label, edge_key]
		)
		return
	var deck: int = int(deck_result["value"])
	var edge_key_deck_result: Dictionary = _edge_key_deck(edge_key)
	if not bool(edge_key_deck_result.get("ok", false)):
		errors.append(
			"%s source/deck does not match declared edge: invalid edge_key %s" % [record_label, edge_key]
		)
	else:
		var declared_deck: int = int(edge_key_deck_result["value"])
		if deck != declared_deck:
			errors.append(
				"%s source/deck does not match declared edge: %d != %d for %s" % [record_label, deck, declared_deck, edge_key]
			)

	var canonical_edge_key: String = StructuralEdgePlanScript.edge_key(deck, source_a, direction)
	if canonical_edge_key != edge_key:
		errors.append(
			"%s source_cells do not match declared edge_key: %s != %s" % [record_label, canonical_edge_key, edge_key]
		)

	var record_cell_result: Dictionary = _parse_cell(record.get("cell", null))
	if not bool(record_cell_result.get("ok", false)):
		errors.append(
			"%s source_cells do not match edge record cell: missing integer cell for %s" % [record_label, edge_key]
		)
	elif record_cell_result["cell"] != source_a:
		errors.append(
			"%s source_cells do not match edge record cell: %s != %s for %s" % [record_label, source_a, record_cell_result["cell"], edge_key]
		)


## Positions and rotations must be the integer-grid canonical pose, not a
## transform inferred from a visual mesh or a sequential floor strip.
func _validate_placement_grid_pose(plan: Dictionary, errors: Array[String]) -> void:
	var placements: Variant = plan.get("placements", null)
	if not (placements is Array):
		return
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			continue
		var placement: Dictionary = placement_variant
		if _record_kind(placement) == EDGE_OPEN:
			continue
		var edge_key: String = String(placement.get("edge_key", ""))
		_validate_source_edge_correspondence(edge_key, placement, errors, "placement")
		var geometry: Dictionary = _placement_geometry(placement)
		if not bool(geometry.get("ok", false)):
			errors.append("placement grid pose is invalid for %s: %s" % [edge_key, String(geometry.get("error", "unknown geometry"))])
			continue

		var canonical_edge_key: String = String(geometry["canonical_edge_key"])
		if edge_key.is_empty() or edge_key != canonical_edge_key:
			errors.append(
				"placement edge_key is not canonical for the cell edge: %s != %s" % [edge_key, canonical_edge_key]
			)

		var raw_yaw: Variant = placement.get("yaw_degrees", null)
		if not _is_number(raw_yaw):
			errors.append("placement yaw is outside canonical pose set {0,90,180,270}: %s" % edge_key)
		else:
			var yaw: float = float(raw_yaw)
			if not _is_canonical_yaw(yaw):
				errors.append("placement yaw is outside canonical pose set {0,90,180,270}: %s" % edge_key)
			elif not is_equal_approx(yaw, float(geometry["expected_yaw"])):
				errors.append(
					"placement yaw does not match canonical edge pose for %s: expected %s" % [edge_key, String(geometry["expected_yaw"])]
				)

		var position_result: Dictionary = _parse_vector3(placement.get("position", null))
		if not bool(position_result.get("ok", false)):
			errors.append("placement position is not on a canonical cell edge: %s" % edge_key)
		else:
			var actual_position: Vector3 = position_result["value"]
			var expected_position: Vector3 = geometry["expected_position"]
			if not actual_position.is_equal_approx(expected_position):
				errors.append(
					"placement position is not aligned to canonical cell edge: %s expected %s got %s" % [edge_key, expected_position, actual_position]
				)


func _validate_edge_occupancy_consistency(plan: Dictionary, errors: Array[String]) -> void:
	var edges: Variant = plan.get("edges", null)
	if not (edges is Dictionary):
		return
	var occupied_cells: Dictionary = _canonical_cells(plan, {})
	for edge_key_variant in edges.keys():
		var edge_key: String = String(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if not edge.has("edge_key") or String(edge.get("edge_key", "")) != edge_key:
			errors.append("edge key/body drift: canonical edge map key %s does not match record edge_key" % edge_key)
		_validate_source_edge_correspondence(edge_key, edge, errors, "edge")

		var source_cells: Array = _source_cells_for_record(edge)
		if source_cells.size() != 2:
			continue
		var first_result: Dictionary = _parse_cell(source_cells[0])
		var second_result: Dictionary = _parse_cell(source_cells[1])
		if not bool(first_result.get("ok", false)) or not bool(second_result.get("ok", false)):
			continue
		var deck_result: Dictionary = _parse_integer(edge.get("deck", null))
		if not bool(deck_result.get("ok", false)):
			continue
		var first_key: String = StructuralEdgePlanScript.cell_key(int(deck_result["value"]), first_result["cell"])
		var second_key: String = StructuralEdgePlanScript.cell_key(int(deck_result["value"]), second_result["cell"])
		var room_ids: Array = _room_ids_for_record(edge)
		var owner_room: String = String(edge.get("owner_room", ""))
		var other_room: String = String(edge.get("other_room", ""))
		if room_ids.size() != 2:
			errors.append("edge endpoint room_ids are inconsistent with owner_room/other_room: %s" % edge_key)
		elif String(room_ids[0]) != owner_room or String(room_ids[1]) != other_room:
			errors.append("edge endpoint room_ids are inconsistent with owner_room/other_room: %s" % edge_key)

		if not occupied_cells.has(first_key):
			errors.append("edge endpoint has no matching occupied cell record: %s" % first_key)
		else:
			var first_record: Dictionary = occupied_cells[first_key]
			if not owner_room.is_empty() and String(first_record.get("room_id", "")) != owner_room:
				errors.append("edge endpoint owner_room does not match occupied cell: %s" % edge_key)

		var second_is_occupied: bool = occupied_cells.has(second_key)
		var exterior: bool = _is_explicit_exterior(edge, _record_kind(edge), room_ids)
		if second_is_occupied:
			var second_record: Dictionary = occupied_cells[second_key]
			var second_room: String = String(second_record.get("room_id", ""))
			if not other_room.is_empty() and second_room != other_room:
				errors.append("edge endpoint other_room does not match occupied cell: %s" % edge_key)
			elif other_room.is_empty() and not exterior:
				errors.append("edge endpoint is occupied but other_room is empty: %s" % edge_key)
		elif not other_room.is_empty():
			errors.append("edge endpoint references an unoccupied other_room: %s" % edge_key)


## Detects duplicate physical occupancy even when a malformed plan uses an Array
## or inconsistent dictionary keys that cannot represent duplicate keys directly.
func _validate_footprint_overlap(plan: Dictionary, errors: Array[String]) -> void:
	var plan_cells: Dictionary = {}
	var occupancy: Variant = plan.get("occupancy", null)
	if occupancy is Dictionary:
		for cell_key_variant in occupancy.keys():
			var record_variant: Variant = occupancy[cell_key_variant]
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			var parsed: Dictionary = _cell_record_geometry(record)
			if not bool(parsed.get("ok", false)):
				continue
			_register_occupied_cell(
				plan_cells,
				int(parsed["deck"]),
				parsed["cell"],
				String(record.get("room_id", "")),
				errors,
			)
	elif occupancy is Array:
			for record_variant in occupancy:
				if not (record_variant is Dictionary):
					continue
				var record: Dictionary = record_variant
				var parsed: Dictionary = _cell_record_geometry(record)
				if bool(parsed.get("ok", false)):
					_register_occupied_cell(
						plan_cells,
						int(parsed["deck"]),
						parsed["cell"],
						String(record.get("room_id", "")),
						errors,
					)
	elif occupancy != null:
		errors.append("structural plan occupancy must be a Dictionary or Array")

	var topology_rooms: Variant = plan.get("rooms", null)
	# The compiler plan normally has no rooms field, so topology is the source of
	# truth for solved footprints. Keeping this fallback also supports direct
	# validator fixtures that place rooms on the plan itself.
	if topology_rooms is Dictionary or topology_rooms is Array:
		_validate_room_footprints(topology_rooms, errors)


## The walkability gate uses a real flood fill over occupied cells, then compares
## the resulting components with topology portal reachability.
func _validate_walkable_reachability(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void:
	var cells: Dictionary = _canonical_cells(plan, topology)
	var components: Array = _flood_fill(cells, plan)
	var room_components: Dictionary = {}
	for component_variant in components:
		var component: Dictionary = component_variant
		var component_id: int = int(component.get("id", 0))
		var rooms: Dictionary = component.get("rooms", {})
		for room_variant in rooms.keys():
			var room_id: String = String(room_variant)
			var ids: Array = room_components.get(room_id, [])
			ids.append(component_id)
			room_components[room_id] = ids

	var topology_pairs: Dictionary = _topology_pairs(topology)
	var edges: Dictionary = plan.get("edges", {}) if plan.get("edges", {}) is Dictionary else {}
	for pair_key_variant in topology_pairs.keys():
		var pair_key: String = String(pair_key_variant)
		var pair: Dictionary = topology_pairs[pair_key_variant]
		var rooms: Array = pair.get("rooms", [])
		if rooms.size() != 2:
			continue
		var first_room: String = String(rooms[0])
		var second_room: String = String(rooms[1])
		var required_edge: String = String(pair.get("edge_key", ""))
		var separated_by_solid: bool = false
		if not required_edge.is_empty() and edges.has(required_edge):
			var required_edge_variant: Variant = edges[required_edge]
			if required_edge_variant is Dictionary:
				var edge: Dictionary = required_edge_variant
				if _record_kind(edge) == EDGE_SOLID:
					separated_by_solid = true
		elif required_edge.is_empty():
			for edge_variant in edges.values():
				if not (edge_variant is Dictionary):
					continue
				var edge: Dictionary = edge_variant
				if _record_kind(edge) != EDGE_SOLID:
					continue
				var edge_rooms: Array = _room_ids_for_record(edge)
				if edge_rooms.size() == 2 and not String(edge_rooms[0]).is_empty() and not String(edge_rooms[1]).is_empty() and _room_pair_key(String(edge_rooms[0]), String(edge_rooms[1])) == pair_key:
					separated_by_solid = true
					break
		if separated_by_solid:
			errors.append(
				"topology-connected rooms separated by SOLID edge: %s" % pair_key
			)
		if bool(pair.get("walkable", true)) and not _rooms_share_component(first_room, second_room, room_components):
			errors.append(
				"topology reachability mismatch: flood_fill cannot connect topology-connected rooms %s" % pair_key
			)

	# A plan must not create a traversable room seam absent from the declared
	# topology. This is the converse half of the flood-fill/topology agreement.
	var actual_cross_room_pairs: Dictionary = _walkable_cross_room_pairs(cells, plan)
	for actual_pair_variant in actual_cross_room_pairs.keys():
		var actual_pair: String = String(actual_pair_variant)
		if not topology_pairs.has(actual_pair):
			errors.append(
				"topology reachability mismatch: flood_fill found undeclared walkable seam %s" % actual_pair
			)


func _build_stats(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> Dictionary:
	var edge_count: int = 0
	var portal_count: int = 0
	var occupancy_count: int = 0
	var placement_count: int = 0
	var edges: Variant = plan.get("edges", {})
	if edges is Dictionary:
		edge_count = edges.size()
		for edge_variant in edges.values():
			if edge_variant is Dictionary and (_is_portal_kind(_record_kind(edge_variant)) or (_record_kind(edge_variant) == EDGE_OPEN and bool(edge_variant.get("portal", false)))):
				portal_count += 1
	var occupancy: Variant = plan.get("occupancy", {})
	if occupancy is Dictionary or occupancy is Array:
		occupancy_count = occupancy.size()
	var placements: Variant = plan.get("placements", [])
	if placements is Array:
		placement_count = placements.size()
	var component_count: int = _flood_fill(_canonical_cells(plan, topology), plan).size()
	return {
		"edge_count": edge_count,
		"portal_count": portal_count,
		"placement_count": placement_count,
		"occupied_cell_count": occupancy_count,
		"walkable_component_count": component_count,
		"error_count": errors.size(),
	}


func _record_kind(record: Dictionary) -> String:
	var raw_kind: String = String(record.get("kind", record.get("state", "")))
	return raw_kind.to_upper()


func _is_portal_kind(kind: String) -> bool:
	return kind == EDGE_DOOR or kind == EDGE_LOCKED or kind == EDGE_HATCH or kind == EDGE_BREACH


func _requires_materialization(kind: String) -> bool:
	return kind == EDGE_SOLID or kind == EDGE_DOOR or kind == EDGE_LOCKED or kind == EDGE_HATCH


func _has_nonempty_string(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


func _is_explicit_exterior(edge: Dictionary, kind: String, room_ids: Array) -> bool:
	if kind != EDGE_BREACH and kind != EDGE_HATCH:
		return false
	var exterior_value: Variant = edge.get("exterior", null)
	return typeof(exterior_value) == TYPE_BOOL and bool(exterior_value)


func _nonempty_room_count(room_ids: Array) -> int:
	var count: int = 0
	for room_variant in room_ids:
		if not String(room_variant).is_empty():
			count += 1
	return count


func _room_ids_for_record(record: Dictionary) -> Array:
	var room_ids: Array = []
	var raw_room_ids: Variant = record.get("room_ids", null)
	if raw_room_ids is Array:
		for room_variant in raw_room_ids:
			room_ids.append(String(room_variant))
		return room_ids
	var owner_room: String = String(record.get("owner_room", ""))
	var other_room: String = String(record.get("other_room", ""))
	if not owner_room.is_empty() or not other_room.is_empty():
		room_ids.append(owner_room)
		room_ids.append(other_room)
	return room_ids


func _source_cells_for_record(record: Dictionary) -> Array:
	var raw_cells: Variant = record.get("source_cells", null)
	if raw_cells is Array:
		return raw_cells
	var result: Array = []
	if record.has("cell"):
		result.append(record["cell"])
	return result


func _validate_explicit_endpoint_normals(edge_key: String, endpoint_data: Variant, errors: Array[String]) -> void:
	if not (endpoint_data is Array) or endpoint_data.size() != 2:
		errors.append(
			"portal endpoints are not reciprocal: %s; exactly two endpoint records are required" % edge_key
		)
		return
	var first: Variant = endpoint_data[0]
	var second: Variant = endpoint_data[1]
	if not (first is Dictionary) or not (second is Dictionary):
		errors.append("portal endpoints are not reciprocal: %s; endpoint records must be Dictionaries" % edge_key)
		return
	var first_direction: String = String(first.get("normal_direction", first.get("direction", "")))
	var second_direction: String = String(second.get("normal_direction", second.get("direction", "")))
	if not _is_direction(first_direction) or not _is_direction(second_direction) or String(StructuralEdgePlanScript.OPPOSITE.get(first_direction, "")) != second_direction:
		errors.append("opposed portal normals are invalid for %s" % edge_key)


func _placement_geometry(placement: Dictionary) -> Dictionary:
	var direction: String = String(placement.get("direction", ""))
	var source_cells: Array = _source_cells_for_record(placement)
	var cell_result: Dictionary = _parse_cell(placement.get("cell", null))
	if not bool(cell_result.get("ok", false)) and not source_cells.is_empty():
		cell_result = _parse_cell(source_cells[0])
	if not bool(cell_result.get("ok", false)) and source_cells.size() == 2:
		var first_result: Dictionary = _parse_cell(source_cells[0])
		var second_result: Dictionary = _parse_cell(source_cells[1])
		if bool(first_result.get("ok", false)) and bool(second_result.get("ok", false)):
			direction = _direction_from_delta(second_result["cell"] - first_result["cell"])
	if not _is_direction(direction):
		return {"ok": false, "error": "missing canonical cardinal direction"}
	if not bool(cell_result.get("ok", false)):
		return {"ok": false, "error": "missing integer source cell"}
	var deck_result: Dictionary = _parse_integer(placement.get("deck", null))
	if not bool(deck_result.get("ok", false)):
		var edge_parts: PackedStringArray = String(placement.get("edge_key", "")).split("|")
		if edge_parts.size() >= 1 and edge_parts[0].is_valid_int():
			deck_result = {"ok": true, "value": int(edge_parts[0])}
	if not bool(deck_result.get("ok", false)):
		return {"ok": false, "error": "missing integer deck"}
	var deck: int = int(deck_result["value"])
	var cell: Vector2i = cell_result["cell"]
	var canonical_edge_key: String = StructuralEdgePlanScript.edge_key(deck, cell, direction)
	return {
		"ok": true,
		"deck": deck,
		"cell": cell,
		"direction": direction,
		"canonical_edge_key": canonical_edge_key,
		"expected_position": StructuralEdgePlanScript.edge_world_position(deck, cell, direction),
		"expected_yaw": float(StructuralEdgePlanScript.YAW_DEGREES[direction]),
	}


func _cell_record_geometry(record: Dictionary) -> Dictionary:
	var cell_result: Dictionary = _parse_cell(record.get("cell", null))
	var deck_result: Dictionary = _parse_integer(record.get("deck", null))
	if not bool(cell_result.get("ok", false)) or not bool(deck_result.get("ok", false)):
		return {"ok": false}
	return {
		"ok": true,
		"cell": cell_result["cell"],
		"deck": int(deck_result["value"]),
	}


func _register_occupied_cell(
		cell_map: Dictionary,
		deck: int,
		cell: Vector2i,
		room_id: String,
		errors: Array[String]) -> void:
	var key: String = StructuralEdgePlanScript.cell_key(deck, cell)
	if cell_map.has(key):
		errors.append(
			"occupied-cell overlap at %s between %s and %s" % [key, String(cell_map[key]), room_id]
		)
		return
	cell_map[key] = room_id


func _validate_room_footprints(raw_rooms: Variant, errors: Array[String]) -> void:
	var room_cells: Dictionary = {}
	for room_variant in _room_records(raw_rooms):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		var deck_result: Dictionary = _parse_integer(room.get("deck", null))
		var raw_cells: Variant = room.get("cells", null)
		if not bool(deck_result.get("ok", false)) or not (raw_cells is Array):
			continue
		for raw_cell in raw_cells:
			var cell_result: Dictionary = _parse_cell(raw_cell)
			if bool(cell_result.get("ok", false)):
				_register_occupied_cell(room_cells, int(deck_result["value"]), cell_result["cell"], room_id, errors)


func _room_records(raw_rooms: Variant) -> Array:
	if raw_rooms is Array:
		return raw_rooms
	var records: Array = []
	if raw_rooms is Dictionary:
		for room_key in raw_rooms.keys():
			var room_variant: Variant = raw_rooms[room_key]
			if not (room_variant is Dictionary):
				continue
			var room: Dictionary = room_variant.duplicate(true)
			if not room.has("id"):
				room["id"] = String(room_key)
			records.append(room)
	return records


func _canonical_cells(plan: Dictionary, topology: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var occupancy: Variant = plan.get("occupancy", null)
	if occupancy is Dictionary:
		for record_variant in occupancy.values():
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			var parsed: Dictionary = _cell_record_geometry(record)
			if bool(parsed.get("ok", false)):
				var key: String = StructuralEdgePlanScript.cell_key(int(parsed["deck"]), parsed["cell"])
				cells[key] = {
					"deck": int(parsed["deck"]),
					"cell": parsed["cell"],
					"room_id": String(record.get("room_id", "")),
				}
	elif occupancy is Array:
		for record_variant in occupancy:
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			var parsed: Dictionary = _cell_record_geometry(record)
			if bool(parsed.get("ok", false)):
				var key: String = StructuralEdgePlanScript.cell_key(int(parsed["deck"]), parsed["cell"])
				cells[key] = {
					"deck": int(parsed["deck"]),
					"cell": parsed["cell"],
					"room_id": String(record.get("room_id", "")),
				}
	if not cells.is_empty():
		return cells
	var rooms: Variant = topology.get("rooms", plan.get("rooms", null))
	for room_variant in _room_records(rooms):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		var deck_result: Dictionary = _parse_integer(room.get("deck", null))
		var raw_cells: Variant = room.get("cells", null)
		if not bool(deck_result.get("ok", false)) or not (raw_cells is Array):
			continue
		for raw_cell in raw_cells:
			var cell_result: Dictionary = _parse_cell(raw_cell)
			if bool(cell_result.get("ok", false)):
				var key: String = StructuralEdgePlanScript.cell_key(int(deck_result["value"]), cell_result["cell"])
				cells[key] = {
					"deck": int(deck_result["value"]),
					"cell": cell_result["cell"],
					"room_id": room_id,
				}
	return cells


func _flood_fill(cells: Dictionary, plan: Dictionary) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	var edges: Dictionary = plan.get("edges", {}) if plan.get("edges", {}) is Dictionary else {}
	for start_key_variant in cells.keys():
		var start_key: String = String(start_key_variant)
		if visited.has(start_key):
			continue
		var component_id: int = components.size()
		var queue: Array = [start_key]
		var queue_index: int = 0
		var component_cells: Dictionary = {}
		var component_rooms: Dictionary = {}
		visited[start_key] = true
		while queue_index < queue.size():
			var current_key: String = String(queue[queue_index])
			queue_index += 1
			var current: Dictionary = cells[current_key]
			component_cells[current_key] = true
			var current_room: String = String(current.get("room_id", ""))
			component_rooms[current_room] = true
			var current_cell: Vector2i = current.get("cell", Vector2i.ZERO)
			var deck: int = int(current.get("deck", 0))
			for direction in CARDINAL_DIRECTIONS:
				var neighbor_cell: Vector2i = current_cell + StructuralEdgePlanScript.DIRECTIONS[direction]
				var neighbor_key: String = StructuralEdgePlanScript.cell_key(deck, neighbor_cell)
				if not cells.has(neighbor_key) or visited.has(neighbor_key):
					continue
				var neighbor: Dictionary = cells[neighbor_key]
				var neighbor_room: String = String(neighbor.get("room_id", ""))
				var crossing_key: String = StructuralEdgePlanScript.edge_key(deck, current_cell, direction)
				var crossing_edge: Variant = edges.get(crossing_key, null)
				if current_room != neighbor_room and not _edge_is_walkable(crossing_edge):
					continue
				visited[neighbor_key] = true
				queue.append(neighbor_key)
		components.append({
			"id": component_id,
			"cells": component_cells,
			"rooms": component_rooms,
		})
	return components


func _edge_is_walkable(edge_variant: Variant) -> bool:
	if not (edge_variant is Dictionary):
		return false
	var edge: Dictionary = edge_variant
	var kind: String = _record_kind(edge)
	return kind == EDGE_OPEN or kind == EDGE_DOOR or kind == EDGE_HATCH or kind == EDGE_BREACH


func _rooms_share_component(first_room: String, second_room: String, room_components: Dictionary) -> bool:
	var first_components: Array = room_components.get(first_room, [])
	var second_components: Array = room_components.get(second_room, [])
	for component_variant in first_components:
		if component_variant in second_components:
			return true
	return false


func _walkable_cross_room_pairs(cells: Dictionary, plan: Dictionary) -> Dictionary:
	var pairs: Dictionary = {}
	var edges: Dictionary = plan.get("edges", {}) if plan.get("edges", {}) is Dictionary else {}
	for cell_key_variant in cells.keys():
		var current_key: String = String(cell_key_variant)
		var current: Dictionary = cells[current_key]
		var current_room: String = String(current.get("room_id", ""))
		var current_cell: Vector2i = current.get("cell", Vector2i.ZERO)
		var deck: int = int(current.get("deck", 0))
		for direction in CARDINAL_DIRECTIONS:
			var neighbor_cell: Vector2i = current_cell + StructuralEdgePlanScript.DIRECTIONS[direction]
			var neighbor_key: String = StructuralEdgePlanScript.cell_key(deck, neighbor_cell)
			if not cells.has(neighbor_key):
				continue
			var neighbor: Dictionary = cells[neighbor_key]
			var neighbor_room: String = String(neighbor.get("room_id", ""))
			if current_room == neighbor_room:
				continue
			var edge_key: String = StructuralEdgePlanScript.edge_key(deck, current_cell, direction)
			var edge: Variant = edges.get(edge_key, null)
			if _edge_is_walkable(edge):
				pairs[_room_pair_key(current_room, neighbor_room)] = true
	return pairs


func _topology_pairs(topology: Dictionary) -> Dictionary:
	var pairs: Dictionary = {}
	for field in ["portals", "connections", "links"]:
		var raw: Variant = topology.get(field, null)
		if raw is Array:
			for item in raw:
				if item is Dictionary:
					_add_topology_pair(pairs, item)
		elif raw is Dictionary:
			for first_key in raw.keys():
				var value: Variant = raw[first_key]
				if value is Array:
					for neighbor in value:
						if neighbor is Dictionary:
							var item: Dictionary = neighbor.duplicate(true)
							if not item.has("from_room"):
								item["from_room"] = String(first_key)
							_add_topology_pair(pairs, item)
				else:
					_add_topology_pair(pairs, {"from_room": String(first_key), "to_room": String(value)})
	var topology_edges: Variant = topology.get("edges", null)
	if topology_edges is Dictionary:
		for edge_variant in topology_edges.values():
			if edge_variant is Dictionary:
				_add_topology_pair(pairs, edge_variant)
	elif topology_edges is Array:
		for edge_variant in topology_edges:
			if edge_variant is Dictionary:
				_add_topology_pair(pairs, edge_variant)
	return pairs


func _add_topology_pair(pairs: Dictionary, record: Dictionary) -> void:
	var first_room: String = String(record.get("from_room", record.get("room_a", record.get("from", ""))))
	var second_room: String = String(record.get("to_room", record.get("room_b", record.get("to", ""))))
	if first_room.is_empty() or second_room.is_empty() or first_room == second_room:
		return
	var raw_kind: String = String(record.get("type", record.get("portal_type", record.get("kind", EDGE_DOOR)))).to_upper()
	if raw_kind == EDGE_SOLID:
		return
	var pair_key: String = _room_pair_key(first_room, second_room)
	var raw_edge_key: Variant = record.get("edge_key", record.get("required_edge", ""))
	var edge_key: String = String(raw_edge_key) if raw_edge_key is String else ""
	pairs[pair_key] = {
		"rooms": [first_room, second_room],
		"edge_key": edge_key,
		"required": bool(record.get("required", false)),
		"walkable": raw_kind != EDGE_LOCKED,
	}


func _room_pair_key(first_room: String, second_room: String) -> String:
	if first_room < second_room:
		return first_room + "|" + second_room
	return second_room + "|" + first_room


func _is_direction(direction: String) -> bool:
	return StructuralEdgePlanScript.DIRECTIONS.has(direction)


func _direction_from_delta(delta: Vector2i) -> String:
	for direction in CARDINAL_DIRECTIONS:
		if StructuralEdgePlanScript.DIRECTIONS[direction] == delta:
			return direction
	return ""


func _is_canonical_yaw(yaw: float) -> bool:
	return is_equal_approx(yaw, 0.0) or is_equal_approx(yaw, 90.0) or is_equal_approx(yaw, 180.0) or is_equal_approx(yaw, 270.0)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _parse_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	return {"ok": false, "value": 0}


func _edge_key_deck(edge_key: String) -> Dictionary:
	var parts: PackedStringArray = edge_key.split("|")
	if parts.size() != 4 or not parts[0].is_valid_int():
		return {"ok": false, "value": 0}
	return {"ok": true, "value": int(parts[0])}


func _parse_cell(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "cell": value}
	if value is Array:
		var values: Array = value
		if values.size() == 2:
			var x_result: Dictionary = _parse_integer(values[0])
			var y_result: Dictionary = _parse_integer(values[1])
			if bool(x_result.get("ok", false)) and bool(y_result.get("ok", false)):
				return {"ok": true, "cell": Vector2i(int(x_result["value"]), int(y_result["value"]))}
	if value is Dictionary:
		var value_dict: Dictionary = value
		if value_dict.has("x") and value_dict.has("y"):
			var x_result: Dictionary = _parse_integer(value_dict["x"])
			var y_result: Dictionary = _parse_integer(value_dict["y"])
			if bool(x_result.get("ok", false)) and bool(y_result.get("ok", false)):
				return {"ok": true, "cell": Vector2i(int(x_result["value"]), int(y_result["value"]))}
	return {"ok": false, "cell": Vector2i.ZERO}


func _parse_vector3(value: Variant) -> Dictionary:
	if value is Vector3:
		return {"ok": true, "value": value}
	if value is Array:
		var values: Array = value
		if values.size() == 3 and _is_number(values[0]) and _is_number(values[1]) and _is_number(values[2]):
			return {"ok": true, "value": Vector3(float(values[0]), float(values[1]), float(values[2]))}
	return {"ok": false, "value": Vector3.ZERO}

