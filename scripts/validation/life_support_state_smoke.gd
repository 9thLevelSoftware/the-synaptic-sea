extends SceneTree

const LifeSupportStateScript := preload("res://scripts/systems/life_support_state.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")

func _initialize() -> void:
	var hull := HullIntegrityStateScript.new()
	hull.configure({"compartments": [{"compartment_id": "engineering", "health": 1.0, "breach_open": false, "isolation_rating": 0.8}]})
	hull.damage_compartment("engineering", 0.7, true)
	var ls := LifeSupportStateScript.new()
	ls.configure({
		"oxygen_percent": 100.0,
		"co2_percent": 2.0,
		"temperature_c": 21.0,
		"water_liters": 40.0,
		"nominal_temperature_c": 21.0,
		"offline_oxygen_drain_per_second": 4.0,
		"online_oxygen_recovery_per_second": 2.0,
		"offline_co2_gain_per_second": 3.5,
		"online_co2_scrub_per_second": 2.0,
		"offline_temp_drift_per_second": 0.3,
		"water_use_per_second": 0.2,
		"life_support_power_threshold": 0.5
	})
	ls.tick(5.0, {"powered_ratio": 0.0, "breach_count": hull.get_breach_count(), "recycled_water": 0.0})
	if ls.oxygen_percent >= 100.0:
		_fail("oxygen should drain offline")
		return
	if ls.co2_percent <= 2.0:
		_fail("co2 should rise offline")
		return
	ls.tick(5.0, {"powered_ratio": 1.0, "breach_count": 0, "recycled_water": 2.0})
	if ls.oxygen_percent <= 80.0:
		_fail("oxygen should recover online")
		return
	var snap: Dictionary = ls.get_summary()
	var restored := LifeSupportStateScript.new()
	restored.configure({})
	restored.apply_summary(snap)
	if int(round(restored.oxygen_percent)) != int(round(ls.oxygen_percent)):
		_fail("round-trip oxygen mismatch")
		return
	print("LIFE SUPPORT STATE PASS offline_drain=true recovery=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("LIFE SUPPORT STATE FAIL reason=%s" % reason)
	quit(1)
