extends SceneTree

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const RouteControlStateScript := preload("res://scripts/systems/route_control_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireStateScript := preload("res://scripts/systems/fire_state.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const PlayerProgressionStateScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _initialize() -> void:
	# Direct service smoke (REQ-012).
	# Builds a RunSnapshot from a freshly configured set of Gate 2 models,
	# writes it via SaveLoadService, reads it back, and asserts all
	# summary fields round-trip cleanly with the canonical 8 summary
	# entries (RunSnapshot.SUMMARY_FIELDS). The marker line below is the
	# spec contract.

	var service := SaveLoadServiceScript.new()
	service.delete_current_run()

	# Build real model instances and seed them with a known state.
	var ship := ShipSystemsManagerScript.new()
	ship.configure(ship.load_definitions(), 1, 17)  # DAMAGED, seed 17
	ship.force_repair("power", "battery_cells")       # force a known non-default health

	var route := RouteControlStateScript.new()
	route.configure_from_blocked_routes(["powered_route_gate_01"])

	var oxygen := OxygenStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	oxygen.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
		"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
		"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
		"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
		"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
	})
	# Force a non-default oxygen value so the round-trip proves we captured
	# the runtime number (not just the default).
	oxygen.tick(2.0, true)

	var inventory := InventoryStateScript.new()
	inventory.add_tool("portable_oxygen_pump")

	var fire := FireStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	fire.configure({
		"zone_ids": ["side_corridor_fire"],
		"burn_duration": FireStateScript.DEFAULT_BURN_DURATION,
		"clear_duration": FireStateScript.DEFAULT_CLEAR_DURATION,
	})

	# REQ-013: include the electrical-arc summary in the round-trip so the
	# smoke proves all seven SUMMARY_FIELDS survive a save / load cycle.
	# Force a non-default state by ticking halfway through the arcing
	# phase, so the round-trip proves we captured the runtime number.
	var arc := ElectricalArcStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary.
	arc.configure({
		"zone_ids": ["side_corridor_arc"],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	arc.tick(ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION + 0.6)

	var progress := ObjectiveProgressStateScript.new()
	progress.register_objective(1, "restore_systems", 2)
	progress.complete_step(1, "step_a")

	var original := RunSnapshotScript.new()
	original.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	original.kit_path = "res://data/kits/ship_structural_v0.json"
	original.gameplay_slice_path = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
	original.player_position = [1.25, 2.5, 3.75]
	original.current_objective_sequence = 2
	original.ship_systems_summary = ship.get_summary()
	original.route_control_summary = route.get_summary()
	original.oxygen_summary = oxygen.get_summary()
	original.inventory_summary = inventory.get_summary()
	original.fire_summary = fire.get_summary()
	original.electrical_arc_summary = arc.get_summary()
	original.objective_progress_summary = progress.get_summary()
	original.audio_summary = _make_audio_summary_for_smoke()
	var progression := PlayerProgressionStateScript.new()
	progression.configure(ClassDefinitionScript.load_all()["engineer"], PlayerProgressionStateScript.load_skills_catalog())
	progression.grant_xp("repair", 100)
	original.player_progression_summary = progression.get_summary()
	# ADR-0034: add food summaries
	original.spoilage_summary = _make_spoilage_summary_for_smoke()
	original.cooking_summary = _make_cooking_summary_for_smoke()
	original.hydroponics_summary = _make_hydroponics_summary_for_smoke()
	original.synthesizer_summary = _make_synthesizer_summary_for_smoke()
	original.consumable_summary = {"hotbar_slots": ["bandage_kit", "focus_ampoule", "pistol_ammo_box"], "last_item_id": "flare", "total_uses": 4}
	original.medicine_summary = {"last_item_id": "bandage_kit", "last_cured_statuses": ["radiation_sickness"], "last_results": []}
	original.stimulant_summary = {"active_stims": [{"item_id": "focus_ampoule", "remaining": 12.0, "base_duration": 20.0, "effects": ["stim_focus"], "withdrawal_effects": ["withdrawal_shakes"]}], "last_used_item": "focus_ampoule"}
	original.addiction_summary = {"profiles": {"focus_ampoule": {"tolerance": 0.4, "dependence": 1.2, "withdrawal_remaining": 8.0, "withdrawal_duration": 28.0, "withdrawal_effects": ["withdrawal_shakes"]}}}
	original.ammo_summary = {"reserves": {"pistol": 12}, "last_ammo_kind": "pistol", "total_consumed": 0}
	original.utility_summary = {"last_item_id": "flare", "last_note": "Flares mark routes and steady the player in dark corridors.", "active_flags": {"flare": {"item_id": "flare", "note": "Flares mark routes and steady the player in dark corridors.", "count": 1}}}
	var crafting := CraftingStateScript.new()
	var materials := MaterialStateScript.new()
	var craft_inv := InventoryStateScript.new()
	craft_inv.add_item("scrap_metal", 3)
	craft_inv.add_item("wiring_bundle", 4)
	craft_inv.add_item("reactive_gel", 2)
	materials.set_quality("scrap_metal", 0.8)
	materials.set_quality("wiring_bundle", 0.7)
	materials.set_quality("reactive_gel", 0.9)
	assert(crafting.begin_craft("craft_power_cell", craft_inv, materials, 2), "crafting smoke fixture should start")
	crafting.tick(10.0)
	original.crafting_summary = crafting.get_summary()
	original.material_summary = materials.get_summary()
	original.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	original.godot_version = Engine.get_version_info()["string"]
	original.saved_at = Time.get_datetime_string_from_system(true)

	if not service.save_current_run(original):
		_fail("save_current_run returned false")
		return
	if not service.has_save():
		_fail("has_save false after save")
		return

	var loaded: RunSnapshot = service.load_current_run()
	if loaded == null:
		_fail("load_current_run returned null")
		return

	if loaded.layout_path != original.layout_path:
		_fail("layout_path mismatch")
		return
	if loaded.kit_path != original.kit_path:
		_fail("kit_path mismatch")
		return
	if loaded.gameplay_slice_path != original.gameplay_slice_path:
		_fail("gameplay_slice_path mismatch")
		return
	if loaded.player_position != original.player_position:
		_fail("player_position mismatch")
		return
	if loaded.current_objective_sequence != original.current_objective_sequence:
		_fail("current_objective_sequence mismatch")
		return
	if loaded.get_summary_count() != 27:
		_fail("summary_count=%d expected 27" % loaded.get_summary_count())
		return
	if not loaded.ship_systems_summary.has("systems") or not loaded.ship_systems_summary.has("system_order"):
		_fail("ship_systems_summary missing manager keys after round-trip")
		return
	if loaded.slice_version != original.slice_version:
		_fail("slice_version mismatch")
		return
	if loaded.godot_version != original.godot_version:
		_fail("godot_version mismatch")
		return
	if not _dicts_equal(loaded.ship_systems_summary, original.ship_systems_summary):
		_fail("ship_systems_summary mismatch: got=%s expected=%s" % [JSON.stringify(loaded.ship_systems_summary), JSON.stringify(original.ship_systems_summary)])
		return
	if not _dicts_equal(loaded.route_control_summary, original.route_control_summary):
		_fail("route_control_summary mismatch")
		return
	if not _dicts_equal(loaded.oxygen_summary, original.oxygen_summary):
		_fail("oxygen_summary mismatch")
		return
	if not _dicts_equal(loaded.inventory_summary, original.inventory_summary):
		_fail("inventory_summary mismatch")
		return
	if not _dicts_equal(loaded.fire_summary, original.fire_summary):
		_fail("fire_summary mismatch")
		return
	if not _dicts_equal(loaded.electrical_arc_summary, original.electrical_arc_summary):
		_fail("electrical_arc_summary mismatch")
		return
	if not _dicts_equal(loaded.audio_summary, original.audio_summary):
		_fail("audio_summary mismatch")
		return
	if not _dicts_equal(loaded.objective_progress_summary, original.objective_progress_summary):
		_fail("objective_progress_summary mismatch")
		return
	if str(loaded.player_progression_summary.get("class_id", "")) != "engineer":
		_fail("player_progression_summary class_id not restored")
		return
	if not _dicts_equal(loaded.consumable_summary, original.consumable_summary):
		_fail("consumable_summary mismatch")
		return
	if not _dicts_equal(loaded.medicine_summary, original.medicine_summary):
		_fail("medicine_summary mismatch")
		return
	if not _dicts_equal(loaded.stimulant_summary, original.stimulant_summary):
		_fail("stimulant_summary mismatch")
		return
	if not _dicts_equal(loaded.addiction_summary, original.addiction_summary):
		_fail("addiction_summary mismatch")
		return
	if not _dicts_equal(loaded.ammo_summary, original.ammo_summary):
		_fail("ammo_summary mismatch")
		return
	if not _dicts_equal(loaded.utility_summary, original.utility_summary):
		_fail("utility_summary mismatch")
		return
	if not _dicts_equal(loaded.crafting_summary, original.crafting_summary):
		_fail("crafting_summary mismatch")
		return
	if not _dicts_equal(loaded.material_summary, original.material_summary):
		_fail("material_summary mismatch")
		return

	# Version mismatch rejection: write a snapshot with the wrong slice_version
	# and confirm load returns null instead of accepting it.
	var bad := RunSnapshotScript.new()
	bad.slice_version = "incompatible-version"
	bad.godot_version = Engine.get_version_info()["string"]
	bad.layout_path = original.layout_path
	bad.current_objective_sequence = 1
	bad.ship_systems_summary = ship.get_summary()
	bad.route_control_summary = route.get_summary()
	bad.oxygen_summary = oxygen.get_summary()
	bad.inventory_summary = inventory.get_summary()
	bad.fire_summary = fire.get_summary()
	bad.electrical_arc_summary = arc.get_summary()
	bad.objective_progress_summary = progress.get_summary()
	bad.audio_summary = original.audio_summary
	# ADR-0034: add food summaries
	bad.spoilage_summary = original.spoilage_summary
	bad.cooking_summary = original.cooking_summary
	bad.hydroponics_summary = original.hydroponics_summary
	bad.synthesizer_summary = original.synthesizer_summary
	bad.consumable_summary = original.consumable_summary
	bad.medicine_summary = original.medicine_summary
	bad.stimulant_summary = original.stimulant_summary
	bad.addiction_summary = original.addiction_summary
	bad.ammo_summary = original.ammo_summary
	bad.utility_summary = original.utility_summary
	bad.crafting_summary = original.crafting_summary
	bad.material_summary = original.material_summary
	# save_current_run should accept the snapshot (it is well-formed JSON);
	# load_current_run must reject it because of the slice_version mismatch.
	if not service.save_current_run(bad):
		_fail("saving incompatible-version snapshot failed unexpectedly")
		return
	var rejected: RunSnapshot = service.load_current_run()
	if rejected != null:
		_fail("incompatible slice_version was accepted: %s" % str(rejected.slice_version))
		return

	# Cleanup
	service.delete_current_run()
	if service.has_save():
		_fail("delete_current_run did not remove the file")
		return

	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27")
	quit(0)

func _make_spoilage_summary_for_smoke() -> Dictionary:
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
	ss.tick(1200.0)
	return ss.get_summary()

func _make_cooking_summary_for_smoke() -> Dictionary:
	var cs = load("res://scripts/systems/cooking_state.gd").new()
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
	cs.start_cooking({"items": {"ration_pack": 2, "purified_water": 2}}, 0, 10.0)
	cs.tick(4.0)
	return cs.get_summary()

func _make_hydroponics_summary_for_smoke() -> Dictionary:
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
	return hs.get_summary()

func _make_synthesizer_summary_for_smoke() -> Dictionary:
	var ss = load("res://scripts/systems/synthesizer_state.gd").new()
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
	ss.start_synthesis({"items": {"hydroponic_greens": 4, "purified_water": 2}}, 1, 10.0)
	ss.tick(7.5)
	return ss.get_summary()

func _make_audio_summary_for_smoke() -> Dictionary:
	# REQ-AU-010: smoke-only round-trip dict that exercises every
	# audio sub-summary field. Mirrors the real AudioManager.get_summary()
	# shape so the JSON round-trip through SaveLoadService is identical.
	var bus_config_script := load("res://scripts/systems/audio_bus_config.gd")
	var bus_config = bus_config_script.make_default()
	bus_config.set_volume_db("sfx", -6.0)
	var sfx_router_script := load("res://scripts/systems/sfx_event_router.gd")
	var router = sfx_router_script.new()
	router.configure({"captions_enabled": true, "caption_duration": 3.0})
	router.route(&"sfx.tool.pickup")
	router.tick(0.5)
	var music_script := load("res://scripts/systems/dynamic_music_state.gd")
	var music = music_script.new()
	music.configure({"crossfade_seconds": 2.0, "initial_state": &"TENSION"})
	music.set_flags(false, true, false)
	music.tick(1.0)
	var ambient_script := load("res://scripts/systems/ambient_zone_state.gd")
	var ambient = ambient_script.new()
	ambient.configure({"initial_role": &"engine", "initial_threat": 0.6})
	ambient.set_room_role(&"med_bay", true)
	ambient.tick(0.5)
	var spatial_script := load("res://scripts/systems/spatial_audio_resolver.gd")
	var spatial = spatial_script.new()
	spatial.configure({"ref_distance": 1.5, "max_distance": 30.0})
	var meta_script := load("res://scripts/systems/meta_event_state.gd")
	var meta = meta_script.new()
	meta.configure({"run_seed": 42})
	meta.tick(15.0)
	return {
		"bus_config": bus_config.get_summary(),
		"ambient": ambient.get_summary(),
		"sfx_router": router.get_summary(),
		"music": music.get_summary(),
		"spatial": spatial.get_summary(),
		"meta_event": meta.get_summary(),
		"current_voice_log_id": "",
		"listener_attached": false,
	}

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	# Type-tolerant compare: Godot's JSON parser decodes every JSON number
	# as float, so an int 1 in the original becomes 1.0 on round-trip. The
	# values match semantically; cast both sides through float() before
	# comparing.
	return JSON.stringify(_normalize(a)) == JSON.stringify(_normalize(b))

func _normalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var out: Dictionary = {}
		for k in (value as Dictionary).keys():
			out[k] = _normalize((value as Dictionary)[k])
		return out
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = []
		for item in (value as Array):
			arr.append(_normalize(item))
		return arr
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return value

func _fail(reason: String) -> void:
	push_error("SAVE LOAD SERVICE FAIL reason=%s" % reason)
	quit(1)
