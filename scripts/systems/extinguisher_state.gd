extends RefCounted
class_name ExtinguisherState

## Player fire-extinguisher tool charge (ADR-0041). Reusable: consumed per manual
## extinguish, refilled at a powered recharge port. Pure RefCounted.

const DEFAULT_MAX_CHARGE: float = 100.0
const DEFAULT_COST_PER_USE: float = 34.0
const DEFAULT_RECHARGE_PER_SECOND: float = 5.0

var max_charge: float = DEFAULT_MAX_CHARGE
var charge: float = DEFAULT_MAX_CHARGE
var charge_cost_per_use: float = DEFAULT_COST_PER_USE
var recharge_per_second: float = DEFAULT_RECHARGE_PER_SECOND

func configure(config: Dictionary) -> void:
	max_charge = maxf(1.0, float(config.get("max_charge", DEFAULT_MAX_CHARGE)))
	charge_cost_per_use = maxf(0.0, float(config.get("charge_cost_per_use", DEFAULT_COST_PER_USE)))
	recharge_per_second = maxf(0.0, float(config.get("recharge_per_second", DEFAULT_RECHARGE_PER_SECOND)))
	charge = clampf(float(config.get("charge", max_charge)), 0.0, max_charge)

func has_charge_for_use() -> bool:
	return charge >= charge_cost_per_use

func consume_use() -> bool:
	if not has_charge_for_use():
		return false
	charge = maxf(0.0, charge - charge_cost_per_use)
	return true

func recharge(delta: float) -> void:
	if delta <= 0.0:
		return
	charge = minf(max_charge, charge + recharge_per_second * delta)

func get_summary() -> Dictionary:
	return {
		"charge": charge,
		"max_charge": max_charge,
		"charge_cost_per_use": charge_cost_per_use,
		"recharge_per_second": recharge_per_second,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["max_charge", "charge_cost_per_use", "recharge_per_second", "charge"]:
		if summary.has(key):
			var new_val: float = float(summary[key])
			if absf(new_val - float(get(key))) > 0.001:
				set(key, new_val)
				changed = true
	charge = clampf(charge, 0.0, max_charge)
	return changed
