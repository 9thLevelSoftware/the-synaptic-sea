extends RefCounted
class_name StatusEffectsState

## Pure registry for active status effects.  Per REQ-SV-005.
## Effects have id, remaining_duration, and stacks.

var effects: Array = []  # Array[Dictionary] { "id": String, "duration": float, "stacks": int }

func configure(config: Dictionary = {}) -> void:
	effects.clear()
	var raw: Variant = config.get("effects", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				add_effect(str(entry.get("id", "")), float(entry.get("duration", 0.0)), int(entry.get("stacks", 1)))

func add_effect(effect_id: String, duration: float, stacks: int = 1) -> bool:
	if effect_id.is_empty() or duration <= 0.0 or stacks <= 0:
		return false
	for e in effects:
		if str(e.get("id", "")) == effect_id:
			e["stacks"] = int(e.get("stacks", 0)) + stacks
			e["duration"] = maxf(float(e.get("duration", 0.0)), duration)
			return true
	effects.append({"id": effect_id, "duration": duration, "stacks": stacks})
	return true

func remove_effect(effect_id: String, stacks: int = 1) -> bool:
	for i in range(effects.size()):
		var e: Dictionary = effects[i]
		if str(e.get("id", "")) == effect_id:
			var current: int = int(e.get("stacks", 0))
			if current <= stacks:
				effects.remove_at(i)
			else:
				e["stacks"] = current - stacks
			return true
	return false

func tick(delta_seconds: float, _context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	var i: int = effects.size() - 1
	while i >= 0:
		var e: Dictionary = effects[i]
		var remaining: float = float(e.get("duration", 0.0)) - delta_seconds
		if remaining <= 0.0:
			effects.remove_at(i)
			changed = true
		else:
			e["duration"] = remaining
			changed = true
		i -= 1
	return changed

func has_effect(effect_id: String) -> bool:
	for e in effects:
		if str(e.get("id", "")) == effect_id:
			return true
	return false

func get_stacks(effect_id: String) -> int:
	for e in effects:
		if str(e.get("id", "")) == effect_id:
			return int(e.get("stacks", 0))
	return 0

## Returns a composite modifier for a given stat key.
## Each effect can contribute a multiplier; default is 1.0.
## Example: get_modifier("stamina_recovery") returns product of all matching effect multipliers.
func get_modifier(stat_key: String) -> float:
	var mult: float = 1.0
	# Hard-coded effect table for the core package.
	for e in effects:
		var id: String = str(e.get("id", ""))
		match id:
			"radiation_sickness":
				if stat_key == "stamina_recovery":
					mult *= 0.75
				if stat_key == "health_recovery":
					mult *= 0.5
			"hunger_weakened":
				if stat_key == "stamina_recovery":
					mult *= 0.5
			"thirst_dazed":
				if stat_key == "vision_clarity":
					mult *= 0.6
			"sanity_fractured":
				if stat_key == "perception_clarity":
					mult *= 0.5
			"stim_focus":
				if stat_key == "stamina_recovery":
					mult *= 1.25
			"stim_haste":
				if stat_key == "stamina_recovery":
					mult *= 1.5
			"stim_steady":
				if stat_key == "stamina_recovery":
					mult *= 1.15
			"withdrawal_shakes", "withdrawal_fatigue":
				if stat_key == "stamina_recovery":
					mult *= 0.5
	return mult

func get_summary() -> Dictionary:
	var out: Array = []
	for e in effects:
		out.append({
			"id": str(e.get("id", "")),
			"duration": float(e.get("duration", 0.0)),
			"stacks": int(e.get("stacks", 0)),
		})
	return {
		"effects": out,
		"count": out.size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var raw: Variant = summary.get("effects", [])
	if raw is Array:
		var new_effects: Array = []
		for entry in raw:
			if entry is Dictionary:
				new_effects.append({
					"id": str(entry.get("id", "")),
					"duration": float(entry.get("duration", 0.0)),
					"stacks": int(entry.get("stacks", 0)),
				})
		if new_effects != effects:
			effects = new_effects
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if effects.is_empty():
		lines.append("Status: none")
		return lines
	for e in effects:
		var id: String = str(e.get("id", ""))
		var stacks: int = int(e.get("stacks", 0))
		var dur: float = float(e.get("duration", 0.0))
		lines.append("Status: %s x%d (%.1fs)" % [id, stacks, dur])
	return lines
