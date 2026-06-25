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
