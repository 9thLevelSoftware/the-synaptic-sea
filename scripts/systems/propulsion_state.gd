extends RefCounted
class_name PropulsionState

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")

var thrust_percent: float = 0.0
var engine_temperature_c: float = 28.0
var fuel_efficiency: float = 1.0
var power_threshold: float = 0.5
var operational: bool = true

func configure(config: Dictionary) -> void:
	thrust_percent = clampf(float(config.get("thrust_percent", 0.0)), 0.0, 100.0)
	engine_temperature_c = float(config.get("engine_temperature_c", 28.0))
	fuel_efficiency = maxf(0.1, float(config.get("fuel_efficiency", 1.0)))
	power_threshold = clampf(float(config.get("power_threshold", 0.5)), 0.05, 1.0)
	operational = bool(config.get("operational", true))

func tick(delta: float, context: Dictionary) -> void:
	var powered_ratio: float = clampf(float(context.get(SimKeysScript.POWERED_RATIO, 0.0)), 0.0, 1.0)
	var manager_operational: bool = bool(context.get(SimKeysScript.MANAGER_OPERATIONAL, true))
	var hull_penalty: float = clampf(float(context.get(SimKeysScript.HULL_PENALTY, 0.0)), 0.0, 1.0)
	operational = manager_operational and powered_ratio >= power_threshold and hull_penalty < 0.6
	var target: float = 100.0 * maxf(0.0, powered_ratio - hull_penalty)
	if not operational:
		target = 0.0
	thrust_percent = lerpf(thrust_percent, target, minf(1.0, maxf(0.05, delta * 0.5)))
	engine_temperature_c = lerpf(engine_temperature_c, 30.0 + thrust_percent * 0.35, minf(1.0, delta * 0.25))

func can_propel() -> bool:
	return operational and thrust_percent >= 50.0

func get_summary() -> Dictionary:
	return {
		"thrust_percent": thrust_percent,
		"engine_temperature_c": engine_temperature_c,
		"fuel_efficiency": fuel_efficiency,
		"power_threshold": power_threshold,
		"operational": operational,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["thrust_percent", "engine_temperature_c", "fuel_efficiency", "power_threshold"]:
		var new_value: float = float(summary.get(key, get(key)))
		if absf(new_value - float(get(key))) > 0.001:
			set(key, new_value)
			changed = true
	var new_operational: bool = bool(summary.get("operational", operational))
	if new_operational != operational:
		operational = new_operational
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Propulsion thrust=%d%% temp=%.1fC %s" % [int(round(thrust_percent)), engine_temperature_c, "ONLINE" if operational else "OFFLINE"])
	return lines
