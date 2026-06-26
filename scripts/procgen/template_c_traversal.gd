extends RefCounted
class_name TemplateCTraversal

# TemplateCTraversal — pure validator for Template C and any other
# multi-deck layout. Walks layout.vertical_connections and asserts
# every entry is a real, fully-anchored transition between two
# decks. Returns a stable error_code so smokes can pin failure
# paths and the loader can refuse to spawn a broken ship.
#
# Stable error codes:
#   ""                 — no error, layout is valid (and has >= 1 transition)
#   "no_transitions"   — vertical_connections is empty (only valid for
#                        single-deck templates; the caller decides)
#   "missing_room"     — from_room or to_room is not in layout.rooms
#   "deck_mismatch"    — from_room and to_room have the same deck (not vertical)
#   "cell_missing"     — from_cell or to_cell is not in its room's cells
#   "self_transition"  — from_room == to_room (degenerate)
#
# All checks are pure Dictionary reads; this class never instantiates
# any scene tree state and never logs anything via push_error/push_warning
# (warnings would taint the smoke bundle's strict ERROR/WARNING check).

const ERROR_NONE: String = ""
const ERROR_NO_TRANSITIONS: String = "no_transitions"
const ERROR_MISSING_ROOM: String = "missing_room"
const ERROR_DECK_MISMATCH: String = "deck_mismatch"
const ERROR_CELL_MISSING: String = "cell_missing"
const ERROR_SELF_TRANSITION: String = "self_transition"


# Validates `layout` (a layout.json-shaped Dictionary). Returns a
# Dictionary:
#   {
#     "valid": bool,
#     "error_code": String,    # stable code; "" when valid
#     "error_room": String,    # offending room id when applicable
#     "error_transition": String, # transition id when applicable
#     "transitions_checked": int,
#     "transitions_valid": int,
#   }
#
# A layout with no vertical_connections at all returns valid=true
# (the layout is trivially multi-deck-consistent), but a caller
# that requires vertical transitions can check transitions_valid > 0
# separately.
static func validate(layout: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"error_code": ERROR_NONE,
		"error_room": "",
		"error_transition": "",
		"transitions_checked": 0,
		"transitions_valid": 0,
	}

	var rooms_data: Variant = layout.get("rooms", [])
	if not (rooms_data is Array):
		result["valid"] = false
		result["error_code"] = "no_rooms"
		return result

	# Build room_id -> {deck, cells_set} lookup.
	var room_lookup: Dictionary = {}
	for room in (rooms_data as Array):
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		var cells_raw: Variant = room.get("cells", [])
		var cells_set: Dictionary = {}
		if cells_raw is Array:
			for cell in (cells_raw as Array):
				var key: String = _cell_key(cell)
				cells_set[key] = true
		room_lookup[rid] = {
			"deck": int(room.get("deck", 0)),
			"cells_set": cells_set,
		}

	var vertical_raw: Variant = layout.get("vertical_connections", [])
	if not (vertical_raw is Array) or (vertical_raw as Array).is_empty():
		# No vertical connections is valid for a single-deck template
		# (the serializer only emits vertical_connections for cross-deck
		# adjacencies). Don't mark invalid — just leave
		# transitions_checked at 0.
		return result

	for transition in (vertical_raw as Array):
		if not (transition is Dictionary):
			continue
		result["transitions_checked"] += 1

		var from_room: String = str(transition.get("from_room", ""))
		var to_room: String = str(transition.get("to_room", ""))
		var transition_id: String = str(transition.get("id",
			"%s_to_%s" % [from_room, to_room]))

		if from_room.is_empty() or to_room.is_empty():
			result["valid"] = false
			result["error_code"] = ERROR_MISSING_ROOM
			result["error_room"] = from_room if from_room.is_empty() else to_room
			result["error_transition"] = transition_id
			return result

		if from_room == to_room:
			result["valid"] = false
			result["error_code"] = ERROR_SELF_TRANSITION
			result["error_room"] = from_room
			result["error_transition"] = transition_id
			return result

		if not room_lookup.has(from_room):
			result["valid"] = false
			result["error_code"] = ERROR_MISSING_ROOM
			result["error_room"] = from_room
			result["error_transition"] = transition_id
			return result
		if not room_lookup.has(to_room):
			result["valid"] = false
			result["error_code"] = ERROR_MISSING_ROOM
			result["error_room"] = to_room
			result["error_transition"] = transition_id
			return result

		var from_data: Dictionary = room_lookup[from_room]
		var to_data: Dictionary = room_lookup[to_room]
		var from_deck: int = int(from_data.get("deck", 0))
		var to_deck: int = int(to_data.get("deck", 0))
		if from_deck == to_deck:
			result["valid"] = false
			result["error_code"] = ERROR_DECK_MISMATCH
			result["error_room"] = from_room
			result["error_transition"] = transition_id
			return result

		# from_cell / to_cell — accept Vector2i, [x, y], or [x, y, deck].
		var from_cell: Variant = transition.get("from_cell", null)
		var to_cell: Variant = transition.get("to_cell", null)
		var from_set: Dictionary = from_data.get("cells_set", {})
		var to_set: Dictionary = to_data.get("cells_set", {})

		if from_cell != null:
			var from_xy: Vector2i = _cell_xy(from_cell)
			if not from_set.is_empty() and not from_set.has(_xy_key(from_xy)):
				result["valid"] = false
				result["error_code"] = ERROR_CELL_MISSING
				result["error_room"] = from_room
				result["error_transition"] = transition_id
				return result

		if to_cell != null:
			var to_xy: Vector2i = _cell_xy(to_cell)
			if not to_set.is_empty() and not to_set.has(_xy_key(to_xy)):
				result["valid"] = false
				result["error_code"] = ERROR_CELL_MISSING
				result["error_room"] = to_room
				result["error_transition"] = transition_id
				return result

		result["transitions_valid"] += 1

	return result


# Builds a critical-path room id list from `layout` using the same
# BFS algorithm as LayoutSerializer._build_critical_path(). The
# serializer writes the result into layout.critical_path already;
# this helper recomputes it for cases where a layout lacks the
# cached field (e.g. a unit-test fixture).
static func critical_path(layout: Dictionary) -> Array[String]:
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		return []
	var entry_id: String = str(rooms[0].get("id", ""))
	var dest_id: String = str(rooms[-1].get("id", ""))
	if entry_id.is_empty() or dest_id.is_empty():
		return []

	var adjacencies: Array = layout.get("room_links", [])
	var adj_map: Dictionary = {}
	for link in adjacencies:
		if not (link is Dictionary):
			continue
		var fr: String = str(link.get("from_room", ""))
		var tr: String = str(link.get("to_room", ""))
		if fr.is_empty() or tr.is_empty():
			continue
		if not adj_map.has(fr):
			adj_map[fr] = []
		(adj_map[fr] as Array).append(tr)
		if not adj_map.has(tr):
			adj_map[tr] = []
		(adj_map[tr] as Array).append(fr)

	var visited: Dictionary = {entry_id: ""}
	var queue: Array = [entry_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == dest_id:
			break
		for neighbor in adj_map.get(current, []):
			if not visited.has(neighbor):
				visited[neighbor] = current
				queue.append(neighbor)

	if not visited.has(dest_id):
		return [entry_id]

	var path: Array[String] = []
	var current: String = dest_id
	while not current.is_empty():
		path.insert(0, current)
		current = str(visited.get(current, ""))
	return path


# --- Internal helpers ---

# Convert a layout cell entry (Vector2i, [x,y], or [x,y,deck]) into
# a stable string key for set membership.
static func _cell_key(cell: Variant) -> String:
	if cell is Vector2i:
		return _xy_key(cell)
	if cell is Array:
		var arr: Array = cell
		if arr.size() >= 2:
			return "%d,%d" % [int(arr[0]), int(arr[1])]
	return ""

# Convert to a Vector2i cell from a layout cell entry. Strips deck.
static func _cell_xy(cell: Variant) -> Vector2i:
	if cell is Vector2i:
		return cell
	if cell is Array:
		var arr: Array = cell
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

static func _xy_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]
