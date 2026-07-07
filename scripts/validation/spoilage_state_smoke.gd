extends SceneTree

const SpoilageStateScript := preload("res://scripts/systems/spoilage_state.gd")
const FoodStateScript := preload("res://scripts/systems/food_state.gd")

func _initialize() -> void:
	var ss := SpoilageStateScript.new()
	ss.add_food("ration_pack", {
		"display_name": "Ration Pack",
		"spoilage_seconds": 100.0,
		"hunger_restore": 15.0,
		"thirst_restore": 5.0,
		"sanity_restore": 2.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.6,
		"rotten_multiplier": 0.2,
		"rotten_sickness_risk": 0.25,
	})
	ss.add_food("scavenged_protein", {
		"display_name": "Scavenged Protein",
		"spoilage_seconds": 200.0,
		"hunger_restore": 20.0,
		"thirst_restore": 0.0,
		"sanity_restore": 0.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.5,
		"rotten_multiplier": 0.1,
		"rotten_sickness_risk": 0.35,
	})

	if ss.get_food_count_by_stage(FoodStateScript.Stage.FRESH) != 2:
		_fail("expected 2 fresh items")
		return

	# Tick both items to different stages
	# ration_pack (spoilage=100s): 120s -> ROTTEN (1 transition)
	# scavenged_protein (spoilage=200s): 120s -> STALE (1 transition)
	var transitions: int = ss.tick(120.0)
	if transitions != 2:
		_fail("expected 2 transitions after 120s, got %d" % transitions)
		return

	if ss.get_food_count_by_stage(FoodStateScript.Stage.FRESH) != 0:
		_fail("expected 0 fresh items after 120s")
		return
	if ss.get_food_count_by_stage(FoodStateScript.Stage.STALE) != 1:
		_fail("expected 1 stale item after 120s")
		return
	if ss.get_food_count_by_stage(FoodStateScript.Stage.ROTTEN) != 1:
		_fail("expected 1 rotten item after 120s")
		return
	if not ss.get_any_rotten():
		_fail("expected rotten after 120s")
		return

	# Tick scavenged_protein to rotten
	ss.tick(100.0)
	if ss.get_food_count_by_stage(FoodStateScript.Stage.ROTTEN) != 2:
		_fail("expected 2 rotten items after 220s")
		return

	# Round-trip
	var summary: Dictionary = ss.get_summary()
	var restored := SpoilageStateScript.new()
	restored.apply_summary(summary)
	if restored.get_summary()["transition_count"] != summary["transition_count"]:
		_fail("round-trip transition_count mismatch")
		return
	if restored.get_food_count_by_stage(FoodStateScript.Stage.ROTTEN) != 2:
		_fail("round-trip rotten count mismatch")
		return
	if restored.get_food_count_by_stage(FoodStateScript.Stage.FRESH) != 0:
		_fail("round-trip fresh count mismatch")
		return

	# Status lines
	var lines: PackedStringArray = ss.get_status_lines()
	var found: bool = false
	for line in lines:
		if String(line).begins_with("Food stocks:"):
			found = true
			break
	if not found:
		_fail("status lines missing food stocks")
		return

	print("SPOILAGE STATE PASS transitions=1 fresh=1 stale=1 rotten=1 round_trip=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SPOILAGE STATE FAIL reason=%s" % reason)
	quit(1)
