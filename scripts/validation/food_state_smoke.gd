extends SceneTree

const FoodStateScript := preload("res://scripts/systems/food_state.gd")

func _initialize() -> void:
	var fs := FoodStateScript.new()
	fs.configure({
		"item_id": "ration_pack",
		"display_name": "Ration Pack",
		"spoilage_seconds": 3600.0,
		"hunger_restore": 15.0,
		"thirst_restore": 5.0,
		"sanity_restore": 2.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.6,
		"rotten_multiplier": 0.2,
		"rotten_sickness_risk": 0.25,
	})

	# Initial state must be FRESH
	if fs.stage != FoodStateScript.Stage.FRESH:
		_fail("initial stage should be FRESH")
		return

	# Effective restores at fresh
	var eff: Dictionary = fs.get_effective_restores()
	if absf(eff["hunger"] - 15.0) > 0.001:
		_fail("fresh hunger should be 15.0")
		return
	if absf(eff["thirst"] - 5.0) > 0.001:
		_fail("fresh thirst should be 5.0")
		return
	if absf(eff["sanity"] - 2.0) > 0.001:
		_fail("fresh sanity should be 2.0")
		return
	if eff["sickness_risk"] != 0.0:
		_fail("fresh sickness risk should be 0")
		return

	# Tick to stale (50% of 3600 = 1800s)
	fs.tick(1800.0)
	if fs.stage != FoodStateScript.Stage.STALE:
		_fail("after 1800s stage should be STALE")
		return

	eff = fs.get_effective_restores()
	if absf(eff["hunger"] - 9.0) > 0.001:
		_fail("stale hunger should be 9.0 (15*0.6)")
		return
	if eff["sickness_risk"] != 0.0:
		_fail("stale sickness risk should be 0")
		return

	# Tick to rotten (another 1800s)
	fs.tick(1800.0)
	if fs.stage != FoodStateScript.Stage.ROTTEN:
		_fail("after 3600s stage should be ROTTEN")
		return

	eff = fs.get_effective_restores()
	if absf(eff["hunger"] - 3.0) > 0.001:
		_fail("rotten hunger should be 3.0 (15*0.2)")
		return
	if absf(eff["sickness_risk"] - 0.25) > 0.001:
		_fail("rotten sickness risk should be 0.25")
		return

	# Round-trip summary
	var summary: Dictionary = fs.get_summary()
	var restored := FoodStateScript.new()
	restored.apply_summary(summary)
	if restored.stage != FoodStateScript.Stage.ROTTEN:
		_fail("round-trip stage mismatch")
		return
	if absf(restored.elapsed_seconds - 3600.0) > 0.001:
		_fail("round-trip elapsed mismatch")
		return

	# Status lines
	var lines: PackedStringArray = fs.get_status_lines()
	var found: bool = false
	for line in lines:
		if String(line).begins_with("Food: Ration Pack [ROTTEN]"):
			found = true
			break
	if not found:
		_fail("status lines missing expected food line")
		return

	print("FOOD STATE PASS fresh=ok stale=ok rotten=ok round_trip=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("FOOD STATE FAIL reason=%s" % reason)
	quit(1)
