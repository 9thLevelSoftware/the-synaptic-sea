extends RefCounted
class_name StructuralEdgeCompiler

## Data-only compiler for solved room footprints.
##
## The compiler is the sole authority for canonical structural boundaries. It
## first records every explicit occupied cell, then walks each cell boundary
## exactly once by canonical edge key. It never loads scenes or creates nodes.

# All edge identity calls go through StructuralEdgePlan.edge_key() and the
# corresponding pure pose helpers; no floor/module list can mint a boundary.
const StructuralEdgePlanScript := preload("res://scripts/procgen/structural_edge_plan.gd")

const EDGE_SOLID: String = "SOLID"
const EDGE_OPEN: String = "OPEN"
const EDGE_DOOR: String = "DOOR"
const EDGE_LOCKED: String = "LOCKED"
const EDGE_HATCH: String = "HATCH"
const EDGE_BREACH: String = "BREACH"

# Kept here as an explicit compiler contract so wall placement cannot drift
# back into floor/module-list decoration.
const WALL_MODULE_ID: String = "wall_straight_1x1"
const CARDINAL_DIRECTIONS: Array[String] = ["north", "east", "south", "west"]


## Compiles explicit room footprints into canonical occupancy, edges, and
## single-owner structural placement records.
func compile(layout: Dictionary) -> Dictionary:
	var occupancy: Dictionary = {}
	var room_by_cell: Dictionary = {}
	var rooms_by_id: Dictionary = {}
	var errors: Array[String] = []
	var emitted_edge_keys: Dictionary = {}
	var edges: Dictionary = {}
	var placements: Array[Dictionary] = []
	var portal_intents: Dictionary = {}
	var matched_portal_ids: Dictionary = {}

	# 1. Insert every explicit room cell before looking at topology. A cell may
	# not silently change owner when two solved footprints overlap.
	var room_records: Array = _room_records(layout.get("rooms", null), errors)
	for room_variant in room_records:
		if not (room_variant is Dictionary):
			errors.append("room record is not a Dictionary")
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		if room_id.is_empty():
			errors.append("room footprint is missing id")
			continue
		if rooms_by_id.has(room_id):
			errors.append("duplicate room id: %s" % room_id)
			continue
		rooms_by_id[room_id] = room

		var deck_result: Dictionary = _parse_integer(room.get("deck", 0))
		if not bool(deck_result.get("ok", false)):
			errors.append("room %s has an invalid integer deck" % room_id)
			continue
		var deck: int = int(deck_result["value"])
		var raw_cells: Variant = room.get("cells", null)
		if not (raw_cells is Array):
			errors.append("room %s footprint is missing explicit cells" % room_id)
			continue
		for raw_cell in raw_cells:
			var parsed_cell: Dictionary = _parse_cell(raw_cell)
			if not bool(parsed_cell.get("ok", false)):
				errors.append("room %s contains an invalid footprint cell" % room_id)
				continue
			var cell: Vector2i = parsed_cell["cell"]
			var cell_key: String = StructuralEdgePlanScript.cell_key(deck, cell)
			if room_by_cell.has(cell_key):
				errors.append(
					"duplicate occupancy for %s: rooms %s and %s" % [
						cell_key,
						String(room_by_cell[cell_key]),
						room_id,
					]
				)
				continue
			var cell_record: Dictionary = StructuralEdgePlanScript.make_cell(deck, cell, room_id)
			occupancy[cell_key] = cell_record
			room_by_cell[cell_key] = room_id

	# 2. Portal records are intents, not visual instances. Store them by the
	# unordered room pair and optionally constrain them to one required edge.
	_build_portal_intents(layout.get("portals", []), portal_intents, errors)

	# 3-4. Visit every occupied cell and cardinal direction, emitting one edge
	# record per canonical edge key. Shared boundaries are skipped on revisit.
	for cell_key_variant in occupancy.keys():
		var cell_record: Dictionary = occupancy[cell_key_variant]
		var deck: int = int(cell_record.get("deck", 0))
		var cell: Vector2i = cell_record.get("cell", Vector2i.ZERO)
		var room_id: String = String(cell_record.get("room_id", ""))

		for direction in CARDINAL_DIRECTIONS:
			var edge_key: String = StructuralEdgePlanScript.edge_key(deck, cell, direction)
			if emitted_edge_keys.has(edge_key):
				continue
			emitted_edge_keys[edge_key] = true

			var direction_delta: Vector2i = StructuralEdgePlanScript.DIRECTIONS[direction]
			var neighbor_cell: Vector2i = cell + direction_delta
			var neighbor_key: String = StructuralEdgePlanScript.cell_key(deck, neighbor_cell)
			var neighbor_room: String = String(room_by_cell.get(neighbor_key, ""))

			var canonical_cell: Vector2i = cell
			var canonical_direction: String = direction
			var owner_room: String = room_id
			var other_room: String = neighbor_room

			# Pick a deterministic owner for shared inter-room boundaries instead
			# of letting room traversal order choose the pose. Exterior boundaries
			# remain owned by their only occupied side.
			if not neighbor_room.is_empty() and neighbor_room != room_id and neighbor_room < room_id:
				canonical_cell = neighbor_cell
				canonical_direction = String(StructuralEdgePlanScript.OPPOSITE[direction])
				owner_room = neighbor_room
				other_room = room_id

			var state: Dictionary = _edge_state_for(
				owner_room,
				other_room,
				edge_key,
				portal_intents,
			)
			var kind: String = String(state.get("kind", EDGE_SOLID))
			if neighbor_room == room_id:
				# Cells in one room have no structural boundary. Retain the edge
				# record as OPEN so validators/debug exports can see the topology.
				kind = EDGE_OPEN
				state = {"kind": EDGE_OPEN, "matched": false, "intent": {}}

			if bool(state.get("matched", false)):
				var intent: Dictionary = state.get("intent", {})
				matched_portal_ids[String(intent.get("id", ""))] = true

			var edge: Dictionary = StructuralEdgePlanScript.make_edge(
				edge_key,
				kind,
				owner_room,
				other_room,
				canonical_cell,
				canonical_direction,
			)
			if kind == EDGE_SOLID:
				edge["module_id"] = WALL_MODULE_ID
			edge["state"] = kind
			edge["portal"] = bool(state.get("matched", false))
			if bool(state.get("matched", false)):
				var matched_intent: Dictionary = state.get("intent", {})
				edge["portal_intent_id"] = String(matched_intent.get("id", ""))
			var non_wrapper_state: bool = kind == EDGE_OPEN or kind == EDGE_BREACH
			edge["placement_required"] = not non_wrapper_state
			edge["wrapper_required"] = not non_wrapper_state
			edge["exterior"] = (
				kind == EDGE_BREACH or kind == EDGE_HATCH
			) and (owner_room.is_empty() or other_room.is_empty())
			edges[edge_key] = edge

			# OPEN edges and exterior BREACH edges intentionally have no physical
			# wrapper placement. Every wrapper-backed state gets exactly one stable
			# placement keyed by the same edge ID.
			if not non_wrapper_state:
				var placement: Dictionary = edge.duplicate(true)
				placement["id"] = "edge:" + edge_key
				placement["placement_id"] = "placement:" + edge_key
				placements.append(placement)

	# An intent that never found a real adjacent footprint edge must not be
	# silently promoted to a portal. This catches stale graph-only topology.
	for pair_key_variant in portal_intents.keys():
		var intents: Array = portal_intents[pair_key_variant]
		for intent_variant in intents:
			var intent: Dictionary = intent_variant
			var intent_id: String = String(intent.get("id", ""))
			if not matched_portal_ids.has(intent_id):
				errors.append(
					"portal intent has no adjacent footprint edge: %s" % intent_id
				)

	return {
		"occupancy": occupancy,
		"edges": edges,
		"placements": placements,
		"errors": errors,
	}


## Returns the state for one canonical edge. Matching is by unordered room pair;
## a portal with an explicit edge_key only matches that one boundary.
func _edge_state_for(
		owner_room: String,
		other_room: String,
		edge_key: String,
		portal_intents: Dictionary) -> Dictionary:
	var pair_key: String = _room_pair_key(owner_room, other_room)
	var intents: Array = portal_intents.get(pair_key, [])
	for intent_variant in intents:
		var intent: Dictionary = intent_variant
		var required_edge: String = String(intent.get("edge_key", ""))
		if required_edge.is_empty() or required_edge == edge_key:
			return {
				"kind": String(intent.get("kind", EDGE_DOOR)),
				"matched": true,
				"intent": intent,
			}
	return {"kind": EDGE_SOLID, "matched": false, "intent": {}}


func _build_portal_intents(raw_portals: Variant, destination: Dictionary, errors: Array[String]) -> void:
	if not (raw_portals is Array):
		errors.append("layout portals must be an Array")
		return

	var next_id: int = 0
	for portal_variant in raw_portals:
		if not (portal_variant is Dictionary):
			errors.append("portal intent is not a Dictionary")
			continue
		var portal: Dictionary = portal_variant
		var from_room: String = String(portal.get("from_room", portal.get("room_a", portal.get("from", ""))))
		var to_room: String = String(portal.get("to_room", portal.get("room_b", portal.get("to", ""))))
		var kind: String = _portal_kind(
			portal.get("type", portal.get("portal_type", portal.get("kind", "DOOR")))
		)
		if kind.is_empty():
			errors.append(
				"portal intent has unknown type: %s" % String(
					portal.get("type", portal.get("portal_type", portal.get("kind", "")))
				)
			)
			continue

		# A missing endpoint is only meaningful for an explicitly exterior
		# breach/hatch. Reject every other incomplete intent before it can match
		# an exterior edge and accidentally create a traversable portal.
		if (from_room.is_empty() or to_room.is_empty()) and not _is_permitted_exterior_portal(
				kind, from_room, to_room):
			errors.append(
				"portal intent is missing a room endpoint; only an explicit exterior breach or hatch may omit one"
			)
			continue
		if from_room.is_empty() and not to_room.is_empty():
			var swapped: String = from_room
			from_room = to_room
			to_room = swapped
		if from_room.is_empty():
			errors.append("portal intent is missing a room endpoint")
			continue
		var portal_id: String = "portal:%d" % next_id
		next_id += 1
		var edge_result: Dictionary = _portal_edge_key(portal, errors)
		if not bool(edge_result.get("ok", false)):
			# Invalid explicit geometry is not the same as an omitted constraint.
			# Do not retain it, or it could match every edge in this room pair.
			continue
		var intent: Dictionary = {
			"id": portal_id,
			"from_room": from_room,
			"to_room": to_room,
			"kind": kind,
			"required": bool(portal.get("required", false)),
			"edge_key": String(edge_result.get("edge_key", "")),
		}
		var pair_key: String = _room_pair_key(from_room, to_room)
		var pair_intents: Array = destination.get(pair_key, [])
		pair_intents.append(intent)
		destination[pair_key] = pair_intents


## Returns a strict explicit-edge parse result. `ok=true` with an empty key means
## the portal intentionally has no edge constraint; malformed geometry always
## returns `ok=false` so it cannot degrade into an unconstrained portal.
func _portal_edge_key(portal: Dictionary, errors: Array[String]) -> Dictionary:
	var has_explicit_edge: bool = (
		portal.has("edge_key") or portal.has("required_edge") or portal.has("edge")
	)
	if has_explicit_edge:
		var explicit_edge: Variant
		if portal.has("edge_key"):
			explicit_edge = portal["edge_key"]
		elif portal.has("required_edge"):
			explicit_edge = portal["required_edge"]
		else:
			explicit_edge = portal["edge"]

		if explicit_edge is String:
			return _validated_explicit_edge_key(String(explicit_edge), errors)
		if explicit_edge is Dictionary:
			var edge_descriptor: Dictionary = explicit_edge
			if edge_descriptor.has("key") or edge_descriptor.has("edge_key"):
				var nested_key: Variant = edge_descriptor.get(
					"key", edge_descriptor.get("edge_key", null)
				)
				if not nested_key is String:
					errors.append("portal intent has a non-string explicit edge key")
					return {"ok": false, "edge_key": ""}
				return _validated_explicit_edge_key(String(nested_key), errors)
			return _edge_key_from_geometry(edge_descriptor, portal, errors)

		errors.append("portal intent has malformed explicit edge geometry")
		return {"ok": false, "edge_key": ""}

	var has_cell: bool = portal.has("cell") or portal.has("from_cell")
	var has_direction: bool = (
		portal.has("direction") or portal.has("wall") or portal.has("from_direction")
	)
	if not has_cell and not has_direction:
		return {"ok": true, "edge_key": ""}
	if not has_cell or not has_direction:
		errors.append("portal intent has incomplete explicit edge geometry")
		return {"ok": false, "edge_key": ""}
	return _edge_key_from_geometry(portal, portal, errors)


func _edge_key_from_geometry(
		descriptor: Dictionary,
		portal: Dictionary,
		errors: Array[String]) -> Dictionary:
	var raw_cell: Variant
	if descriptor.has("cell"):
		raw_cell = descriptor["cell"]
	else:
		raw_cell = descriptor.get("from_cell", null)
	var raw_direction: Variant
	if descriptor.has("direction"):
		raw_direction = descriptor["direction"]
	elif descriptor.has("wall"):
		raw_direction = descriptor["wall"]
	else:
		raw_direction = descriptor.get("from_direction", null)
	if not raw_direction is String or String(raw_direction).is_empty():
		errors.append("portal intent has an invalid explicit edge direction")
		return {"ok": false, "edge_key": ""}
	var direction: String = String(raw_direction)
	if not StructuralEdgePlanScript.DIRECTIONS.has(direction):
		errors.append("portal intent has an invalid direction: %s" % direction)
		return {"ok": false, "edge_key": ""}
	var parsed_cell: Dictionary = _parse_cell(raw_cell)
	if not bool(parsed_cell.get("ok", false)):
		errors.append("portal intent has an invalid required edge cell")
		return {"ok": false, "edge_key": ""}
	var raw_deck: Variant
	if descriptor.has("deck"):
		raw_deck = descriptor["deck"]
	else:
		raw_deck = portal.get("deck", 0)
	var deck_result: Dictionary = _parse_integer(raw_deck)
	if not bool(deck_result.get("ok", false)):
		errors.append("portal intent has an invalid integer deck")
		return {"ok": false, "edge_key": ""}
	var deck: int = int(deck_result["value"])
	return {
		"ok": true,
		"edge_key": StructuralEdgePlanScript.edge_key(deck, parsed_cell["cell"], direction),
	}


func _validated_explicit_edge_key(raw_edge_key: String, errors: Array[String]) -> Dictionary:
	var parts: PackedStringArray = raw_edge_key.split("|")
	var valid: bool = parts.size() == 4
	if valid:
		valid = (parts[1] == "h" or parts[1] == "v")
	if valid:
		valid = parts[0].is_valid_int() and parts[2].is_valid_int() and parts[3].is_valid_int()
	if valid:
		var normalized: String = "%d|%s|%d|%d" % [
			int(parts[0]),
			parts[1],
			int(parts[2]),
			int(parts[3]),
		]
		valid = normalized == raw_edge_key
	if not valid:
		errors.append("portal intent has malformed explicit edge key: %s" % raw_edge_key)
		return {"ok": false, "edge_key": ""}
	return {"ok": true, "edge_key": raw_edge_key}


func _is_permitted_exterior_portal(kind: String, from_room: String, to_room: String) -> bool:
	var has_one_missing_endpoint: bool = from_room.is_empty() != to_room.is_empty()
	return has_one_missing_endpoint and (kind == EDGE_BREACH or kind == EDGE_HATCH)


func _portal_kind(raw_kind: Variant) -> String:
	var normalized: String = String(raw_kind).to_lower()
	match normalized:
		"solid":
			return EDGE_SOLID
		"open", "passage":
			return EDGE_OPEN
		"door", "portal", "airlock":
			return EDGE_DOOR if normalized != "airlock" else EDGE_HATCH
		"locked", "lock":
			return EDGE_LOCKED
		"hatch":
			return EDGE_HATCH
		"breach":
			return EDGE_BREACH
		_:
			return ""


func _room_pair_key(first: String, second: String) -> String:
	if first < second:
		return first + "|" + second
	return second + "|" + first


func _room_records(raw_rooms: Variant, errors: Array[String]) -> Array:
	var records: Array = []
	if raw_rooms is Array:
		return raw_rooms
	if raw_rooms is Dictionary:
		for room_key in raw_rooms.keys():
			var room_variant: Variant = raw_rooms[room_key]
			if not (room_variant is Dictionary):
				errors.append("room record is not a Dictionary")
				continue
			var room: Dictionary = room_variant.duplicate(true)
			if not room.has("id"):
				room["id"] = String(room_key)
			records.append(room)
		return records
	errors.append("layout rooms must be an Array or Dictionary")
	return records


func _parse_integer(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) == TYPE_INT:
		return {"ok": true, "value": int(raw_value)}
	return {"ok": false, "value": 0}


func _parse_cell(raw_cell: Variant) -> Dictionary:
	if raw_cell is Vector2i:
		return {"ok": true, "cell": raw_cell}
	if raw_cell is Array:
		var values: Array = raw_cell
		if values.size() == 2:
			var x_result: Dictionary = _parse_integer(values[0])
			var y_result: Dictionary = _parse_integer(values[1])
			if bool(x_result.get("ok", false)) and bool(y_result.get("ok", false)):
				return {
					"ok": true,
					"cell": Vector2i(int(x_result["value"]), int(y_result["value"])),
				}
	if raw_cell is Dictionary:
		var value_dict: Dictionary = raw_cell
		if value_dict.has("x") and value_dict.has("y"):
			var x_result: Dictionary = _parse_integer(value_dict["x"])
			var y_result: Dictionary = _parse_integer(value_dict["y"])
			if bool(x_result.get("ok", false)) and bool(y_result.get("ok", false)):
				return {
					"ok": true,
					"cell": Vector2i(int(x_result["value"]), int(y_result["value"])),
				}
	return {"ok": false, "cell": Vector2i.ZERO}
