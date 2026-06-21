extends RefCounted
class_name WorldSnapshot

## Top-level world save. Wraps the SargassoWorld summary, the home ship's
## RunSnapshot (unchanged), a per-derelict slice registry keyed by marker_id,
## the player's current location, and the in-ship player position. Pure data;
## serialization-agnostic (SaveLoadService owns file I/O). Geometry is never
## stored — derelict hulls regenerate deterministically from seed; only mutable
## state rides the per-ship slices.

const WORLD_SLICE_VERSION: String = "world-1"

var world_summary: Dictionary = {}
var home_ship: Dictionary = {}                  # a RunSnapshot.to_dict()
var visited_ships: Dictionary = {}              # marker_id -> ShipInstance.get_summary()
var current_location: String = ""               # "" = home ship, else marker_id
var player_position_in_ship: Array = [0.0, 0.0, 0.0]
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

func to_dict() -> Dictionary:
	return {
		"world_summary": world_summary.duplicate(true),
		"home_ship": home_ship.duplicate(true),
		"visited_ships": visited_ships.duplicate(true),
		"current_location": current_location,
		"player_position_in_ship": player_position_in_ship.duplicate(),
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}

## Reconstructs a WorldSnapshot. Returns null when data is missing/not a dict,
## or when either version marker does not match (per ADR-0007/0012: incompatible
## saves are rejected so load always falls back to a fresh run).
static func from_dict(data: Variant, expected_world_version: String, expected_godot_version: String) -> WorldSnapshot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data as Dictionary
	if dict.is_empty():
		return null
	if str(dict.get("slice_version", "")) != expected_world_version:
		return null
	if str(dict.get("godot_version", "")) != expected_godot_version:
		return null
	var ws := WorldSnapshot.new()
	ws.world_summary = _deep_copy_dict(dict.get("world_summary", {}))
	ws.home_ship = _deep_copy_dict(dict.get("home_ship", {}))
	ws.visited_ships = _deep_copy_dict(dict.get("visited_ships", {}))
	ws.current_location = str(dict.get("current_location", ""))
	var pos = dict.get("player_position_in_ship", [0.0, 0.0, 0.0])
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		var pa: Array = pos as Array
		ws.player_position_in_ship = [float(pa[0]), float(pa[1]), float(pa[2])]
	ws.slice_version = str(dict.get("slice_version", ""))
	ws.godot_version = str(dict.get("godot_version", ""))
	ws.saved_at = str(dict.get("saved_at", ""))
	return ws

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
