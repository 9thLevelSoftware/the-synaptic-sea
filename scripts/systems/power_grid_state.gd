extends RefCounted
class_name PowerGridState

const DEFAULT_SUBSYSTEM_ORDER: Array[String] = [
	"life_support",
	"propulsion",
	"shields",
	"stations",
	"lights",
	"sustenance",
]

var total_supply_units: float = 100.0
var min_operational_ratio: float = 0.5
var subsystem_order: Array[String] = []
var baseline_demand_units: Dictionary = {}
var manual_routes_units: Dictionary = {}
var effective_routes_units: Dictionary = {}
var blackout_subsystems: Array[String] = []
var overloaded: bool = false
var available_supply_units: float = 100.0
var manager_broken_systems: Array[String] = []

func configure(config: Dictionary) -> void:
	total_supply_units = maxf(1.0, float(config.get("total_supply_units", 100.0)))
	min_operational_ratio = clampf(float(config.get("min_operational_ratio", 0.5)), 0.05, 1.0)
	subsystem_order.clear()
	for raw_id in config.get("subsystem_order", DEFAULT_SUBSYSTEM_ORDER):
		subsystem_order.append(str(raw_id))
	if subsystem_order.is_empty():
		subsystem_order = DEFAULT_SUBSYSTEM_ORDER.duplicate()
	baseline_demand_units.clear()
	for subsystem_id in subsystem_order:
		baseline_demand_units[subsystem_id] = float((config.get("baseline_demand_units", {}) as Dictionary).get(subsystem_id, 10.0))
	manual_routes_units.clear()
	for subsystem_id in subsystem_order:
		manual_routes_units[subsystem_id] = float(baseline_demand_units.get(subsystem_id, 0.0))
	effective_routes_units = manual_routes_units.duplicate(true)
	blackout_subsystems.clear()
	overloaded = false
	available_supply_units = total_supply_units
	manager_broken_systems.clear()

func set_manual_route(subsystem_id: String, units: float) -> bool:
	if not baseline_demand_units.has(subsystem_id):
		return false
	manual_routes_units[subsystem_id] = maxf(0.0, units)
	return true

func rebalance(power_health_ratio: float, broken_systems: Array[String] = []) -> void:
	available_supply_units = clampf(power_health_ratio, 0.0, 1.0) * total_supply_units
	manager_broken_systems = broken_systems.duplicate()
	effective_routes_units.clear()
	blackout_subsystems.clear()
	overloaded = false
	var remaining: float = available_supply_units
	for subsystem_id in subsystem_order:
		var requested: float = maxf(0.0, float(manual_routes_units.get(subsystem_id, baseline_demand_units.get(subsystem_id, 0.0))))
		var granted: float = minf(requested, remaining)
		if manager_broken_systems.has(subsystem_id):
			granted = 0.0
		effective_routes_units[subsystem_id] = granted
		remaining = maxf(0.0, remaining - granted)
		if requested > granted + 0.001:
			overloaded = true
		if not is_system_powered(subsystem_id):
			blackout_subsystems.append(subsystem_id)

func get_allocation_ratio(subsystem_id: String) -> float:
	var demand: float = maxf(0.001, float(baseline_demand_units.get(subsystem_id, 0.0)))
	return clampf(float(effective_routes_units.get(subsystem_id, 0.0)) / demand, 0.0, 1.0)

func is_system_powered(subsystem_id: String) -> bool:
	if manager_broken_systems.has(subsystem_id):
		return false
	return get_allocation_ratio(subsystem_id) >= min_operational_ratio

func get_summary() -> Dictionary:
	return {
		"total_supply_units": total_supply_units,
		"available_supply_units": available_supply_units,
		"min_operational_ratio": min_operational_ratio,
		"subsystem_order": subsystem_order.duplicate(),
		"baseline_demand_units": baseline_demand_units.duplicate(true),
		"manual_routes_units": manual_routes_units.duplicate(true),
		"effective_routes_units": effective_routes_units.duplicate(true),
		"blackout_subsystems": blackout_subsystems.duplicate(),
		"manager_broken_systems": manager_broken_systems.duplicate(),
		"overloaded": overloaded,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	for key in ["total_supply_units", "available_supply_units", "min_operational_ratio"]:
		var new_value: float = float(summary.get(key, get(key)))
		if absf(new_value - float(get(key))) > 0.001:
			set(key, new_value)
			changed = true
	for key in ["baseline_demand_units", "manual_routes_units", "effective_routes_units"]:
		var value: Variant = summary.get(key, null)
		if typeof(value) == TYPE_DICTIONARY and JSON.stringify(value) != JSON.stringify(get(key)):
			set(key, (value as Dictionary).duplicate(true))
			changed = true
	for key in ["subsystem_order", "blackout_subsystems", "manager_broken_systems"]:
		var value: Variant = summary.get(key, null)
		if typeof(value) == TYPE_ARRAY:
			var normalized: Array[String] = []
			for entry in (value as Array):
				normalized.append(str(entry))
			if normalized != get(key):
				set(key, normalized)
				changed = true
	var new_overloaded: bool = bool(summary.get("overloaded", overloaded))
	if new_overloaded != overloaded:
		overloaded = new_overloaded
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Grid %.0f/%.0f units%s" % [available_supply_units, total_supply_units, " OVERLOAD" if overloaded else ""])
	for subsystem_id in subsystem_order:
		var pct: int = int(round(get_allocation_ratio(subsystem_id) * 100.0))
		var state: String = "ON" if is_system_powered(subsystem_id) else "BLACKOUT"
		lines.append("Grid %s %d%% %s" % [subsystem_id, pct, state])
	return lines
