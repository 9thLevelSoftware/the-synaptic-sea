extends RefCounted
class_name LifeSupportState

var oxygen_percent: float = 100.0
var co2_percent: float = 2.0
var temperature_c: float = 21.0
var water_liters: float = 40.0
var nominal_temperature_c: float = 21.0
var offline_oxygen_drain_per_second: float = 4.0
var online_oxygen_recovery_per_second: float = 2.0
var offline_co2_gain_per_second: float = 3.5
var online_co2_scrub_per_second: float = 2.0
var offline_temp_drift_per_second: float = 0.3
var water_use_per_second: float = 0.2
var life_support_power_threshold: float = 0.5

func configure(config: Dictionary) -> void:
	oxygen_percent = clampf(float(config.get("oxygen_percent", 100.0)), 0.0, 100.0)
	co2_percent = clampf(float(config.get("co2_percent", 2.0)), 0.0, 100.0)
	temperature_c = float(config.get("temperature_c", 21.0))
	water_liters = maxf(0.0, float(config.get("water_liters", 40.0)))
	nominal_temperature_c = float(config.get("nominal_temperature_c", 21.0))
	offline_oxygen_drain_per_second = maxf(0.1, float(config.get("offline_oxygen_drain_per_second", 4.0)))
	online_oxygen_recovery_per_second = maxf(0.1, float(config.get("online_oxygen_recovery_per_second", 2.0)))
	offline_co2_gain_per_second = maxf(0.1, float(config.get("offline_co2_gain_per_second", 3.5)))
	online_co2_scrub_per_second = maxf(0.1, float(config.get("online_co2_scrub_per_second", 2.0)))
	offline_temp_drift_per_second = maxf(0.01, float(config.get("offline_temp_drift_per_second", 0.3)))
	water_use_per_second = maxf(0.01, float(config.get("water_use_per_second", 0.2)))
	life_support_power_threshold = clampf(float(config.get("life_support_power_threshold", 0.5)), 0.05, 1.0)

func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return
	var powered_ratio: float = clampf(float(context.get("powered_ratio", 0.0)), 0.0, 1.0)
	var breach_count: int = max(0, int(context.get("breach_count", 0)))
	var recycled_water: float = maxf(0.0, float(context.get("recycled_water", 0.0)))
	var powered: bool = powered_ratio >= life_support_power_threshold
	if powered:
		oxygen_percent = minf(100.0, oxygen_percent + online_oxygen_recovery_per_second * powered_ratio * delta)
		co2_percent = maxf(0.0, co2_percent - online_co2_scrub_per_second * powered_ratio * delta)
		temperature_c = lerpf(temperature_c, nominal_temperature_c, minf(1.0, 0.15 * delta))
	else:
		var breach_mult: float = 1.0 + float(breach_count) * 0.35
		oxygen_percent = maxf(0.0, oxygen_percent - offline_oxygen_drain_per_second * breach_mult * delta)
		co2_percent = minf(100.0, co2_percent + offline_co2_gain_per_second * breach_mult * delta)
		temperature_c += offline_temp_drift_per_second * delta * (1.0 if breach_count > 0 else -0.5)
	water_liters = maxf(0.0, water_liters - water_use_per_second * delta + recycled_water)

func is_nominal() -> bool:
	return oxygen_percent >= 70.0 and co2_percent <= 10.0 and water_liters > 5.0

func get_summary() -> Dictionary:
	return {
		"oxygen_percent": oxygen_percent,
		"co2_percent": co2_percent,
		"temperature_c": temperature_c,
		"water_liters": water_liters,
		"nominal_temperature_c": nominal_temperature_c,
		"offline_oxygen_drain_per_second": offline_oxygen_drain_per_second,
		"online_oxygen_recovery_per_second": online_oxygen_recovery_per_second,
		"offline_co2_gain_per_second": offline_co2_gain_per_second,
		"online_co2_scrub_per_second": online_co2_scrub_per_second,
		"offline_temp_drift_per_second": offline_temp_drift_per_second,
		"water_use_per_second": water_use_per_second,
		"life_support_power_threshold": life_support_power_threshold,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in [
		"oxygen_percent", "co2_percent", "temperature_c", "water_liters",
		"nominal_temperature_c", "offline_oxygen_drain_per_second",
		"online_oxygen_recovery_per_second", "offline_co2_gain_per_second",
		"online_co2_scrub_per_second", "offline_temp_drift_per_second",
		"water_use_per_second", "life_support_power_threshold",
	]:
		var new_value: float = float(summary.get(key, get(key)))
		if absf(new_value - float(get(key))) > 0.001:
			set(key, new_value)
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Life Support O2=%d%% CO2=%d%%" % [int(round(oxygen_percent)), int(round(co2_percent))])
	lines.append("Life Support Temp=%.1fC Water=%.1fL" % [temperature_c, water_liters])
	return lines
