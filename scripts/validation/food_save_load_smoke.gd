extends SceneTree

## Food-specific save/load integration smoke.
## Builds food model state, persists through SaveLoadService, and asserts
## every food summary field round-trips. This is the integration-level
## counterpart to the individual model smokes.

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	service.delete_current_run()

	var original := RunSnapshotScript.new()
	original.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	original.current_objective_sequence = 1
	original.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	original.godot_version = Engine.get_version_info()["string"]

	# Build food summaries
	var ss = load("res://scripts/systems/spoilage_state.gd").new()
	ss.add_food("ration_pack", {
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
	ss.add_food("cooked_meal", {
		"display_name": "Cooked Meal",
		"spoilage_seconds": 1800.0,
		"hunger_restore": 25.0,
		"thirst_restore": 8.0,
		"sanity_restore": 5.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.7,
		"rotten_multiplier": 0.3,
		"rotten_sickness_risk": 0.15,
	})
	ss.tick(1200.0)  # ration_pack fresh (1200/3600=0.33 < 0.5), cooked_meal stale (1200/1800=0.67 > 0.5)
	original.spoilage_summary = ss.get_summary()

	var hs = load("res://scripts/systems/hydroponics_state.gd").new()
	hs.plant({
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}, 0, 5.0, 5.0)
	hs.tick(30.0)
	original.hydroponics_summary = hs.get_summary()

	var syn = load("res://scripts/systems/synthesizer_state.gd").new()
	syn.configure({
		"recipe_id": "nutrient_paste",
		"display_name": "Nutrient Paste",
		"ingredients": {"hydroponic_greens": 2, "purified_water": 1},
		"produces": {"item_id": "nutrient_paste", "quantity": 2},
		"power_cost": 8.0,
		"cook_time_seconds": 15.0,
		"required_skill_level": 1,
		"station_kind": "synthesizer",
	})
	syn.start_synthesis({"items": {"hydroponic_greens": 4, "purified_water": 2}}, 1, 10.0)
	syn.tick(7.5)
	original.synthesizer_summary = syn.get_summary()

	if not service.save_current_run(original):
		_fail("save_current_run returned false")
		return

	var loaded: RunSnapshot = service.load_current_run()
	if loaded == null:
		_fail("load_current_run returned null")
		return

	# Assert food summaries present and non-empty
	if loaded.spoilage_summary.is_empty():
		_fail("spoilage_summary empty after round-trip")
		return
	if loaded.hydroponics_summary.is_empty():
		_fail("hydroponics_summary empty after round-trip")
		return
	if loaded.synthesizer_summary.is_empty():
		_fail("synthesizer_summary empty after round-trip")
		return

	# Assert spoilage contains the two foods with correct stages
	# ration_pack: 1200/3600 = 0.33 < 0.5 -> FRESH (0)
	# cooked_meal: 1200/1800 = 0.67 > 0.5 -> STALE (1)
	var foods: Variant = loaded.spoilage_summary.get("foods", {})
	if typeof(foods) != TYPE_DICTIONARY:
		_fail("spoilage foods not a dictionary")
		return
	var foods_dict: Dictionary = foods as Dictionary
	if not foods_dict.has("ration_pack"):
		_fail("ration_pack missing from spoilage")
		return
	if not foods_dict.has("cooked_meal"):
		_fail("cooked_meal missing from spoilage")
		return
	var rp_summary: Dictionary = foods_dict["ration_pack"] as Dictionary
	var cm_summary: Dictionary = foods_dict["cooked_meal"] as Dictionary
	if int(rp_summary.get("stage", 0)) != 0:  # FRESH
		_fail("ration_pack stage mismatch after round-trip")
		return
	if int(cm_summary.get("stage", 0)) != 1:  # STALE
		_fail("cooked_meal stage mismatch after round-trip")
		return


	# Assert hydroponics progress preserved
	if float(loaded.hydroponics_summary.get("progress_seconds", 0.0)) != 30.0:
		_fail("hydroponics progress mismatch")
		return
	if str(loaded.hydroponics_summary.get("crop_id", "")) != "hydroponic_greens":
		_fail("hydroponics crop_id mismatch")
		return

	# Assert synthesizer power tracking preserved
	if float(loaded.synthesizer_summary.get("total_power_consumed", 0.0)) != 8.0:
		_fail("synthesizer power mismatch")
		return
	if str(loaded.synthesizer_summary.get("station_type", "")) != "synthesizer":
		_fail("synthesizer station_type mismatch")
		return

	service.delete_current_run()
	print("FOOD SAVE LOAD PASS spoilage=2 hydroponics=1 synthesizer=1")
	quit(0)

func _fail(reason: String) -> void:
	push_error("FOOD SAVE LOAD FAIL reason=%s" % reason)
	quit(1)
