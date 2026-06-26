extends RefCounted
class_name RadiationState

## Pure model for radiation accumulation and decay.  Per REQ-SV-003.

const DEFAULT_MAX_RADIATION: float = 100.0
const DEFAULT_ACCUMULATION_RATE: float = 2.0
const DEFAULT_DECAY_RATE: float = 0.5
const HEALTH_DRAIN_THRESHOLD: float = 50.0
const DEFAULT_HEALTH_DRAIN_RATE: float = 1.0

var max_radiation: float = DEFAULT_MAX_RADIATION
var accumulation_rate: float = DEFAULT_ACCUMULATION_RATE
var decay_rate: float = DEFAULT_DECAY_RATE
var health_drain_rate: float = DEFAULT_HEALTH_DRAIN_RATE

var radiation: float = 0.0
var in_radiation_zone: bool = false

func configure(config: Dictionary) -> void:
	max_radiation = _f(config, "max_radiation", DEFAULT_MAX_RADIATION)
	accumulation_rate = _f(config, "accumulation_rate", DEFAULT_ACCUMULATION_RATE)
	decay_rate = _f(config, "decay_rate", DEFAULT_DECAY_RATE)
	health_drain_rate = _f(config, "health_drain_rate", DEFAULT_HEALTH_DRAIN_RATE)
	radiation = clampf(_f(config, "radiation", radiation), 0.0, max_radiation)
	in_radiation_zone = bool(config.get("in_radiation_zone", false))

func tick(delta_seconds: float, _context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	if in_radiation_zone:
		var acc: float = accumulation_rate * delta_seconds
		if acc > 0.0 and radiation < max_radiation:
			radiation = minf(max_radiation, radiation + acc)
			changed = true
	else:
		var dec: float = decay_rate * delta_seconds
		if dec > 0.0 and radiation > 0.0:
			radiation = maxf(0.0, radiation - dec)
			changed = true
	return changed

## Returns the current passive health drain per second caused by radiation.
func get_health_drain_per_second() -> float:
	if radiation >= HEALTH_DRAIN_THRESHOLD:
		return health_drain_rate
	return 0.0

func adjust_radiation(amount: float) -> float:
	radiation = clampf(radiation + amount, 0.0, max_radiation)
	return radiation

func get_summary() -> Dictionary:
	return {
		"radiation": radiation,
		"max_radiation": max_radiation,
		"accumulation_rate": accumulation_rate,
		"decay_rate": decay_rate,
		"health_drain_rate": health_drain_rate,
		"in_radiation_zone": in_radiation_zone,
		"health_drain_active": radiation >= HEALTH_DRAIN_THRESHOLD,
		"health_drain_per_second": get_health_drain_per_second(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	if summary.has("radiation"):
		var new_val: float = float(summary.get("radiation", 0.0))
		if absf(new_val - radiation) > 0.001:
			radiation = new_val
			changed = true
	if summary.has("max_radiation"):
		var new_val: float = float(summary.get("max_radiation", 0.0))
		if absf(new_val - max_radiation) > 0.001:
			max_radiation = new_val
			changed = true
	if summary.has("accumulation_rate"):
		var new_val: float = float(summary.get("accumulation_rate", 0.0))
		if absf(new_val - accumulation_rate) > 0.001:
			accumulation_rate = new_val
			changed = true
	if summary.has("decay_rate"):
		var new_val: float = float(summary.get("decay_rate", 0.0))
		if absf(new_val - decay_rate) > 0.001:
			decay_rate = new_val
			changed = true
	if summary.has("health_drain_rate"):
		var new_val: float = float(summary.get("health_drain_rate", 0.0))
		if absf(new_val - health_drain_rate) > 0.001:
			health_drain_rate = new_val
			changed = true
	if summary.has("in_radiation_zone"):
		var new_zone: bool = bool(summary.get("in_radiation_zone", false))
		if new_zone != in_radiation_zone:
			in_radiation_zone = new_zone
			changed = true
	radiation = clampf(radiation, 0.0, max_radiation)
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var pct: int = int(round((radiation / max_radiation) * 100.0)) if max_radiation > 0.0 else 0
	var suffix: String = ""
	if radiation >= HEALTH_DRAIN_THRESHOLD:
		suffix = " CRITICAL"
	lines.append("Radiation: %d%%%s" % [pct, suffix])
	if radiation >= HEALTH_DRAIN_THRESHOLD:
		lines.append("RADIATION SICKNESS -> health drain")
	return lines

func _f(config: Dictionary, key: String, fallback: float) -> float:
	if config.has(key):
		return maxf(0.0, float(config.get(key, fallback)))
	return fallback
