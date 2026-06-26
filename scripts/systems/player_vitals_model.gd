extends RefCounted
class_name PlayerVitalsModel

## Pure formatting model for the player-vitals HUD panel (Phase 7 sub-project C).
## Turns raw model numbers (oxygen summary, inventory load, repair channel state)
## into player-facing ASCII status lines. No scene-tree access; no persistence
## (vitals are live-derived each frame). The coordinator feeds it via the setters
## below; the panel renders get_status_lines().

const BLOCKED_DISPLAY_SECONDS: float = 3.0
const DEFAULT_RECOVERY_THRESHOLD: float = 30.0

var _oxygen_summary: Dictionary = {}
var _load_ratio: float = 0.0
var _move_multiplier: float = 1.0
var _weight_saved: float = 0.0
var _repair_channeling: bool = false
var _repair_progress: float = 0.0
var _blocked_reason: String = ""
var _blocked_remaining: float = 0.0

# REQ-SV: survival vitals summaries
var _vitals_summary: Dictionary = {}
var _sanity_summary: Dictionary = {}
var _radiation_summary: Dictionary = {}
var _temperature_summary: Dictionary = {}
var _status_effects_summary: Dictionary = {}

func apply_oxygen_summary(summary: Dictionary) -> void:
	_oxygen_summary = summary.duplicate(true)

func apply_inventory_load(load_ratio: float, move_multiplier: float, weight_saved: float = 0.0) -> void:
	_load_ratio = maxf(0.0, load_ratio)
	_move_multiplier = move_multiplier
	_weight_saved = maxf(0.0, weight_saved)

func set_repair_progress(channeling: bool, progress: float) -> void:
	_repair_channeling = channeling
	_repair_progress = clampf(progress, 0.0, 1.0)

func notify_repair_blocked(reason: String) -> void:
	_blocked_reason = reason
	_blocked_remaining = BLOCKED_DISPLAY_SECONDS

func apply_vitals_summary(summary: Dictionary) -> void:
	_vitals_summary = summary.duplicate(true)

func apply_sanity_summary(summary: Dictionary) -> void:
	_sanity_summary = summary.duplicate(true)

func apply_radiation_summary(summary: Dictionary) -> void:
	_radiation_summary = summary.duplicate(true)

func apply_temperature_summary(summary: Dictionary) -> void:
	_temperature_summary = summary.duplicate(true)

func apply_status_effects_summary(summary: Dictionary) -> void:
	_status_effects_summary = summary.duplicate(true)

func tick(delta: float) -> void:
	if _blocked_remaining > 0.0:
		_blocked_remaining = maxf(0.0, _blocked_remaining - delta)
		if _blocked_remaining <= 0.0:
			_blocked_reason = ""

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_oxygen_line())
	var suit: String = _suit_line()
	if suit != "":
		lines.append(suit)
	lines.append(_load_line())
	var repair: String = _repair_line()
	if repair != "":
		lines.append(repair)
	# REQ-SV: append survival vitals lines
	lines.append_array(_vitals_lines())
	lines.append_array(_sanity_lines())
	lines.append_array(_radiation_lines())
	lines.append_array(_temperature_lines())
	lines.append_array(_status_effects_lines())
	return lines

func get_vitals_summary() -> Dictionary:
	return {
		"oxygen": int(round(float(_oxygen_summary.get("oxygen", 0.0)))),
		"breach_state": _breach_state(),
		"suit_drain_percent": _suit_percent(),
		"load_percent": int(round(_load_ratio * 100.0)),
		"heavy": _load_ratio > 1.0,
		"move_penalty_percent": int(round((1.0 - _move_multiplier) * 100.0)),
		"repair_line": _repair_line(),
		"blocked_active": _blocked_remaining > 0.0 and not _repair_channeling,
		"health": int(round(float(_vitals_summary.get("health", 0.0)))),
		"stamina": int(round(float(_vitals_summary.get("stamina", 0.0)))),
		"hunger": int(round(float(_vitals_summary.get("hunger", 0.0)))),
		"thirst": int(round(float(_vitals_summary.get("thirst", 0.0)))),
		"sanity": int(round(float(_sanity_summary.get("sanity", 0.0)))),
		"radiation": int(round(float(_radiation_summary.get("radiation", 0.0)))),
		"temperature": float(_temperature_summary.get("temperature", 22.0)),
		"status_effects_count": int(_status_effects_summary.get("count", 0)),
	}

# --- line composers ---

func _oxygen_line() -> String:
	var oxygen: int = int(round(float(_oxygen_summary.get("oxygen", 0.0))))
	var line: String = "Oxygen: %d" % oxygen
	var state: String = _breach_state()
	if state == "breach":
		line += " (BREACH)"
	elif state == "sealed":
		line += " (SEALED)"
	var threshold: float = float(_oxygen_summary.get("recovery_threshold", DEFAULT_RECOVERY_THRESHOLD))
	if float(oxygen) <= threshold:
		line += " LOW"
	return line

func _breach_state() -> String:
	if bool(_oxygen_summary.get("breach_sealed", false)):
		return "sealed"
	if bool(_oxygen_summary.get("breach_open", false)):
		return "breach"
	return "closed"

func _suit_percent() -> int:
	var mult: float = float(_oxygen_summary.get("equipment_drain_multiplier", 1.0))
	return int(round((1.0 - mult) * 100.0))

func _suit_line() -> String:
	var mult: float = float(_oxygen_summary.get("equipment_drain_multiplier", 1.0))
	if mult >= 1.0:
		return ""
	return "Suit: -%d%% O2 drain" % _suit_percent()

func _load_line() -> String:
	var pct: int = int(round(_load_ratio * 100.0))
	var saved_kg: int = int(round(_weight_saved))
	var suffix: String = " (bags -%dkg)" % saved_kg if saved_kg >= 1 else ""
	if _load_ratio > 1.0:
		var penalty: int = int(round((1.0 - _move_multiplier) * 100.0))
		return "Load: %d%% HEAVY (-%d%% move)%s" % [pct, penalty, suffix]
	return "Load: %d%%%s" % [pct, suffix]

func _repair_line() -> String:
	if _repair_channeling:
		return "Repairing %d%%" % int(round(_repair_progress * 100.0))
	if _blocked_remaining > 0.0 and _blocked_reason != "":
		return "Repair blocked: %s" % _blocked_reason_text(_blocked_reason)
	return ""

func _blocked_reason_text(reason: String) -> String:
	if reason == "missing_parts":
		return "missing parts"
	if reason == "missing_tools":
		return "missing tools"
	if reason == "insufficient_skill":
		return "need higher repair skill"
	if reason == "already_functional":
		return "already repaired"
	return reason

# REQ-SV: survival vitals line composers

func _vitals_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var health: float = float(_vitals_summary.get("health", 0.0))
	var max_health: float = float(_vitals_summary.get("max_health", 100.0))
	var stamina: float = float(_vitals_summary.get("stamina", 0.0))
	var max_stamina: float = float(_vitals_summary.get("max_stamina", 100.0))
	var hunger: float = float(_vitals_summary.get("hunger", 0.0))
	var max_hunger: float = float(_vitals_summary.get("max_hunger", 100.0))
	var thirst: float = float(_vitals_summary.get("thirst", 0.0))
	var max_thirst: float = float(_vitals_summary.get("max_thirst", 100.0))
	lines.append(_vital_line("Health", health, max_health, 25.0))
	lines.append(_vital_line("Stamina", stamina, max_stamina, 20.0))
	lines.append(_vital_line("Hunger", hunger, max_hunger, 15.0))
	lines.append(_vital_line("Thirst", thirst, max_thirst, 15.0))
	if bool(_vitals_summary.get("hunger_stamina_cascade_active", false)):
		lines.append("HUNGER LOW -> stamina recovery halved")
	if bool(_vitals_summary.get("thirst_vision_warning_active", false)):
		lines.append("THIRST LOW -> vision impaired")
	return lines

func _sanity_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var sanity: float = float(_sanity_summary.get("sanity", 0.0))
	var max_sanity: float = float(_sanity_summary.get("max_sanity", 100.0))
	var pct: int = int(round((sanity / max_sanity) * 100.0)) if max_sanity > 0.0 else 0
	var suffix: String = ""
	if sanity < 40.0:
		suffix = " CRITICAL"
	lines.append("Sanity: %d%%%s" % [pct, suffix])
	if bool(_sanity_summary.get("perception_pressure_active", false)):
		lines.append("PERCEPTION PRESSURE -> hallucination risk")
	return lines

func _radiation_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var radiation: float = float(_radiation_summary.get("radiation", 0.0))
	var max_radiation: float = float(_radiation_summary.get("max_radiation", 100.0))
	var pct: int = int(round((radiation / max_radiation) * 100.0)) if max_radiation > 0.0 else 0
	var suffix: String = ""
	if bool(_radiation_summary.get("health_drain_active", false)):
		suffix = " CRITICAL"
	lines.append("Radiation: %d%%%s" % [pct, suffix])
	if bool(_radiation_summary.get("health_drain_active", false)):
		lines.append("RADIATION SICKNESS -> health drain")
	return lines

func _temperature_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var temp: float = float(_temperature_summary.get("temperature", 22.0))
	var suffix: String = ""
	if not bool(_temperature_summary.get("is_safe", true)):
		suffix = " DANGER"
	lines.append("Temp: %.1fC%s" % [temp, suffix])
	if not bool(_temperature_summary.get("is_safe", true)):
		lines.append("EXTREME TEMP -> thirst drain increased")
	return lines

func _status_effects_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var effects: Array = []
	var raw: Variant = _status_effects_summary.get("effects", [])
	if raw is Array:
		effects = raw
	if effects.is_empty():
		return lines
	for e in effects:
		if e is Dictionary:
			var id: String = str(e.get("id", ""))
			var stacks: int = int(e.get("stacks", 0))
			var dur: float = float(e.get("duration", 0.0))
			if not id.is_empty():
				lines.append("Status: %s x%d (%.1fs)" % [id, stacks, dur])
	return lines

func _vital_line(name: String, value: float, maxv: float, critical: float) -> String:
	var pct: int = int(round((value / maxv) * 100.0)) if maxv > 0.0 else 0
	var suffix: String = ""
	if value <= critical:
		suffix = " CRITICAL"
	return "%s: %d%%%s" % [name, pct, suffix]
