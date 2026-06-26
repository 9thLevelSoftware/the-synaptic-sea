extends SceneTree

const HydroponicsStateScript := preload("res://scripts/systems/hydroponics_state.gd")

func _initialize() -> void:
	var hs := HydroponicsStateScript.new()
	# plant() calls configure() internally; do not pre-configure.

	# Reject insufficient water
	var bad: Dictionary = hs.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}, 0, 1.0, 5.0)
	if bad.get("ok", true):
		_fail("should reject insufficient water")
		return

	# Reject insufficient power
	bad = hs.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}, 0, 5.0, 1.0)
	if bad.get("ok", true):
		_fail("should reject insufficient power")
		return

	# Success
	var ok: Dictionary = hs.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}, 0, 5.0, 5.0)
	if not ok.get("ok", false):
		_fail("should accept valid plant: %s" % ok.get("reason", ""))
		return
	if hs.state != HydroponicsStateScript.State.PLANTED:
		_fail("state should be PLANTED")
		return

	# Tick to harvestable
	var changed: bool = hs.tick(120.0)
	if not changed:
		_fail("should become harvestable after 120s")
		return
	if hs.state != HydroponicsStateScript.State.HARVESTABLE:
		_fail("state should be HARVESTABLE")
		return

	# Harvest
	var result: Dictionary = hs.harvest()
	if not result.get("ok", false):
		_fail("harvest should succeed")
		return
	if result.get("item_id", "") != "hydroponic_greens":
		_fail("harvest item_id mismatch, got %s" % result.get("item_id", ""))
		return
	if result.get("quantity", 0) != 3:
		_fail("harvest quantity mismatch")
		return
	if hs.state != HydroponicsStateScript.State.IDLE:
		_fail("state should return to IDLE after harvest")
		return

	# Round-trip mid-growth
	ok = hs.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}, 0, 5.0, 5.0)
	hs.tick(60.0)
	var summary: Dictionary = hs.get_summary()
	var restored := HydroponicsStateScript.new()
	restored.apply_summary(summary)
	if restored.state != HydroponicsStateScript.State.PLANTED:
		_fail("round-trip state mismatch")
		return
	if absf(restored.progress_seconds - 60.0) > 0.001:
		_fail("round-trip progress mismatch")
		return

	print("HYDROPONICS STATE PASS reject_water=ok reject_power=ok harvest=ok round_trip=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("HYDROPONICS STATE FAIL reason=%s" % reason)
	quit(1)
