extends RefCounted
class_name MapFogState
## Pure fog-of-war map state (REQ-UI-006 / ADR-0033).
##
## Owns:
##   - `_rooms` — `{room_id: {revealed: bool, discovered: bool}}`
##   - `_neighbours` — `{room_id: [adjacent_room_id, ...]}`
##   - `_tracked_room_id` — current player location
##
## Pure-model-first: no scene-tree access. The MinimapPanel subscribes
## to `state_changed` and re-renders.
##
## Headless round-trip via `get_summary` / `apply_summary` keeps the
## fog state recoverable through save/load.

signal state_changed(room_id: String)

const MapFogStateSchemaScript := preload("res://scripts/schemas/map_fog_schema.gd")

const SCHEMA_VERSION: String = "map-fog-state-1"
const SAVE_KEY: String = "map_fog_state"

var _rooms: Dictionary = {}                # room_id -> {revealed, discovered}
var _neighbours: Dictionary = {}           # room_id -> Array of neighbour ids
var _room_ids: Array = []                  # ordered list of room ids
var _tracked_room_id: String = ""

func configure_for_rooms(room_payload: Dictionary) -> bool:
	if not MapFogStateSchemaScript.validate(room_payload):
		return false
	_rooms.clear()
	_neighbours.clear()
	_room_ids.clear()
	var dict: Dictionary = room_payload
	for room in (dict.get("rooms", []) as Array):
		var room_id: String = str(room)
		_room_ids.append(room_id)
		_rooms[room_id] = {"revealed": false, "discovered": false}
	var neighbours: Dictionary = dict.get("neighbours", {})
	for room_id in neighbours.keys():
		var neighbours_for_room: Array = []
		for neighbour in (neighbours[room_id] as Array):
			neighbours_for_room.append(str(neighbour))
		_neighbours[String(room_id)] = neighbours_for_room
	_tracked_room_id = ""
	return true

func get_room_ids() -> Array:
	return _room_ids.duplicate()

func get_room_count() -> int:
	return _room_ids.size()

func is_known_room(room_id: String) -> bool:
	return _rooms.has(room_id)

func is_revealed(room_id: String) -> bool:
	if not is_known_room(room_id):
		return false
	return bool(_rooms[room_id].get("revealed", false))

func is_discovered(room_id: String) -> bool:
	if not is_known_room(room_id):
		return false
	return bool(_rooms[room_id].get("discovered", false))

## Reveal a room and propagate discovery to its neighbours. Returns
## false when the room id is unknown.
func reveal(room_id: String) -> bool:
	if not is_known_room(room_id):
		push_warning("MapFogState: reveal unknown room '%s'" % room_id)
		return false
	_rooms[room_id]["revealed"] = true
	_rooms[room_id]["discovered"] = true
	for neighbour_id in (_neighbours.get(room_id, []) as Array):
		if _rooms.has(neighbour_id):
			_rooms[neighbour_id]["discovered"] = true
	emit_signal("state_changed", room_id)
	return true

## Mark a room as discovered (without revealing). Returns false when
## the room id is unknown.
func discover(room_id: String) -> bool:
	if not is_known_room(room_id):
		push_warning("MapFogState: discover unknown room '%s'" % room_id)
		return false
	if not bool(_rooms[room_id].get("discovered", false)):
		_rooms[room_id]["discovered"] = true
		emit_signal("state_changed", room_id)
	return true

## Set the current player location. Reveals the room (so the player
## sees their own position) and rejects unknown ids.
func track(room_id: String) -> bool:
	if not is_known_room(room_id):
		push_warning("MapFogState: track unknown room '%s'" % room_id)
		return false
	_tracked_room_id = room_id
	reveal(room_id)
	return true

func get_tracked_room_id() -> String:
	return _tracked_room_id

func get_neighbours(room_id: String) -> Array:
	if not is_known_room(room_id):
		return []
	return (_neighbours.get(room_id, []) as Array).duplicate()

## Counts for the status dump.
func get_revealed_count() -> int:
	var count: int = 0
	for room_id in _rooms.keys():
		if bool(_rooms[room_id].get("revealed", false)):
			count += 1
	return count

func get_discovered_count() -> int:
	var count: int = 0
	for room_id in _rooms.keys():
		if bool(_rooms[room_id].get("discovered", false)):
			count += 1
	return count

## Round-trip seam. Unknown rooms are ignored so a save from a
## different ship layout does not blow up the load.
func get_summary() -> Dictionary:
	var rooms_dict: Dictionary = {}
	for room_id in _rooms.keys():
		rooms_dict[String(room_id)] = {
			"revealed": bool(_rooms[room_id].get("revealed", false)),
			"discovered": bool(_rooms[room_id].get("discovered", false)),
		}
	return {
		"schema": SCHEMA_VERSION,
		"room_count": _room_ids.size(),
		"revealed_count": get_revealed_count(),
		"discovered_count": get_discovered_count(),
		"tracked_room_id": _tracked_room_id,
		"rooms": rooms_dict,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	if str(summary.get("schema", "")) != SCHEMA_VERSION:
		return false
	var rooms_variant: Variant = summary.get("rooms", {})
	if typeof(rooms_variant) != TYPE_DICTIONARY:
		return false
	for room_id in (rooms_variant as Dictionary).keys():
		var room_id_s: String = str(room_id)
		if not _rooms.has(room_id_s):
			continue  # ignore rooms not declared in the current layout
		var entry: Variant = rooms_variant[room_id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_dict: Dictionary = entry
		_rooms[room_id_s]["revealed"] = bool(entry_dict.get("revealed", false))
		_rooms[room_id_s]["discovered"] = bool(entry_dict.get("discovered", false))
	var tracked: String = str(summary.get("tracked_room_id", ""))
	if _rooms.has(tracked):
		_tracked_room_id = tracked
	else:
		_tracked_room_id = ""
	emit_signal("state_changed", _tracked_room_id)
	return true

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("MapFogState: rooms=%d revealed=%d discovered=%d tracked=%s" % [
		_room_ids.size(),
		get_revealed_count(),
		get_discovered_count(),
		_tracked_room_id if not _tracked_room_id.is_empty() else "<none>",
	])
	return lines