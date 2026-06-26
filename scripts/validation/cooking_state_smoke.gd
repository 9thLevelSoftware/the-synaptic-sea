extends SceneTree

const CookingStateScript := preload("res://scripts/systems/cooking_state.gd")

func _initialize() -> void:
	var cs := CookingStateScript.new()
	cs.configure({
		"recipe_id": "cooked_meal_basic",
		"display_name": "Basic Cooked Meal",
		"ingredients": {"ration_pack": 1, "purified_water": 1},
		"produces": {"item_id": "cooked_meal", "quantity": 1},
		"power_cost": 5.0,
		"cook_time_seconds": 10.0,
		"required_skill_level": 0,
		"station_kind": "galley",
	})

	# Missing ingredients
	var bad: Dictionary = cs.start_cooking({"items": {}}, 0, 10.0)
	if bad.get("ok", true):
		_fail("should reject missing ingredients")
		return

	# Insufficient power
	bad = cs.start_cooking({"items": {"ration_pack": 1, "purified_water": 1}}, 0, 2.0)
	if bad.get("ok", true):
		_fail("should reject insufficient power")
		return

	# Success
	var inv: Dictionary = {"items": {"ration_pack": 2, "purified_water": 2}}
	var ok: Dictionary = cs.start_cooking(inv, 0, 10.0)
	if not ok.get("ok", false):
		_fail("should accept valid cooking start: %s" % ok.get("reason", ""))
		return
	if cs.state != CookingStateScript.State.COOKING:
		_fail("state should be COOKING")
		return

	# Tick to completion
	var changed: bool = cs.tick(10.0)
	if not changed:
		_fail("should complete after 10s")
		return
	if cs.state != CookingStateScript.State.COMPLETE:
		_fail("state should be COMPLETE")
		return

	# Collect result
	var result: Dictionary = cs.collect_result()
	if not result.get("ok", false):
		_fail("collect_result should succeed")
		return
	if result.get("item_id", "") != "cooked_meal":
		_fail("result item_id mismatch")
		return
	if result.get("quantity", 0) != 1:
		_fail("result quantity mismatch")
		return
	if cs.state != CookingStateScript.State.IDLE:
		_fail("state should return to IDLE after collect")
		return

	# Round-trip
	# Re-start cooking for the round-trip test
	cs.start_cooking(inv, 0, 10.0)
	cs.tick(5.0)
	var summary: Dictionary = cs.get_summary()
	var restored := CookingStateScript.new()
	restored.apply_summary(summary)
	if restored.state != CookingStateScript.State.COOKING:
		_fail("round-trip state mismatch")
		return
	if absf(restored.progress_seconds - 5.0) > 0.001:
		_fail("round-trip progress mismatch")
		return

	print("COOKING STATE PASS reject_missing=ok reject_power=ok complete=ok collect=ok round_trip=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("COOKING STATE FAIL reason=%s" % reason)
	quit(1)
