extends RefCounted
class_name MapFogStateSchema
## Static validation for `MapFogState.configure_for_rooms` payloads
## (REQ-UI-006 / ADR-0033).
##
## A room-graph payload has the following shape:
##
##   {
##     "rooms": ["cargo_01", "corridor_01", "engine_01"],
##     "neighbours": {
##       "cargo_01":    ["corridor_01"],
##       "corridor_01": ["cargo_01", "engine_01"],
##       "engine_01":   ["corridor_01"]
##     }
##   }
##
## The schema rejects:
##   - missing / non-Dictionary root
##   - `rooms` not an Array of strings
##   - `neighbours` not a Dictionary
##   - a neighbour value not an Array of strings
##   - a neighbour room id not declared in `rooms`
##
## Unknown extra fields are ignored (forward-compat).

static func validate(payload: Variant) -> bool:
	if payload == null or typeof(payload) != TYPE_DICTIONARY:
		push_error("MapFogStateSchema: payload must be a Dictionary; got %s" % typeof(payload))
		return false
	var dict: Dictionary = payload
	var rooms_variant: Variant = dict.get("rooms", null)
	if typeof(rooms_variant) != TYPE_ARRAY:
		push_error("MapFogStateSchema: 'rooms' must be an Array")
		return false
	var rooms: Array = rooms_variant
	var room_set: Dictionary = {}
	for room in rooms:
		var room_id: String = str(room)
		if room_id.is_empty():
			push_error("MapFogStateSchema: empty room id in 'rooms'")
			return false
		if room_set.has(room_id):
			push_error("MapFogStateSchema: duplicate room id '%s'" % room_id)
			return false
		room_set[room_id] = true
	var neighbours_variant: Variant = dict.get("neighbours", null)
	if typeof(neighbours_variant) != TYPE_DICTIONARY:
		push_error("MapFogStateSchema: 'neighbours' must be a Dictionary")
		return false
	var neighbours: Dictionary = neighbours_variant
	for room_id in neighbours.keys():
		if not room_set.has(str(room_id)):
			push_error("MapFogStateSchema: neighbour key '%s' not in 'rooms'" % str(room_id))
			return false
		var values: Variant = neighbours[room_id]
		if typeof(values) != TYPE_ARRAY:
			push_error("MapFogStateSchema: neighbours['%s'] must be an Array" % str(room_id))
			return false
		for neighbour in (values as Array):
			var neighbour_id: String = str(neighbour)
			if not room_set.has(neighbour_id):
				push_error("MapFogStateSchema: neighbour '%s' not in 'rooms'" % neighbour_id)
				return false
	return true