extends RefCounted
class_name ShieldState

var charge_percent: float = 100.0
var recharge_per_second: float = 8.0
var drain_per_second: float = 15.0
var power_threshold: float = 0.5
var active: bool = true

func configure(config: Dictionary) -> void:
	charge_percent = clampf(float(config.get("charge_percent", 100.0)), 0.0, 100.0)
	recharge_per_second = maxf(0.1, float(config.get("recharge_per_second", 8.0)))
	drain_per_second = maxf(0.1, float(config.get("drain_per_second", 15.0)))
	power_threshold = clampf(float(config.get("power_threshold", 0.5)), 0.05, 1.0)
	active = bool(config.get("active", true))

func tick(delta: float, context: Dictionary) -> void:
	var powered_ratio: float = clampf(float(context.get("powered_ratio", 0.0)), 0.0, 1.0)
	if powered_ratio >= power_threshold:
		active = true
		charge_percent = minf(100.0, charge_percent + recharge_per_second * powered_ratio * delta)
	else:
		active = false
		charge_percent = maxf(0.0, charge_percent - drain_per_second * delta)

func get_summary() -> Dictionary:
	return {
		"charge_percent": charge_percent,
		"recharge_per_second": recharge_per_second,
		"drain_per_second": drain_per_second,
		"power_threshold": power_threshold,
		"active": active,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["charge_percent", "recharge_per_second", "drain_per_second", "power_threshold"]:
		var new_value: float = float(summary.get(key, get(key)))
		if absf(new_value - float(get(key))) > 0.001:
			set(key, new_value)
			changed = true
	var new_active: bool = bool(summary.get("active", active))
	if new_active != active:
		active = new_active
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Shields charge=%d%% %s" % [int(round(charge_percent)), "ACTIVE" if active else "DOWN"])
	return lines
