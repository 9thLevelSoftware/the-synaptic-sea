extends SceneTree

const SynthesizerStateScript := preload("res://scripts/systems/synthesizer_state.gd")

func _initialize() -> void:
	var ss := SynthesizerStateScript.new()
	ss.configure({
		"recipe_id": "nutrient_paste",
		"display_name": "Nutrient Paste",
		"ingredients": {"hydroponic_greens": 2, "purified_water": 1},
		"produces": {"item_id": "nutrient_paste", "quantity": 2},
		"power_cost": 8.0,
		"cook_time_seconds": 15.0,
		"required_skill_level": 1,
		"station_kind": "synthesizer",
	})

	# Missing ingredients
	var bad: Dictionary = ss.start_synthesis({"items": {}}, 1, 10.0)
	if bad.get("ok", true):
		_fail("should reject missing ingredients")
		return

	# Insufficient skill
	bad = ss.start_synthesis({"items": {"hydroponic_greens": 2, "purified_water": 1}}, 0, 10.0)
	if bad.get("ok", true):
		_fail("should reject insufficient skill")
		return

	# Success
	var inv: Dictionary = {"items": {"hydroponic_greens": 4, "purified_water": 2}}
	var ok: Dictionary = ss.start_synthesis(inv, 1, 10.0)
	if not ok.get("ok", false):
		_fail("should accept valid synthesis start: %s" % ok.get("reason", ""))
		return
	if not ss.is_complete():
		# should still be cooking
		pass

	# Tick to completion
	var changed: bool = ss.tick(15.0)
	if not changed:
		_fail("should complete after 15s")
		return
	if not ss.is_complete():
		_fail("should be complete after 15s")
		return

	# Collect result
	var result: Dictionary = ss.collect_result()
	if not result.get("ok", false):
		_fail("collect_result should succeed")
		return
	if result.get("item_id", "") != "nutrient_paste":
		_fail("result item_id mismatch")
		return
	if result.get("quantity", 0) != 2:
		_fail("result quantity mismatch")
		return

	# Power tracking
	if ss.total_power_consumed != 8.0:
		_fail("total_power_consumed should be 8.0")
		return

	# Round-trip mid-synthesis
	ss.start_synthesis(inv, 1, 10.0)
	ss.tick(7.5)
	var summary: Dictionary = ss.get_summary()
	var restored := SynthesizerStateScript.new()
	restored.apply_summary(summary)
	if restored.total_power_consumed != 16.0:
		_fail("round-trip total_power mismatch, got %.1f" % restored.total_power_consumed)
		return

	print("SYNTHESIZER STATE PASS reject_missing=ok reject_skill=ok complete=ok collect=ok power=ok round_trip=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SYNTHESIZER STATE FAIL reason=%s" % reason)
	quit(1)
