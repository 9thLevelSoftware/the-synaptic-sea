extends RefCounted
class_name BodyTemperatureState

## Pure model for body temperature.  Per REQ-SV-004.

const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")

const DEFAULT_TEMPERATURE: float = 22.0
const DEFAULT_SAFE_MIN: float = 18.0
const DEFAULT_SAFE_MAX: float = 32.0
const DEFAULT_DRAIN_RATE: float = 0.5
const DEFAULT_RECOVERY_RATE: float = 1.0

var temperature: float = DEFAULT_TEMPERATURE
var safe_min: float = DEFAULT_SAFE_MIN
var safe_max: float = DEFAULT_SAFE_MAX
var drain_rate: float = DEFAULT_DRAIN_RATE
var recovery_rate: float = DEFAULT_RECOVERY_RATE
var in_extreme_zone: bool = false

func configure(config: Dictionary) -> void:
	temperature = _f(config, "temperature", DEFAULT_TEMPERATURE)
	safe_min = _f(config, "safe_min", DEFAULT_SAFE_MIN)
	safe_max = _f(config, "safe_max", DEFAULT_SAFE_MAX)
	drain_rate = _f(config, "drain_rate", DEFAULT_DRAIN_RATE)
	recovery_rate = _f(config, "recovery_rate", DEFAULT_RECOVERY_RATE)
	in_extreme_zone = bool(config.get("in_extreme_zone", false))

func tick(delta_seconds: float, _context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	if in_extreme_zone:
		var drn: float = drain_rate * delta_seconds
		if drn > 0.0:
			# Move away from safe center (arbitrary: heat up)
			temperature = temperature + drn
			changed = true
	else:
		# Recover toward default temperature
		var target: float = DEFAULT_TEMPERATURE
		var diff: float = target - temperature
		if absf(diff) > 0.01:
			var rec: float = recovery_rate * delta_seconds
			if rec > absf(diff):
				rec = absf(diff)
			temperature += signf(diff) * rec
			changed = true
	return changed

func is_safe() -> bool:
	return temperature >= safe_min and temperature <= safe_max

## Returns thirst-drain multiplier when temperature is outside safe range.
## PKG-C3.1b: continuous curve (not a 1.0/1.5 cliff).
func get_thirst_multiplier() -> float:
	if is_safe():
		return 1.0
	var over: float = 0.0
	if temperature < safe_min:
		over = clampf((safe_min - temperature) / 10.0, 0.0, 1.0)
	elif temperature > safe_max:
		over = clampf((temperature - safe_max) / 10.0, 0.0, 1.0)
	# smooth 1.0 → 1.8
	var t: float = over * over * (3.0 - 2.0 * over)
	return 1.0 + 0.8 * t


## PKG-C3.1b: cold raises hunger drain; heat does not.
func get_hunger_multiplier() -> float:
	return VitalsStateScript.cold_hunger_curve(temperature, safe_min)

func adjust_temperature(amount: float) -> float:
	temperature += amount
	return temperature

func get_summary() -> Dictionary:
	return {
		"temperature": temperature,
		"safe_min": safe_min,
		"safe_max": safe_max,
		"drain_rate": drain_rate,
		"recovery_rate": recovery_rate,
		"in_extreme_zone": in_extreme_zone,
		"is_safe": is_safe(),
		"thirst_multiplier": get_thirst_multiplier(),
		"hunger_multiplier": get_hunger_multiplier(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	if summary.has("temperature"):
		var new_val: float = float(summary.get("temperature", 0.0))
		if absf(new_val - temperature) > 0.001:
			temperature = new_val
			changed = true
	if summary.has("safe_min"):
		var new_val: float = float(summary.get("safe_min", 0.0))
		if absf(new_val - safe_min) > 0.001:
			safe_min = new_val
			changed = true
	if summary.has("safe_max"):
		var new_val: float = float(summary.get("safe_max", 0.0))
		if absf(new_val - safe_max) > 0.001:
			safe_max = new_val
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
	if summary.has("in_extreme_zone"):
		var new_zone: bool = bool(summary.get("in_extreme_zone", false))
		if new_zone != in_extreme_zone:
			in_extreme_zone = new_zone
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var suffix: String = ""
	if not is_safe():
		suffix = " DANGER"
	lines.append("Temp: %.1fC%s" % [temperature, suffix])
	if not is_safe():
		lines.append("EXTREME TEMP -> thirst drain increased")
	return lines

func _f(config: Dictionary, key: String, fallback: float) -> float:
	if config.has(key):
		return float(config.get(key, fallback))
	return fallback
