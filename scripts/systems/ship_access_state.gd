extends RefCounted
class_name ShipAccessState

## Per-ship ownership + access list. Pure data (no scene tree). The multiplayer
## forward seam: one local player this cycle, but owner_id + access_ids + the
## grant/revoke methods generalize to N players. Persisted as a ship-summary
## sub-dict. class_name is declared for tooling; headless callers preload + create().

var owner_id: String = ""
var access_ids: Array[String] = []

static func create() -> ShipAccessState:
	var script: GDScript = load("res://scripts/systems/ship_access_state.gd")
	return script.new()

## Claims an unowned ship for player_id (sets owner + grants access). Returns
## whether player_id now owns it: true if it just claimed or already owned it,
## false if a different player already owns it.
func claim(player_id: String) -> bool:
	if player_id == "":
		return false
	if owner_id == "":
		owner_id = player_id
		_add_access(player_id)
		return true
	return owner_id == player_id

func grant(player_id: String) -> void:
	if player_id != "":
		_add_access(player_id)

func revoke(player_id: String) -> void:
	if player_id == owner_id:
		return   # the owner always retains access
	access_ids.erase(player_id)

func has_access(player_id: String) -> bool:
	return player_id != "" and access_ids.has(player_id)

func _add_access(player_id: String) -> void:
	if not access_ids.has(player_id):
		access_ids.append(player_id)

func get_summary() -> Dictionary:
	return {"owner_id": owner_id, "access_ids": access_ids.duplicate()}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY:
		return false
	owner_id = str((summary as Dictionary).get("owner_id", ""))
	access_ids = []
	var raw: Variant = (summary as Dictionary).get("access_ids", [])
	if typeof(raw) == TYPE_ARRAY:
		for a in (raw as Array):
			_add_access(String(a))
	return true
