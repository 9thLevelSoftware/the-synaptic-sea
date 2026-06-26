extends RefCounted
class_name SanityState

## Pure model for player sanity.  Per REQ-SV-002.
## Drains while in the Synapse Sea field, recovers in safe zones.

const DEFAULT_MAX_SANITY: float = 100.0
const DEFAULT_DRAIN_RATE: float = 1.5
const DEFAULT_RECOVERY_RATE: float = 3.0
const PERCEPTION_PRESSURE_THRESHOLD: float = 40.0

var max_sanity: float = DEFAULT_MAX_SANITY
var drain_rate: float = DEFAULT_DRAIN_RATE
var recovery_rate: float = DEFAULT_RECOVERY_RATE

var sanity: float = DEFAULT_MAX_SANITY
var in_safe_zone: bool = false

func configure(config: Dictionary) -> void:
	max_sanity = _f(config, "max_sanity", DEFAULT_MAX_SANITY)
	drain_rate = _f(config, "drain_rate", DEFAULT_DRAIN_RATE)
	recovery_rate = _f(config, "recovery_rate", DEFAULT_RECOVERY_RATE)
	sanity = clampf(_f(config, "sanity", sanity), 0.0, max_sanity)
	in_safe_zone = bool(config.get("in_safe_zone", false))

func tick(delta_seconds: float, _context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	if in_safe_zone:
		var rec: float = recovery_rate * delta_seconds
		if rec > 0.0 and sanity < max_sanity:
			sanity = minf(max_sanity, sanity + rec)
			changed = true
	else:
		var drn: float = drain_rate * delta_seconds
		if drn > 0.0 and sanity > 0.0:
			sanity = maxf(0.0, sanity - drn)
			changed = true
	return changed

func adjust_sanity(amount: float) -> float:
	sanity = clampf(sanity + amount, 0.0, max_sanity)
	return sanity

func get_summary() -> Dictionary:
	return {
		"sanity": sanity,
		"max_sanity": max_sanity,
		"drain_rate": drain_rate,
		"recovery_rate": recovery_rate,
		"in_safe_zone": in_safe_zone,
		"perception_pressure_active": sanity < PERCEPTION_PRESSURE_THRESHOLD,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	if summary.has("sanity"):
		var new_val: float = float(summary.get("sanity", 0.0))
		if absf(new_val - sanity) > 0.001:
			sanity = new_val
			changed = true
	if summary.has("max_sanity"):
		var new_val: float = float(summary.get("max_sanity", 0.0))
		if absf(new_val - max_sanity) > 0.001:
			max_sanity = new_val
			changed = true
	if summary.has("drain_rate"):
		var new_val: float = float(summary.get("drain_rate", 0.0))
		if absf(new_val - drain_rate) > 0.001:
			drain_rate = new_val
			changed = true
	if summary.has("recovery_rate"):
		var new_val: float = float(summary.get("recovery_rate", 0.0))
		if absf(new_val - recovery_rate) > 0.001:
			recovery_rate = new_val
			changed = true
	if summary.has("in_safe_zone"):
		var new_safe: bool = bool(summary.get("in_safe_zone", false))
		if new_safe != in_safe_zone:
			in_safe_zone = new_safe
			changed = true
	sanity = clampf(sanity, 0.0, max_sanity)
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var pct: int = int(round((sanity / max_sanity) * 100.0)) if max_sanity > 0.0 else 0
	var suffix: String = ""
	if sanity < PERCEPTION_PRESSURE_THRESHOLD:
		suffix = " CRITICAL"
	lines.append("Sanity: %d%%%s" % [pct, suffix])
	if sanity < PERCEPTION_PRESSURE_THRESHOLD:
		lines.append("PERCEPTION PRESSURE -> hallucination risk")
	return lines

func _f(config: Dictionary, key: String, fallback: float) -> float:
	if config.has(key):
		return maxf(0.0, float(config.get(key, fallback)))
	return fallback
