extends SceneTree

const SustenanceStateScript := preload("res://scripts/systems/sustenance_state.gd")
const HydroponicsStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const WaterRecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")

func _initialize() -> void:
	var hydro := HydroponicsStateScript.new()
	hydro.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 10.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0
	}, 0, 5.0, 5.0)
	hydro.tick(10.0)
	var recycler := WaterRecyclerStateScript.new()
	recycler.configure({"input_item_id": "contaminated_water", "output_item_id": "purified_water", "conversion_ratio": 1.0, "recycle_time_seconds": 5.0, "power_cost": 2.0})
	recycler.load_input("contaminated_water", 4, 10.0)
	recycler.tick(5.0)
	var state := SustenanceStateScript.new()
	state.configure({"facilities": {"hydroponics": {}, "synthesizer": {}, "water_recycler": {}}})
	state.tick(1.0, {
		"powered_ratio": 1.0,
		"hydroponics_summary": hydro.get_summary(),
		"water_recycler_summary": recycler.get_summary(),
		"meals_active": true,
	})
	if state.harvest_ready != 1 or state.meals_ready != 1 or state.purified_water_ready != 4:
		_fail("expected real facility outputs")
		return
	var snap: Dictionary = state.get_summary()
	var restored := SustenanceStateScript.new()
	restored.configure({})
	restored.apply_summary(snap)
	if restored.purified_water_ready != 4:
		_fail("round-trip water mismatch")
		return
	print("SUSTENANCE STATE PASS outputs=true resources=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SUSTENANCE STATE FAIL reason=%s" % reason)
	quit(1)
