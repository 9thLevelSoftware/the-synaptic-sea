extends RefCounted
class_name AddictionState

## Tracks stimulant tolerance, dependence, and withdrawal windows. The active
## withdrawal debuffs themselves are carried by StatusEffectsState; this model is
## the durable state that decides when to start/stop them.

const TUNING_PATH: String = "res://data/items/addiction_tuning.json"

var tuning: Dictionary = {}
var profiles: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	tuning = _load_tuning()
	profiles.clear()
	var raw: Variant = config.get("profiles", {})
	if raw is Dictionary:
		for item_id in (raw as Dictionary):
			profiles[str(item_id)] = (raw as Dictionary)[item_id]

func record_dose(item_id: String, definition: Dictionary) -> void:
	var profile: Dictionary = _profile_for(item_id)
	profile["tolerance"] = clampf(float(profile.get("tolerance", 0.0)) + float(definition.get("tolerance_gain", 0.25)), 0.0, 5.0)
	profile["dependence"] = clampf(float(profile.get("dependence", 0.0)) + float(definition.get("dependence_gain", 0.34)), 0.0, 10.0)
	profile["withdrawal_duration"] = maxf(float(profile.get("withdrawal_duration", 0.0)), float(definition.get("withdrawal_duration", _default_withdrawal_duration(item_id))))
	profile["withdrawal_effects"] = (definition.get("withdrawal_effects", []) as Array).duplicate() if definition.get("withdrawal_effects", []) is Array else []
	profiles[item_id] = profile

func activate_withdrawal_if_needed(item_id: String, status_effects_state) -> Dictionary:
	var profile: Dictionary = _profile_for(item_id)
	var threshold: float = _withdrawal_threshold(item_id)
	if float(profile.get("dependence", 0.0)) < threshold:
		return {"ok": false, "reason": "below_threshold", "item_id": item_id}
	var duration: float = maxf(float(profile.get("withdrawal_duration", 0.0)), _default_withdrawal_duration(item_id))
	profile["withdrawal_remaining"] = duration
	profiles[item_id] = profile
	var applied: Array[String] = []
	var effects: Variant = profile.get("withdrawal_effects", [])
	if effects is Array and status_effects_state != null:
		for effect_id_variant in effects:
			var effect_id: String = str(effect_id_variant)
			status_effects_state.add_effect(effect_id, duration, 1)
			applied.append(effect_id)
	return {"ok": true, "item_id": item_id, "applied": applied, "duration": duration}

func tick(delta_seconds: float, status_effects_state = null) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	for item_id in profiles.keys():
		var profile: Dictionary = profiles[item_id]
		var tolerance: float = float(profile.get("tolerance", 0.0))
		if tolerance > 0.0:
			profile["tolerance"] = maxf(0.0, tolerance - delta_seconds * 0.01)
			changed = true
		var dependence: float = float(profile.get("dependence", 0.0))
		if dependence > 0.0:
			profile["dependence"] = maxf(0.0, dependence - delta_seconds * 0.002)
			changed = true
		var remaining: float = float(profile.get("withdrawal_remaining", 0.0))
		if remaining > 0.0:
			remaining = maxf(0.0, remaining - delta_seconds)
			profile["withdrawal_remaining"] = remaining
			changed = true
			if remaining <= 0.0 and status_effects_state != null:
				var effects: Variant = profile.get("withdrawal_effects", [])
				if effects is Array:
					for effect_id_variant in effects:
						status_effects_state.remove_effect(str(effect_id_variant), 9999)
		profiles[item_id] = profile
	return changed

func get_tolerance(item_id: String) -> float:
	return float(_profile_for(item_id).get("tolerance", 0.0))

func has_withdrawal() -> bool:
	for item_id in profiles:
		if float((profiles[item_id] as Dictionary).get("withdrawal_remaining", 0.0)) > 0.0:
			return true
	return false

func get_summary() -> Dictionary:
	return {
		"profiles": profiles.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"profiles": summary.get("profiles", {})})
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for item_id in profiles.keys():
		var profile: Dictionary = profiles[item_id]
		var dependence: float = float(profile.get("dependence", 0.0))
		var remaining: float = float(profile.get("withdrawal_remaining", 0.0))
		if dependence > 0.0:
			lines.append("Addiction %s dep=%.2f tol=%.2f" % [String(item_id), dependence, float(profile.get("tolerance", 0.0))])
		if remaining > 0.0:
			lines.append("Withdrawal %s %.1fs" % [String(item_id), remaining])
	return lines

func _profile_for(item_id: String) -> Dictionary:
	var raw: Variant = profiles.get(item_id, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {
		"tolerance": 0.0,
		"dependence": 0.0,
		"withdrawal_remaining": 0.0,
		"withdrawal_duration": _default_withdrawal_duration(item_id),
		"withdrawal_effects": _default_withdrawal_effects(item_id),
	}

func _load_tuning() -> Dictionary:
	if not FileAccess.file_exists(TUNING_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))
	return parsed if parsed is Dictionary else {}

func _withdrawal_threshold(item_id: String) -> float:
	var raw: Variant = tuning.get(item_id, {})
	if raw is Dictionary:
		return float((raw as Dictionary).get("withdrawal_threshold", 1.0))
	return 1.0

func _default_withdrawal_duration(item_id: String) -> float:
	var raw: Variant = tuning.get(item_id, {})
	if raw is Dictionary:
		return float((raw as Dictionary).get("withdrawal_duration", 25.0))
	return 25.0

func _default_withdrawal_effects(item_id: String) -> Array:
	var raw: Variant = tuning.get(item_id, {})
	if raw is Dictionary and (raw as Dictionary).get("withdrawal_effects", []) is Array:
		return ((raw as Dictionary).get("withdrawal_effects", []) as Array).duplicate()
	return []
