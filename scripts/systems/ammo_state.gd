extends RefCounted
class_name AmmoState

## Per-weapon magazine + timed reload. Combat (threat_manager) fires from the
## magazine; inventory holds the reserve stock. Reload moves reserve -> magazine
## over RELOAD_SECONDS. Domain 5: repurposed from the pre-combat reserve tracker
## (combat consumes ammo from inventory; ammo_state is the loaded-magazine layer).

const RELOAD_SECONDS: float = 1.5

var magazines: Dictionary = {}          # weapon_id (String) -> loaded rounds (int)
var reload_active: bool = false
var reload_remaining: float = 0.0
var reload_weapon_id: String = ""
var reload_target: int = 0              # rounds committed to load on completion
var total_fired: int = 0

func configure(config: Dictionary = {}) -> void:
	magazines.clear()
	reload_active = false
	reload_remaining = 0.0
	reload_weapon_id = ""
	reload_target = 0
	total_fired = 0
	var raw: Variant = config.get("magazines", {})
	if raw is Dictionary:
		for wid in (raw as Dictionary):
			magazines[str(wid)] = max(0, int((raw as Dictionary)[wid]))

func loaded(weapon_id: String) -> int:
	return int(magazines.get(weapon_id, 0))

func spend(weapon_id: String) -> bool:
	var cur: int = loaded(weapon_id)
	if cur <= 0:
		return false
	magazines[weapon_id] = cur - 1
	total_fired += 1
	return true

func is_reloading() -> bool:
	return reload_active

## Begins a reload if not already reloading and there is room + reserve.
## reserve_available is the inventory count the coordinator passes in; the
## coordinator removes reload_target from inventory once this returns true.
func begin_reload(weapon_id: String, magazine_size: int, reserve_available: int) -> bool:
	if reload_active:
		return false
	if weapon_id.is_empty() or magazine_size <= 0:
		return false
	var need: int = magazine_size - loaded(weapon_id)
	var can_load: int = min(need, max(0, reserve_available))
	if can_load <= 0:
		return false
	reload_active = true
	reload_remaining = RELOAD_SECONDS
	reload_weapon_id = weapon_id
	reload_target = can_load
	return true

## Advances the reload timer. On completion, credits the magazine and returns
## {"weapon_id","loaded"} so the coordinator can refresh the HUD (inventory was
## already debited at begin_reload time). Returns {} while idle or mid-reload.
func tick(delta: float) -> Dictionary:
	if not reload_active:
		return {}
	reload_remaining -= delta
	if reload_remaining > 0.0:
		return {}
	var wid: String = reload_weapon_id
	var loaded_count: int = reload_target
	magazines[wid] = loaded(wid) + loaded_count
	reload_active = false
	reload_remaining = 0.0
	reload_weapon_id = ""
	reload_target = 0
	return {"weapon_id": wid, "loaded": loaded_count}

func get_summary() -> Dictionary:
	return {
		"magazines": magazines.duplicate(true),
		"reload_active": reload_active,
		"reload_remaining": reload_remaining,
		"reload_weapon_id": reload_weapon_id,
		"reload_target": reload_target,
		"total_fired": total_fired,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"magazines": summary.get("magazines", {})})
	reload_active = bool(summary.get("reload_active", false))
	reload_remaining = float(summary.get("reload_remaining", 0.0))
	reload_weapon_id = str(summary.get("reload_weapon_id", ""))
	reload_target = int(summary.get("reload_target", 0))
	total_fired = int(summary.get("total_fired", 0))
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var wids: Array = magazines.keys()
	wids.sort()
	for wid in wids:
		lines.append("Mag %s=%d" % [String(wid), int(magazines[wid])])
	if reload_active:
		lines.append("Reloading %s (%.1fs)" % [reload_weapon_id, reload_remaining])
	return lines
