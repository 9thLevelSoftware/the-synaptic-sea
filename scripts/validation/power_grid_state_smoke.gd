extends SceneTree

const PowerGridStateScript := preload("res://scripts/systems/power_grid_state.gd")

func _initialize() -> void:
	var grid := PowerGridStateScript.new()
	grid.configure({
		"total_supply_units": 100.0,
		"min_operational_ratio": 0.5,
		"subsystem_order": ["life_support", "propulsion", "stations", "lights", "sustenance"],
		"baseline_demand_units": {
			"life_support": 22.0,
			"propulsion": 30.0,
			"stations": 12.0,
			"lights": 8.0,
			"sustenance": 10.0
		}
	})
	grid.set_manual_route("propulsion", 0.0)
	grid.rebalance(1.0)
	if grid.is_system_powered("propulsion"):
		_fail("propulsion should blackout at 0 allocation")
		return
	grid.set_manual_route("propulsion", 30.0)
	grid.set_manual_route("sustenance", 20.0)
	grid.rebalance(0.7)
	if not grid.overloaded:
		_fail("expected overload when requests exceed available supply")
		return
	if grid.get_allocation_ratio("life_support") <= 0.0:
		_fail("life_support should still receive power")
		return
	var snap: Dictionary = grid.get_summary()
	var restored := PowerGridStateScript.new()
	restored.configure({
		"total_supply_units": 100.0,
		"min_operational_ratio": 0.5,
		"subsystem_order": ["life_support", "propulsion", "stations", "lights", "sustenance"],
		"baseline_demand_units": {
			"life_support": 22.0,
			"propulsion": 30.0,
			"stations": 12.0,
			"lights": 8.0,
			"sustenance": 10.0
		}
	})
	restored.apply_summary(snap)
	if JSON.stringify(restored.get_summary()) != JSON.stringify(snap):
		_fail("round-trip mismatch")
		return
	print("POWER GRID STATE PASS blackout=true overload=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("POWER GRID STATE FAIL reason=%s" % reason)
	quit(1)
