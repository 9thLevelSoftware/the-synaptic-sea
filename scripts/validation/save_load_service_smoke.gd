extends SceneTree

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const RouteControlStateScript := preload("res://scripts/systems/route_control_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const PlayerProgressionStateScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const HallucinationDirectorScript := preload("res://scripts/systems/hallucination_director.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")

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

	# M7-B Task 7: the old timer FireState is retired. The RunSnapshot still
	# carries a legacy `fire_summary` field for save-format back-compat, so this
	# smoke seeds it with a representative literal dict and proves it round-trips.
	var fire_summary: Dictionary = {"state": "CLEARED", "hazard_kind": "fire"}

	# REQ-013: include the electrical-arc summary in the round-trip so the
	# smoke proves all 27 SUMMARY_FIELDS survive a save / load cycle.
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
	original.fire_summary = fire_summary
	original.electrical_arc_summary = arc.get_summary()
	original.objective_progress_summary = progress.get_summary()
	original.audio_summary = _make_audio_summary_for_smoke()
	var progression := PlayerProgressionStateScript.new()
	progression.configure(ClassDefinitionScript.load_all()["engineer"], PlayerProgressionStateScript.load_skills_catalog())
	progression.grant_xp("repair", 100)
	original.player_progression_summary = progression.get_summary()
	# Domain 6 P2 fix: skill-tree unlocks must survive save/load too, or the
	# rebuilt tree drops XP for skills the player already unlocked.
	original.skill_tree_summary = {"unlocked": {"fabrication": true}}
	# ADR-0034: add food summaries
	original.spoilage_summary = _make_spoilage_summary_for_smoke()
	original.hydroponics_summary = _make_hydroponics_summary_for_smoke()
	original.water_recycler_summary = _make_water_recycler_summary_for_smoke()
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
	# Session 3 B3 (audit): HallucinationDirector state (active events, rng
	# step, tier teeth) was never persisted. Build a director in a real
	# mid-hallucination state (tier 3, active events with Vector3 anchors)
	# and prove the summary survives the DISK round-trip — JSON does not
	# preserve Vector3, so the model must serialize event positions.
	var hallu := HallucinationDirectorScript.new()
	hallu.configure({"seed": 17})
	var hallu_anchors: Array = [Vector3(1.0, 0.0, 2.0), Vector3(4.0, 0.0, 6.0)]
	for i in range(24):
		hallu.tick(0.5, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": hallu_anchors})
	if hallu.get_active_events().is_empty():
		_fail("hallucination fixture produced no active events (fixture bug)")
		return
	original.set("hallucination_summary", hallu.get_summary())
	# Session 3 B7 (audit): the survival-vitals set (vitals, sanity,
	# radiation, temperature, status_effects) was counted in SUMMARY_FIELDS
	# but never populated here — the "round-trip" passed {} == {}. Seed each
	# from its real model in a NON-DEFAULT state so the disk round-trip
	# proves the runtime numbers survive.
	var vitals := VitalsStateScript.new()
	vitals.configure({})
	vitals.tick(6.0)  # passive hunger/thirst/stamina attrition
	vitals.health = 77.5
	var sanity := SanityStateScript.new()
	sanity.configure({})
	sanity.adjust_sanity(-35.0)  # 100 -> 65
	var radiation := RadiationStateScript.new()
	radiation.configure({"in_radiation_zone": true})
	radiation.adjust_radiation(60.0)  # past HEALTH_DRAIN_THRESHOLD -> drain active
	var temperature := BodyTemperatureStateScript.new()
	temperature.configure({"in_extreme_zone": true})
	temperature.adjust_temperature(15.0)  # 22 -> 37, outside safe_max -> thirst x1.5
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	statuses.add_effect("radiation_sickness", 30.0, 2)
	statuses.add_effect("stim_focus", 12.0, 1)
	original.vitals_summary = vitals.get_summary()
	original.sanity_summary = sanity.get_summary()
	original.radiation_summary = radiation.get_summary()
	original.temperature_summary = temperature.get_summary()
	original.status_effects_summary = statuses.get_summary()
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
	if loaded.get_summary_count() != 28:
		_fail("summary_count=%d expected 28" % loaded.get_summary_count())
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
	if loaded.skill_tree_summary != original.skill_tree_summary:
		_fail("skill_tree_summary mismatch")
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
	if not _dicts_equal(loaded.water_recycler_summary, original.water_recycler_summary):
		_fail("water_recycler_summary mismatch")
		return
	# B3: hallucination_summary must round-trip the disk write AND remain
	# usable — a fresh director applying the loaded summary must yield
	# Vector3 event positions (JSON turns naive Vector3s into strings,
	# which would crash HallucinationManager.render's typed assignment).
	var loaded_hallu: Variant = loaded.get("hallucination_summary")
	if loaded_hallu == null or not (loaded_hallu is Dictionary) or (loaded_hallu as Dictionary).is_empty():
		_fail("hallucination_summary missing/empty after round-trip: %s" % str(loaded_hallu))
		return
	var hallu2 := HallucinationDirectorScript.new()
	if not hallu2.apply_summary(loaded_hallu as Dictionary):
		_fail("hallucination apply_summary rejected the loaded summary")
		return
	if hallu2.get_tier() != hallu.get_tier():
		_fail("hallucination tier=%d did not round-trip (expected %d)" % [hallu2.get_tier(), hallu.get_tier()])
		return
	var hallu2_events: Array = hallu2.get_active_events()
	if hallu2_events.size() != hallu.get_active_events().size():
		_fail("hallucination active_events count=%d did not round-trip (expected %d)" % [hallu2_events.size(), hallu.get_active_events().size()])
		return
	if not (hallu2_events[0].get("position") is Vector3):
		_fail("hallucination event position not a Vector3 after disk round-trip (got %s)" % str(hallu2_events[0].get("position")))
		return
	var original_hallu_timers: Dictionary = original.hallucination_summary.get("spawn_timers", {}) as Dictionary
	var loaded_hallu_timers: Dictionary = hallu2.get_summary().get("spawn_timers", {}) as Dictionary
	if not _dicts_equal(loaded_hallu_timers, original_hallu_timers):
		_fail("hallucination spawn_timers did not round-trip: got=%s expected=%s" % [str(loaded_hallu_timers), str(original_hallu_timers)])
		return
	# B7: field-level round-trip of the survival set, plus spot asserts on
	# the non-default values so an accidental {} == {} can never pass again.
	if not _dicts_equal(loaded.vitals_summary, original.vitals_summary):
		_fail("vitals_summary mismatch")
		return
	if absf(float(loaded.vitals_summary.get("health", 0.0)) - 77.5) > 0.001:
		_fail("vitals health=%s expected 77.5" % str(loaded.vitals_summary.get("health")))
		return
	if not _dicts_equal(loaded.sanity_summary, original.sanity_summary):
		_fail("sanity_summary mismatch")
		return
	if absf(float(loaded.sanity_summary.get("sanity", 0.0)) - 65.0) > 0.001:
		_fail("sanity=%s expected 65.0" % str(loaded.sanity_summary.get("sanity")))
		return
	if not _dicts_equal(loaded.radiation_summary, original.radiation_summary):
		_fail("radiation_summary mismatch")
		return
	if not bool(loaded.radiation_summary.get("health_drain_active", false)):
		_fail("radiation health_drain_active did not round-trip true")
		return
	if not _dicts_equal(loaded.temperature_summary, original.temperature_summary):
		_fail("temperature_summary mismatch")
		return
	if bool(loaded.temperature_summary.get("is_safe", true)):
		_fail("temperature is_safe should round-trip false (extreme fixture)")
		return
	if not _dicts_equal(loaded.status_effects_summary, original.status_effects_summary):
		_fail("status_effects_summary mismatch")
		return
	if int(loaded.status_effects_summary.get("count", 0)) != 2:
		_fail("status effects count=%d expected 2" % int(loaded.status_effects_summary.get("count", 0)))
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
	bad.fire_summary = fire_summary
	bad.electrical_arc_summary = arc.get_summary()
	bad.objective_progress_summary = progress.get_summary()
	bad.audio_summary = original.audio_summary
	# ADR-0034: add food summaries
	bad.spoilage_summary = original.spoilage_summary
	bad.hydroponics_summary = original.hydroponics_summary
	bad.water_recycler_summary = original.water_recycler_summary
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

	# ADR-0043 permadeath freeze-gate: load_world() must refuse a frozen slot.
	var resolver_script := load("res://scripts/systems/permadeath_resolver.gd")
	var resolver = resolver_script.new()
	resolver.clear_death("world")
	var world_script := load("res://scripts/systems/world_snapshot.gd")
	var ws = world_script.new()
	ws.world_summary = {"world_seed": 5, "player_position": [0.0, 0.0, 0.0], "generated_marker_ids": ["2:0:1"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1"}
	ws.slice_version = world_script.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = "2026-06-21T00:00:00"
	if not service.save_world(ws):
		_fail("save_world failed while seeding the permadeath-gate assertion")
		return
	resolver.record_death("world", "death", "test epitaph", 12.0, 1)
	if service.load_world() != null:
		_fail("load_world() returned non-null for a frozen world slot")
		return
	resolver.clear_death("world")
	service.delete_current_run()
	if service.load_world() != null:
		_fail("cleanup: load_world() should be null after delete_current_run")
		return

	# PR #64 Codex P2: a future world save from a newer build is not corrupt.
	# The older build must refuse to load it, but leave world.json intact so
	# the newer build can still use it after sync/downgrade churn.
	var future_world = world_script.new()
	future_world.world_summary = {"world_seed": 99, "player_position": [0.0, 0.0, 0.0], "generated_marker_ids": ["future"]}
	future_world.home_ship = {"slice_version": SaveLoadServiceScript.CURRENT_SLICE_VERSION}
	future_world.slice_version = world_script.WORLD_SLICE_VERSION
	future_world.godot_version = Engine.get_version_info()["string"]
	future_world.saved_at = "2026-07-07T00:00:00"
	if not service.save_world(future_world):
		_fail("future world preserve: save_world fixture failed")
		return
	var future_dict: Dictionary = future_world.to_dict()
	future_dict["slice_version"] = "world-99"
	future_dict["future_sentinel"] = "keep_me"
	var future_file := FileAccess.open(SaveLoadServiceScript.WORLD_SLOT_FILE, FileAccess.WRITE)
	if future_file == null:
		_fail("future world preserve: could not overwrite world fixture")
		return
	future_file.store_string(JSON.stringify(future_dict, "	"))
	future_file.close()
	if service.load_world() != null:
		_fail("future world preserve: load_world should reject newer world-99")
		return
	if not FileAccess.file_exists(SaveLoadServiceScript.WORLD_SLOT_FILE):
		_fail("future world preserve: load_world moved future world into .corrupt")
		return
	var future_after: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveLoadServiceScript.WORLD_SLOT_FILE))
	if not (future_after is Dictionary) or str((future_after as Dictionary).get("future_sentinel", "")) != "keep_me":
		_fail("future world preserve: world.json contents were not preserved")
		return

	# PR #64 Codex P1: the outer world schema stayed at world-4 while the
	# embedded home RunSnapshot schema advanced to gate2-current-run-4.
	# load_world() must still migrate that inner home slice.
	var stale_home_world = world_script.new()
	stale_home_world.world_summary = {"world_seed": 100, "player_position": [0.0, 0.0, 0.0], "generated_marker_ids": ["stale-home"]}
	stale_home_world.home_ship = {"slice_version": "gate2-current-run-3", "player_position": [1.0, 0.0, 2.0]}
	stale_home_world.slice_version = world_script.WORLD_SLICE_VERSION
	stale_home_world.godot_version = Engine.get_version_info()["string"]
	stale_home_world.saved_at = "2026-07-07T00:01:00"
	if not service.save_world(stale_home_world):
		_fail("current world home migration: save_world fixture failed")
		return
	var stale_loaded = service.load_world()
	if stale_loaded == null:
		_fail("current world home migration: load_world returned null")
		return
	if str(stale_loaded.home_ship.get("slice_version", "")) != SaveLoadServiceScript.CURRENT_SLICE_VERSION:
		_fail("current world home migration: home_ship slice_version='%s' expected '%s'" % [str(stale_loaded.home_ship.get("slice_version", "")), SaveLoadServiceScript.CURRENT_SLICE_VERSION])
		return
	service.delete_current_run()

	# --- run_id slot-ownership rework: stamp + slot_ids_for_run + freeze_run ---
	for sid in ["slot_01", "autosave_a", "autosave_b", "autosave_c", SaveLoadServiceScript.ACTIVE_AUTOSAVE_SLOT_ID]:
		service.delete_slot(sid)
		resolver.clear_death(sid)
	service.delete_current_run()
	resolver.clear_death("world")

	service.set_active_run_id("A")
	var stamp_snap := RunSnapshotScript.new()
	stamp_snap.layout_path = original.layout_path
	stamp_snap.kit_path = original.kit_path
	stamp_snap.gameplay_slice_path = original.gameplay_slice_path
	stamp_snap.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	stamp_snap.godot_version = Engine.get_version_info()["string"]
	if not service.save_to_slot("slot_01", stamp_snap, "manual", false, "Manual Save"):
		_fail("run_id stamp: save_to_slot(slot_01) under run A should succeed")
		return
	if not service.slot_ids_for_run("A").has("slot_01"):
		_fail("run_id stamp: slot_ids_for_run('A') should contain slot_01 after a save stamped with run A")
		return
	if not service.slot_ids_for_run("").is_empty():
		_fail("run_id stamp: slot_ids_for_run('') must match nothing")
		return

	# freeze_run: freeze "A" -> has_died_in true for its slots only.
	resolver.clear_death("slot_01")
	service.freeze_run("A", "death", "test epitaph run A", 5.0, 1)
	if not resolver.has_died_in("slot_01"):
		_fail("freeze_run: slot_01 (owned by run A) should be frozen after freeze_run('A')")
		return
	if resolver.has_died_in("autosave_a"):
		_fail("freeze_run: autosave_a (never written by run A) must not be frozen by freeze_run('A')")
		return
	resolver.clear_death("slot_01")

	# index.json written WITHOUT run_id keys still loads with rows defaulting "".
	var index_path: String = "user://saves/index.json"
	var idx_file := FileAccess.open(index_path, FileAccess.READ)
	if idx_file == null:
		_fail("run_id stamp: could not read index.json to strip run_id for the legacy-index assertion")
		return
	var idx_text: String = idx_file.get_as_text()
	idx_file.close()
	var idx_parsed: Variant = JSON.parse_string(idx_text)
	if typeof(idx_parsed) != TYPE_DICTIONARY:
		_fail("run_id stamp: index.json did not parse as a dictionary")
		return
	var idx_dict: Dictionary = idx_parsed as Dictionary
	for row in (idx_dict.get("slots", []) as Array):
		if typeof(row) == TYPE_DICTIONARY:
			(row as Dictionary).erase("run_id")
	var stripped_file := FileAccess.open(index_path, FileAccess.WRITE)
	if stripped_file == null:
		_fail("run_id stamp: could not rewrite index.json without run_id keys")
		return
	stripped_file.store_string(JSON.stringify(idx_dict, "	"))
	stripped_file.close()
	if not service.has_slot("slot_01"):
		_fail("run_id stamp: slot_01 should still load after index.json's run_id keys were stripped (legacy index rows default \"\")")
		return
	# PR #58 (Codex P2): ownership must survive a stripped/legacy index --
	# the payload still carries run_id "A", and the disk-union scan in
	# slot_ids_for_run must find it even when no index row matches.
	if not service.slot_ids_for_run("A").has("slot_01"):
		_fail("run_id ownership: slot_ids_for_run('A') must still find slot_01 via its payload when index rows carry no run_id")
		return

	# PR #58 (Codex P2): a corrupt/missing index.json parses to an EMPTY
	# SaveIndexState -- freeze ownership must not fail open. Delete the
	# index entirely; the payload scan alone must still resolve ownership.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	if not service.slot_ids_for_run("A").has("slot_01"):
		_fail("run_id ownership: slot_ids_for_run('A') must find slot_01 from its payload alone after index.json is deleted")
		return
	resolver.clear_death("slot_01")
	service.freeze_run("A", "death", "test epitaph no index", 5.0, 1)
	if not resolver.has_died_in("slot_01"):
		_fail("run_id ownership: freeze_run('A') must freeze slot_01 even with index.json missing")
		return
	resolver.clear_death("slot_01")

	# True-legacy payload (no run_id key anywhere): fail-open is preserved --
	# a payload written before the rework matches no run id.
	var slot_path: String = "user://saves/slot_01.json"
	var slot_file := FileAccess.open(slot_path, FileAccess.READ)
	if slot_file == null:
		_fail("run_id ownership: could not read slot_01.json for the legacy-payload assertion")
		return
	var slot_parsed: Variant = JSON.parse_string(slot_file.get_as_text())
	slot_file.close()
	if typeof(slot_parsed) != TYPE_DICTIONARY:
		_fail("run_id ownership: slot_01.json did not parse as a dictionary")
		return
	(slot_parsed as Dictionary).erase("run_id")
	var legacy_file := FileAccess.open(slot_path, FileAccess.WRITE)
	if legacy_file == null:
		_fail("run_id ownership: could not rewrite slot_01.json without run_id")
		return
	legacy_file.store_string(JSON.stringify(slot_parsed as Dictionary, "	"))
	legacy_file.close()
	if not service.slot_ids_for_run("A").is_empty():
		_fail("run_id ownership: a legacy payload with no run_id must match no run (fail-open preserved)")
		return

	service.delete_slot("slot_01")
	service.set_active_run_id("")

	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=28 survival_roundtrip=true")
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

func _make_water_recycler_summary_for_smoke() -> Dictionary:
	var wr = load("res://scripts/systems/water_recycler_state.gd").new()
	wr.configure({
		"input_item_id": "contaminated_water",
		"output_item_id": "purified_water",
		"conversion_ratio": 1.0,
		"recycle_time_seconds": 30.0,
		"power_cost": 5.0,
	})
	wr.load_input("contaminated_water", 3, 10.0)
	wr.tick(12.0)
	return wr.get_summary()

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
