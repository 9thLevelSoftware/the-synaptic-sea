extends SceneTree

## FC-12 / P10: versioned crafting migration and atomic persistence boundary.
## Marker: FC P10 PASS

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const PendingOutputStoreScript := preload("res://scripts/systems/pending_output_store.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const ThreatInitialStateBuilderScript := preload("res://scripts/systems/threat_initial_state_builder.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")

const FIXTURE_DIR: String = "res://tests/fixtures/feature_completion"
const RUN_CASES: Array[String] = [
    "p10_run_v4_legacy_active_paid.json",
    "p10_run_v5_transactional.json",
    "p10_run_v7_future.json",
    "p10_run_v5_malformed_component_source_lot.json",
    "p10_run_v5_malformed_field_pin.json",
]
const WORLD_CASES: Array[String] = [
    "p10_world_v4_legacy_active_paid.json",
    "p10_world_v5_transactional.json",
    "p10_world_v7_future.json",
    "p10_world_v5_malformed_nested_holder.json",
]

var live_main: Node = null
var live_frames: int = 0
var live_finished: bool = false
var title_validation: Node = null
var title_validation_frames: int = 0
var title_expected_run_id: String = ""
var title_expected_inventory: Dictionary = {}
var title_expected_player_position: Array = []
var title_expected_location: String = ""
var title_expected_objective: int = 0


class SkillFixture extends RefCounted:
    func get_skill_level(_skill_id: String) -> int:
        return 4


func _initialize() -> void:
    if not _ensure_save_dir():
        return
    _clear_owned_fixture_files()
    var fixtures: Dictionary = {}
    for fixture_name in RUN_CASES + WORLD_CASES:
        var loaded: Dictionary = _load_fixture(fixture_name)
        if loaded.is_empty():
            _fail("could not load fixture %s" % fixture_name)
            return
        fixtures[fixture_name] = loaded
    var service = SaveLoadServiceScript.new()
    if not _validate_nondefault_threat_summary_round_trip():
        return
    if not _validate_invalid_json_prepare_read_only(service):
        return
    if not _validate_legacy_run(service, fixtures[RUN_CASES[0]]):
        return
    if not _validate_current_run(service, fixtures[RUN_CASES[1]]):
        return
    if not _validate_rejected_run(service, "p10-future", fixtures[RUN_CASES[2]]):
        return
    if not _validate_rejected_run(service, "p10-bad-component", fixtures[RUN_CASES[3]]):
        return
    if not _validate_rejected_run(service, "p10-bad-field", fixtures[RUN_CASES[4]]):
        return
    if not _validate_legacy_world(service, fixtures[WORLD_CASES[0]]):
        return
    if not _validate_current_world(service, fixtures[WORLD_CASES[1]]):
        return
    if not _validate_exact_read_buffer_seal(service, fixtures[WORLD_CASES[1]]):
        return
    if not _validate_terminal_authority_matrix(
            service, fixtures[WORLD_CASES[1]], fixtures[RUN_CASES[1]]):
        return
    if not _validate_rejected_world(service, fixtures[WORLD_CASES[2]], "future world"):
        return
    if not _validate_rejected_world(service, fixtures[WORLD_CASES[3]], "nested holder"):
        return
    live_main = MAIN_SCENE.instantiate()
    get_root().add_child(live_main)
    process_frame.connect(_on_live_frame)


func _validate_nondefault_threat_summary_round_trip() -> bool:
    var source = ThreatManagerScript.new()
    source.awareness_indicator = 0.09175000000000003
    source.combat_engaged = true
    source.last_attack_result = _weapon_receipt(
        "flare_pistol", "p10-threat", 7.125000000000003)
    source.detection_state.detected = true
    source.damage_pipeline.total_damage_applied = 12.375000000000004
    var expected: Dictionary = source.get_summary()
    var restored = ThreatManagerScript.new()
    restored.awareness_indicator = 0.75
    restored.combat_engaged = false
    restored.last_attack_result = {"stale": true}
    if not restored.apply_summary(expected):
        return _fail_bool("nondefault threat summary was rejected")
    var actual: Dictionary = restored.get_summary()
    if not _json_values_equal(actual, expected):
        return _fail_bool("threat awareness/detection/damage authority did not round-trip")
    var dead_threat = ThreatAIStateScript.new()
    dead_threat.configure({
        "instance_id": "p10-restored-ranged-kill",
        "archetype_id": "p10-ranged-target",
        "health": 0.0,
        "world_position": [1.0, 0.5, 2.0],
    })
    restored.threats.append(dead_threat)
    var kill_receipts: Array[Dictionary] = []
    restored.threat_killed.connect(func(receipt: Dictionary) -> void:
        kill_receipts.append(receipt.duplicate(true)))
    restored._sweep_dead_threats()
    if kill_receipts.size() != 1 \
            or str(kill_receipts[0].get("weapon_id", "")) != "flare_pistol" \
            or str(kill_receipts[0].get("weapon_id", "")) in ["", "crowbar", "unarmed"]:
        return _fail_bool("restored lethal ranged attack lost exact kill attribution")
    source.free()
    restored.free()
    return true


func _validate_restored_ranged_kill_production_callback(playable) -> bool:
    var manager = playable.threat_manager
    var bus = playable.get_training_event_bus()
    var progression = playable.player_progression
    if manager == null or bus == null or progression == null:
        return _fail_bool("production ranged-kill dependencies were unavailable")
    var summary: Dictionary = manager.get_summary()
    summary["threats"] = []
    summary["encounter_markers"] = []
    summary["last_attack_result"] = _weapon_receipt(
        "flare_pistol", "p10-production-ranged-kill", 7.125)
    if not manager.apply_summary(summary) \
            or manager._last_attack_weapon_id != "flare_pistol":
        return _fail_bool("production manager did not restore exact ranged receipt")
    var dead_threat = ThreatAIStateScript.new()
    dead_threat.configure({
        "instance_id": "p10-production-ranged-kill",
        "archetype_id": "hull_tendril",
        "health": 0.0,
        "world_position": [1.0, 0.5, 2.0],
    })
    manager.threats.append(dead_threat)
    var log_before: int = bus.get_log().size()
    var bus_xp_before: int = bus.get_total_xp_delivered()
    var scavenging_before: int = progression.get_skill_xp("scavenging")
    var intimidation_before: int = progression.get_skill_xp("intimidation")
    var kills_before: int = playable.threats_killed_count
    var inventory_before = playable.inventory_state
    # Keep this receipt proof isolated from corpse/container side effects while
    # exercising the production-connected manager signal and callback.
    playable.inventory_state = null
    manager._sweep_dead_threats()
    playable.inventory_state = inventory_before
    var new_log: Array = bus.get_log().slice(log_before)
    var kill_events: int = 0
    var intimidate_events: int = 0
    for event_v in new_log:
        if not event_v is Dictionary:
            continue
        var event_id: String = str((event_v as Dictionary).get("event_id", ""))
        if event_id == "threat_killed":
            kill_events += 1
            if int((event_v as Dictionary).get("base_xp", 0)) != 10 \
                    or str((event_v as Dictionary).get("skill_id", "")) != "scavenging" \
                    or bool((event_v as Dictionary).get("gated", true)):
                return _fail_bool("production ranged kill emitted invalid training receipt")
        elif event_id == "intimidate_threat":
            intimidate_events += 1
    if kill_events != 1 or intimidate_events != 0 \
            or bus.get_total_xp_delivered() != bus_xp_before + 10 \
            or progression.get_skill_xp("scavenging") <= scavenging_before \
            or progression.get_skill_xp("intimidation") != intimidation_before \
            or playable.threats_killed_count != kills_before + 1:
        return _fail_bool("restored ranged receipt did not drive exact production reward callback")
    return true


func _weapon_receipt(weapon_id: String, target_id: String, damage: float) -> Dictionary:
    return {
        "damage_type": "physical",
        "incoming": damage,
        "flat_reduction": 0.0,
        "resistance": 0.0,
        "absorbed": 0.0,
        "final_damage": damage,
        "durability": 0.0,
        "profile": {
            "flat_reduction": {}, "resistance": {}, "durability": 0.0,
            "max_durability": 0.0, "wear_factor": 0.35,
        },
        "stun_seconds": 0.0,
        "source_id": weapon_id,
        "status_effect_id": "",
        "noise": 0.75,
        "ok": true,
        "weapon_id": weapon_id,
        "target_id": target_id,
        "ammo_item_id": "flare_round" if weapon_id == "flare_pistol" else "",
        "ammo_remaining": 2 if weapon_id == "flare_pistol" else -1,
    }


func _on_live_frame() -> void:
    if live_finished:
        return
    live_frames += 1
    var playable = live_main.get("playable_instance") if live_main != null else null
    if playable == null or not bool(playable.get("playable_started")):
        if live_frames > 500:
            _fail("production playable did not start")
        return
    live_finished = true
    if not _validate_live_production(playable):
        return
    _begin_title_continue_validation()


func _validate_live_production(initial_playable) -> bool:
    if initial_playable.menu_coordinator != null:
        initial_playable.menu_coordinator.dismiss_boot_menu()
        initial_playable.menu_coordinator.menu_state.close_all()
    if not _validate_restored_ranged_kill_production_callback(initial_playable):
        return false
    if not _validate_all_station_kinds_through_ordinary_interact(initial_playable):
        return false
    var expected_settings: Dictionary = initial_playable.menu_coordinator.get_settings_summary()
    expected_settings["text_scale"] = 1.35
    expected_settings["colorblind_mode"] = "deuteranopia"
    expected_settings["motion_reduce"] = true
    if not initial_playable.menu_coordinator.apply_settings_summary(expected_settings):
        return _fail_bool("production nondefault settings fixture was rejected")
    expected_settings = initial_playable.menu_coordinator.get_settings_summary()
    var expected_audio: Dictionary = initial_playable.audio_manager.get_summary()
    expected_audio["current_voice_log_id"] = "p10-active-voice-log"
    expected_audio.bus_config.volumes["music"] = -13.375000000000002
    expected_audio.bus_config.mutes["ambient"] = true
    if not initial_playable.audio_manager.apply_summary(expected_audio):
        return _fail_bool("production nondefault audio fixture was rejected")
    expected_audio = initial_playable.audio_manager.get_summary()
    var expected_fire: Dictionary = _stage_nondefault_fire(initial_playable)
    if expected_fire.is_empty():
        return false
    if not initial_playable.request_save():
        return _fail_bool("production world capture/save failed")
    var service = initial_playable.get_save_load_service()
    var source_path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    var source_before: String = FileAccess.get_file_as_string(source_path)
    if source_before.is_empty():
        return _fail_bool("production world save bytes missing")

    var manual_world = initial_playable._build_world_snapshot()
    if manual_world == null or not initial_playable.save_load_menu.confirm_save_to_slot(
            "p10-live-manual", manual_world, "manual", "P10 Live"):
        return _fail_bool("production manual world save failed")
    if not initial_playable.request_quicksave_for_validation():
        return _fail_bool("production quicksave world save failed")
    var autosave: Dictionary = initial_playable.force_autosave_for_validation()
    if not bool(autosave.get("should_save", false)):
        return _fail_bool("production autosave world save failed: %s" % str(autosave))
    for slot_id in ["p10-live-manual", "quicksave", str(autosave.get("slot_id", ""))]:
        var slot_prepared: Dictionary = service.prepare_slot_load(slot_id)
        var slot_world: Dictionary = service.inspect_prepared_world_for_validation(
            str(slot_prepared.get("token", "")), str(slot_prepared.get("seal", "")))
        if not bool(slot_prepared.get("ok", false)) \
                or str(slot_world.get("slice_version", "")) != "world-6" \
                or not slot_world.get("home_pending_outputs_v1", null) is Dictionary \
                or not _json_values_equal(
                    slot_world.get("home_ship", {}).get(
                        "ship_systems_summary", {}).get(
                            "fire_suppression_summary", {}), expected_fire):
            return _fail_bool("%s did not persist a coherent world envelope" % slot_id)
        service.discard_prepared_load(str(slot_prepared.token))

    # Quicksave and rotating autosave each exercise a real staged replacement,
    # with a fresh service capability owned by the current playable.
    for slot_id in ["quicksave", str(autosave.get("slot_id", ""))]:
        var slot_prepared: Dictionary = service.prepare_slot_load(slot_id)
        var previous = initial_playable
        if not bool(slot_prepared.get("ok", false)) \
                or not live_main.replace_playable_from_prepared(previous, slot_prepared):
            return _fail_bool("%s staged replacement failed: %s" % [
                slot_id, str(live_main.get_last_restore_failure_reason_for_validation())])
        initial_playable = live_main.get("playable_instance")
        if initial_playable == null or initial_playable == previous \
                or not _validate_nondefault_fire(initial_playable, expected_fire) \
                or initial_playable.save_load_menu \
                    != initial_playable.menu_coordinator.get_save_load_menu():
            return _fail_bool("%s staged replacement did not bind exact authority" % slot_id)
        service = initial_playable.get_save_load_service()

    # Open the visible Records/Save-Load surface and drive its real cursor,
    # arm, and confirm sequence through the same input route as gameplay.
    var menu = initial_playable.menu_coordinator
    menu.open_meta_screen("save_load")
    var rows: Array = menu.call("_save_load_rows")
    var manual_index: int = -1
    for index in range(rows.size()):
        if str(rows[index].slot_id) == "p10-live-manual":
            manual_index = index
            break
    if manual_index < 0 or menu.get_active_meta_screen() != "save_load":
        return _fail_bool("visible save/load screen omitted the production manual row")
    for _index in range(manual_index):
        if not menu.handle_ui_input(_ui_action("ui_down")):
            return _fail_bool("visible save/load screen did not consume row navigation")
    if not menu.handle_ui_input(_ui_action("ui_accept")):
        return _fail_bool("visible save/load screen did not consume load arm")
    var armed: Dictionary = menu.get_last_meta_screen_confirm_result()
    if str(armed.get("action", "")) != "arm" \
            or str(armed.get("detail", "")) != "p10-live-manual":
        return _fail_bool("visible save/load row did not arm the manual load")
    initial_playable._dispatch_save_load_confirm_result(armed)
    if not menu.handle_ui_input(_ui_action("ui_accept")):
        return _fail_bool("visible save/load screen did not consume load confirm")
    var confirmed: Dictionary = menu.get_last_meta_screen_confirm_result()
    if str(confirmed.get("action", "")) != "load" \
            or not bool(confirmed.get("ok", false)) \
            or str(confirmed.get("detail", "")) != "p10-live-manual":
        return _fail_bool("visible save/load screen did not prepare the selected manual row")
    initial_playable._dispatch_save_load_confirm_result(confirmed)
    var manual_loaded = live_main.get("playable_instance")
    if manual_loaded == null or manual_loaded == initial_playable:
        return _fail_bool("production manual menu load did not replace the playable: %s" % str(
            live_main.get_last_restore_failure_reason_for_validation()))
    if manual_loaded.menu_coordinator == null \
            or manual_loaded.save_load_menu != manual_loaded.menu_coordinator.get_save_load_menu():
        return _fail_bool("manual load did not rebind the authoritative menu/save pointers")
    if not _validate_nondefault_fire(manual_loaded, expected_fire):
        return _fail_bool("manual load changed current nested fire authority")
    initial_playable = manual_loaded
    service = initial_playable.get_save_load_service()

    # A prepared request is an opaque token+seal pair. No mutable candidate or
    # snapshot object is exposed to the caller, and mixing two capabilities is
    # rejected without replacing the live scene.
    var prepared_a: Dictionary = service.prepare_world_load()
    var prepared_b: Dictionary = service.prepare_world_load()
    if not bool(prepared_a.get("ok", false)) or not bool(prepared_b.get("ok", false)) \
            or prepared_a.has("candidate") or prepared_a.has("snapshot"):
        return _fail_bool("prepared request exposed mutable restore authority")
    var mixed: Dictionary = prepared_a.duplicate(true)
    mixed["seal"] = str(prepared_b.seal)
    if live_main.replace_playable_from_prepared(initial_playable, mixed) \
            or live_main.get("playable_instance") != initial_playable \
            or str(live_main.get_last_restore_failure_reason_for_validation()) \
                != "prepared_seal_mismatch":
        return _fail_bool("swapped prepared token/seal was not rejected atomically")
    service.discard_prepared_load(str(prepared_b.token))
    var mutated: Dictionary = service.prepare_world_load()
    mutated["seal"] = "post-prepare-mutation"
    if live_main.replace_playable_from_prepared(initial_playable, mutated) \
            or live_main.get("playable_instance") != initial_playable:
        return _fail_bool("post-prepare capability mutation replaced the live scene")
    if service.prepared_load_count_for_validation() != 0:
        return _fail_bool("rejected prepared requests leaked service authority")

    var expected_station_plan: Dictionary = initial_playable._crafting_station_position_summary()
    var expected_inventory: Dictionary = initial_playable.inventory_state.get_summary()
    var expected_run_id: String = str(initial_playable.get("_run_id"))
    var first_camera_before = initial_playable.get_viewport().get_camera_3d()
    var first_camera_id: int = first_camera_before.get_instance_id() \
        if is_instance_valid(first_camera_before) else 0
    if not initial_playable.request_load():
        return _fail_bool("first staged production load failed: %s" % str(
            live_main.get_last_restore_failure_reason_for_validation()))
    var loaded_once = live_main.get("playable_instance")
    if loaded_once == initial_playable or loaded_once == null \
            or str(loaded_once.get("_run_id")) != expected_run_id \
            or loaded_once.inventory_state.get_summary() != expected_inventory \
            or loaded_once._crafting_station_position_summary() != expected_station_plan:
        return _fail_bool("first staged production load changed saved authority")
    var first_camera_after = loaded_once.get_viewport().get_camera_3d()
    if not is_instance_valid(first_camera_after) or not first_camera_after.is_current() \
            or first_camera_after.get_instance_id() == first_camera_id:
        return _fail_bool("accepted staged load did not activate only the replacement camera")
    if not _validate_all_station_kinds_through_ordinary_interact(loaded_once):
        return false
    if not loaded_once.request_load():
        return _fail_bool("second staged production load failed: %s" % str(
            live_main.get_last_restore_failure_reason_for_validation()))
    var loaded_twice = live_main.get("playable_instance")
    if loaded_twice == loaded_once or loaded_twice == null \
            or str(loaded_twice.get("_run_id")) != expected_run_id \
            or loaded_twice.inventory_state.get_summary() != expected_inventory \
            or loaded_twice._crafting_station_position_summary() != expected_station_plan:
        return _fail_bool("second staged production load changed saved authority")
    if not _validate_nondefault_fire(loaded_twice, expected_fire):
        return _fail_bool("world load changed current nested fire authority")
    var restored_audio: Dictionary = loaded_twice.audio_manager.get_summary()
    if not _json_values_equal(
            loaded_twice.menu_coordinator.get_settings_summary(), expected_settings) \
            or str(restored_audio.get("current_voice_log_id", "")) \
                != str(expected_audio.get("current_voice_log_id", "")) \
            or not _json_values_equal(
                restored_audio.get("bus_config", {}), expected_audio.get("bus_config", {})):
        return _fail_bool("nondefault settings/audio persisted fields changed across two loads")
    if not _validate_all_station_kinds_through_ordinary_interact(loaded_twice):
        return false
    if not _validate_exact_authority_precision_and_oxygen_projection(loaded_twice):
        return false

    if not _validate_injected_rollback(
            loaded_twice, source_path, "after_rebuild", "injected_after_rebuild"):
        return false
    if not _validate_injected_rollback(
            loaded_twice, source_path, "after_world_apply", "injected_after_world_apply"):
        return false
    if not _validate_injected_rollback(
            loaded_twice, source_path, "before_activation", "staged_activation_failed"):
        return false
    if not _validate_changed_source_rollback(loaded_twice, source_path):
        return false
    if not _validate_staged_malformed_subsystem_rejections(loaded_twice):
        return false
    if not _validate_malformed_station_descriptors(loaded_twice, source_path):
        return false
    if not _validate_away_owner_graph(loaded_twice):
        return false
    var away_playable = live_main.get("playable_instance")
    if away_playable == null or not _validate_away_field_pin(away_playable):
        return false
    away_playable = live_main.get("playable_instance")
    if away_playable == null or not _validate_component_move_round_trips(away_playable):
        return false
    return true


func _validate_exact_authority_precision_and_oxygen_projection(playable) -> bool:
    if not _validate_oxygen_projection_context(playable, "postactivation", 0.0):
        return false
    var world = playable._build_world_snapshot()
    if world == null or not world.home_ship.get("oxygen_summary", null) is Dictionary:
        return _fail_bool("production world omitted oxygen authority")
    var changed_dict: Dictionary = world.to_dict()
    var changed_oxygen: Dictionary = changed_dict.home_ship.oxygen_summary
    changed_oxygen["drain_rate"] = float(changed_oxygen.get("drain_rate", 0.0)) + 0.125
    var changed_world = WorldSnapshotScript.from_dict(
        changed_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
        Engine.get_version_info()["string"])
    if changed_world == null \
            or playable._canonical_restore_world(world) \
                == playable._canonical_restore_world(changed_world):
        return _fail_bool("oxygen authority outside the overlap projection was normalized")
    var projected_dict: Dictionary = world.to_dict()
    var projected_oxygen: Dictionary = projected_dict.home_ship.oxygen_summary
    projected_oxygen["player_in_breach_zone"] = \
        not bool(projected_oxygen.get("player_in_breach_zone", false))
    var projected_world = WorldSnapshotScript.from_dict(
        projected_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
        Engine.get_version_info()["string"])
    if projected_world == null \
            or playable._canonical_restore_world(world) \
                != playable._canonical_restore_world(projected_world):
        return _fail_bool("documented oxygen overlap projection was not the exact exception")
    var precision_left: Variant = playable._canonical_json_value(
        {"quality_score": 0.293333333333333})
    var precision_right: Variant = playable._canonical_json_value(
        {"quality_score": 0.293333333333334})
    if precision_left == precision_right:
        return _fail_bool("canonical restore equality truncated sub-ULP lot quality")
    return true


func _validate_oxygen_projection_context(
        playable, label: String, delta: float) -> bool:
    playable._refresh_oxygen_state(false, delta)
    var expected_context: bool = playable._is_field_suit_pressure_active() \
        or (not bool(playable.get("away_from_start")) \
            and playable.is_player_in_breach_zone())
    if playable.oxygen_state.is_player_in_breach_zone() != expected_context:
        return _fail_bool("%s oxygen context did not match production occupancy" % label)
    return true


func _stage_nondefault_fire(playable) -> Dictionary:
    var state = playable.fire_suppression_state
    if state == null:
        _fail("production nested fire authority was unavailable")
        return {}
    var summary: Dictionary = state.get_summary()
    var compartments: Array = summary.get("compartments", []) as Array
    if compartments.is_empty():
        _fail("production nested fire authority had no compartments")
        return {}
    var primary: String = str(compartments[0])
    var secondary: String = str(compartments[1]) if compartments.size() > 1 else primary
    summary["active_fires"] = {primary: 1.3750000000000002}
    summary["suppressant_units"] = 73.12500000000001
    summary["spread_progress"] = {secondary: 0.293333333333333}
    summary["ignition_progress"] = {primary: 0.41750000000000004}
    summary["cascade_progress"] = 0.6250000000000001
    if not state.apply_summary(summary):
        _fail("production nondefault nested fire fixture was rejected")
        return {}
    return state.get_summary()


func _validate_nondefault_fire(playable, expected: Dictionary) -> bool:
    return playable != null and playable.fire_suppression_state != null \
        and _json_values_equal(
            playable.fire_suppression_state.get_summary(), expected)


func _validate_all_station_kinds_through_ordinary_interact(playable) -> bool:
    var by_kind: Dictionary = {}
    for station in playable.crafting_stations:
        if is_instance_valid(station):
            by_kind[str(station.station_kind)] = station
    for kind in ["fabricator", "medbay", "kitchen", "synthesizer", "workbench", "salvage"]:
        if not by_kind.has(kind):
            return _fail_bool("production floor plan left station unavailable: %s / %s" % [
                kind, str(playable._crafting_station_unavailable_by_owner)])
        if playable.recipe_picker_panel.is_open():
            playable.recipe_picker_panel.close()
        var station = by_kind[kind]
        playable.player.teleport_to(station.global_position)
        playable.recompute_occupancy()
        playable.player.request_interact()
        if not playable.recipe_picker_panel.is_open() \
                or playable.recipe_picker_panel.get_station_kind() != kind \
                or playable.recipe_picker_panel.get_station_instance_id() \
                    != str(station.station_instance_id):
            return _fail_bool("ordinary interact could not select station kind %s" % kind)
        playable.recipe_picker_panel.close()
    return true


func _ui_action(action_name: String) -> InputEventAction:
    var event := InputEventAction.new()
    event.action = action_name
    event.pressed = true
    return event


func _validate_away_owner_graph(playable) -> bool:
    playable.force_repair_all_for_validation()
    playable.board_piloted_ship_for_validation()
    playable.recompute_occupancy()
    var world = playable.get_synaptic_sea_world()
    var markers: Array = world.markers_in_range(playable.scanner_state.range_radius) \
        if world != null else []
    if markers.is_empty():
        return _fail_bool("production owner graph had no reachable away marker")
    var marker_id: String = str(markers[0].marker_id)
    var traveled: Dictionary = playable.travel_to_marker_id(marker_id)
    if not bool(traveled.get("success", false)):
        return _fail_bool("production away route failed: %s" % str(traveled))
    var opened: bool = playable.open_active_dock_barrier_for_validation()
    var boarded: bool = playable.board_host_for_validation() if opened else false
    if not opened or not boarded:
        return _fail_bool("production away owner could not be occupied opened=%s boarded=%s" % [
            opened, boarded])
    playable.recompute_occupancy()
    if not _validate_oxygen_projection_context(playable, "away activation tick", 0.125):
        return false
    var away = playable.get_current_host_for_validation()
    if away == null or away == playable.get_home_ship_for_validation():
        return _fail_bool("production away owner identity was not selected")
    var away_ship_id: String = str(away.ship_id)
    var station = _station_for(playable, away_ship_id, "workbench")
    if station == null or not _open_station_ordinary(playable, station) \
            or not _select_with_input(playable, "weld_plating"):
        return _fail_bool("production away workbench was not ordinarily reachable")
    _ensure_quantity(playable.inventory_state, "scrap_metal", 12)
    _ensure_quantity(playable.inventory_state, "adhesive_paste", 6)
    playable.recipe_picker_panel.refresh()
    if not _select_with_input(playable, "weld_plating"):
        return _fail_bool("production away paid recipe was not selectable")
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    var projection: Dictionary = playable.get_station_crafting_projection(
        "workbench", away_ship_id, str(station.station_instance_id),
        int(station.binding_generation))
    var running: Dictionary = _first_job_in_state(projection, "running")
    if running.is_empty():
        return _fail_bool("production away paid job did not start")
    var job_id: String = str(running.job_id)
    var station_id: String = str(station.station_instance_id)
    if not playable.travel_home():
        return _fail_bool("production away job could not be detached")
    playable.world_time += 60.0
    if not playable.request_save() or not playable.request_load():
        return _fail_bool("detached away job did not survive first world reload")
    playable = live_main.get("playable_instance")
    if playable == null or not playable.request_load():
        return _fail_bool("detached away job did not survive second world reload")
    playable = live_main.get("playable_instance")
    if playable == null:
        return _fail_bool("second away-job reload lost the playable")
    playable.board_piloted_ship_for_validation()
    playable.recompute_occupancy()
    var revisit: Dictionary = playable.travel_to_marker_id(marker_id)
    if not bool(revisit.get("success", false)) \
            or not playable.open_active_dock_barrier_for_validation() \
            or not playable.board_host_for_validation():
        return _fail_bool("detached away owner could not be revisited")
    playable.recompute_occupancy()
    if not _validate_oxygen_projection_context(playable, "away revisit", 0.0):
        return false
    var revisited = playable.get_current_host_for_validation()
    var revisited_station = _station_for(playable, away_ship_id, "workbench")
    var restored_job: Dictionary = playable.crafting_state.get_craft_job_scheduler() \
        .get_job(job_id)
    if revisited == null or str(revisited.ship_id) != away_ship_id \
            or revisited_station == null \
            or str(revisited_station.station_instance_id) != station_id \
            or str(restored_job.get("state", "")) != "collected":
        return _fail_bool(
            "first away revisit did not catch up the exact station owner " \
            + "owner=%s expected_owner=%s station=%s expected_station=%s job=%s" % [
                str(revisited.ship_id) if revisited != null else "<null>", away_ship_id,
                str(revisited_station.station_instance_id) \
                    if revisited_station != null else "<null>", station_id,
                str(restored_job)])
    var records: Array = revisited.get_pending_output_store().list_records_for_station(
        station_id)
    if records.size() != 1 or str((records[0] as Dictionary).producer_id) != job_id:
        return _fail_bool("away completion did not publish one exact pending receipt")
    _remove_all(playable.inventory_state, "plating")
    if not _open_station_ordinary(playable, revisited_station) \
            or not _select_with_input(playable, "collect_pending"):
        return _fail_bool("away pending receipt was not reachable through ordinary input")
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    if playable.inventory_state.get_quantity("plating") != 1 \
            or not revisited.get_pending_output_store().list_records_for_station(
                station_id).is_empty():
        return _fail_bool("away pending receipt was not collected exactly once")
    if not _validate_live_forfeited_cancellation(
            playable, away_ship_id, revisited_station):
        return false
    return true


func _validate_live_forfeited_cancellation(
        playable, away_ship_id: String, station) -> bool:
    _ensure_quantity(playable.inventory_state, "scrap_metal", 2)
    _ensure_quantity(playable.inventory_state, "adhesive_paste", 1)
    if not _open_station_ordinary(playable, station) \
            or not _select_with_input(playable, "weld_plating"):
        return _fail_bool("forfeited cancellation recipe was not ordinarily reachable")
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    var projection: Dictionary = playable.get_station_crafting_projection(
        "workbench", away_ship_id, str(station.station_instance_id),
        int(station.binding_generation))
    var running: Dictionary = _first_job_in_state(projection, "running")
    if running.is_empty():
        return _fail_bool("forfeited cancellation did not start a production job")
    var job_id: String = str(running.job_id)
    playable.advance_crafting_for_validation(2.0)
    var started: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(job_id)
    if str(started.get("state", "")) != "running" \
            or float(started.get("progress_seconds", 0.0)) <= 0.0 \
            or (started.get("consumed_lots", []) as Array).is_empty():
        return _fail_bool("production cancellation fixture did not reach paid mid-progress state")
    if not _open_station_ordinary(playable, station) \
            or not _select_with_input(playable, "cancel:%s" % job_id):
        return _fail_bool("mid-progress cancellation was not ordinarily selectable")
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    var cancelled: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(job_id)
    if str(cancelled.get("state", "")) != "cancelled" \
            or (cancelled.get("consumed_lots", []) as Array).is_empty() \
            or not (cancelled.get("refunded_lots_v1", []) as Array).is_empty() \
            or bool(cancelled.get("legacy_unreserved_cancelled_v1", true)) \
            or bool(cancelled.get("legacy_unrecorded_cancelled_v1", true)):
        return _fail_bool("mid-progress cancellation did not preserve exact forfeiture: %s" % str(
            cancelled))
    var expected: Dictionary = cancelled.duplicate(true)
    if not playable.request_save() or not playable.request_load():
        return _fail_bool("forfeited cancellation failed first production reload")
    playable = live_main.get("playable_instance")
    var first: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(job_id) \
        if playable != null else {}
    if playable == null or not _json_values_equal(first, expected) \
            or not playable.request_load():
        return _fail_bool("forfeited cancellation changed on first reload: %s" % str(first))
    playable = live_main.get("playable_instance")
    var second: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(job_id) \
        if playable != null else {}
    if playable == null or not _json_values_equal(second, expected):
        return _fail_bool("forfeited cancellation changed on second reload: %s" % str(second))
    return true


func _validate_away_field_pin(playable) -> bool:
    var away = playable.get_current_host_for_validation()
    if away == null or away == playable.get_home_ship_for_validation() \
            or str(away.marker_id).is_empty():
        return _fail_bool("field pin proof did not start aboard an away owner")
    var marker_id: String = str(away.marker_id)
    var away_ship_id: String = str(away.ship_id)
    _remove_all(playable.inventory_state, "field_bandage")
    _ensure_quantity(playable.inventory_state, "synth_fiber", 2)
    _ensure_quantity(playable.inventory_state, "medical_gauze", 1)
    playable.inventory_state.add_item("field_bandage", 99)
    var full_stack_quantity: int = playable.inventory_state.get_quantity("field_bandage")
    if full_stack_quantity <= 0:
        return _fail_bool("away field pin could not fill the destination stack")
    playable.vitals_state.stamina = playable.vitals_state.max_stamina
    if not playable.begin_field_craft_recipe("field_bandage"):
        return _fail_bool("production away field craft did not start")
    playable._process(9.0)
    if playable.field_crafting_state.is_crafting():
        return _fail_bool("production away field craft did not complete")
    var field_records: Array = away.get_pending_output_store().list_records_for_station(
        "field_crafting", true)
    if field_records.size() != 1 or away.floor_drop_descriptors.size() != 1:
        return _fail_bool("away field completion did not pin one physical receipt")
    var receipt: Dictionary = field_records[0] as Dictionary
    var receipt_id: String = str(receipt.get("receipt_id", ""))
    var original_lots: Array = (receipt.get("original_lots", []) as Array).duplicate(true)
    if receipt_id.is_empty() or original_lots.size() != 1 \
            or str((original_lots[0] as Dictionary).get("item_id", "")) != "field_bandage":
        return _fail_bool("away field receipt lost exact output provenance")
    if not playable.travel_home():
        return _fail_bool("away field pin could not return home")
    if not playable.request_save():
        return _fail_bool("away field pin save rejected scheduler=%s away_store=%s history=%s" % [
            str(playable.crafting_state.get_craft_job_scheduler().get_summary()),
            str(away.get_pending_output_store().get_summary()),
            str(playable.field_crafting_state.get_receipt_history_v1())])
    if not playable.request_load():
        return _fail_bool("away field pin did not survive first world reload reason=%s" % \
            str(live_main.get_last_restore_failure_reason_for_validation()))
    playable = live_main.get("playable_instance")
    if playable == null or not playable.request_load():
        return _fail_bool("away field pin did not survive second world reload")
    playable = live_main.get("playable_instance")
    if playable == null:
        return _fail_bool("away field pin second reload lost playable")
    if playable.inventory_state.get_quantity("field_bandage") != full_stack_quantity:
        return _fail_bool(
            "away field pin reload changed the full destination stack expected=%d actual=%d" % [
                full_stack_quantity,
                playable.inventory_state.get_quantity("field_bandage")])
    playable.board_piloted_ship_for_validation()
    playable.recompute_occupancy()
    var revisit: Dictionary = playable.travel_to_marker_id(marker_id)
    if not bool(revisit.get("success", false)) \
            or not playable.open_active_dock_barrier_for_validation() \
            or not playable.board_host_for_validation():
        return _fail_bool("away field pin owner could not be revisited")
    playable.recompute_occupancy()
    var revisited = playable.get_current_host_for_validation()
    if revisited == null or str(revisited.ship_id) != away_ship_id:
        return _fail_bool("away field pin rebound wrong ship")
    var restored_records: Array = revisited.get_pending_output_store() \
        .list_records_for_station("field_crafting", true)
    var restored_receipt_id: String = str(
        (restored_records[0] as Dictionary).get("receipt_id", "")) \
        if restored_records.size() == 1 else ""
    var restored_lots_json: Variant = JSON.parse_string(JSON.stringify(
        (restored_records[0] as Dictionary).get("original_lots", []), "", true, true)) \
        if restored_records.size() == 1 else null
    var expected_lots_json: Variant = JSON.parse_string(
        JSON.stringify(original_lots, "", true, true))
    var receipt_id_matches: bool = restored_receipt_id == receipt_id
    var lots_match: bool = restored_lots_json == expected_lots_json
    var drop_count_matches: bool = playable.work_yield_drops.size() == 1
    if restored_records.size() != 1 or not receipt_id_matches \
            or not lots_match or not drop_count_matches:
        return _fail_bool(
            ("away field pin did not restore exact receipt and floor holder records=%s " \
            + "expected_receipt=%s id_match=%s expected_lots=%s lots_match=%s " \
            + "drops=%d descriptors=%s") % [
                str(restored_records), receipt_id, str(receipt_id_matches),
                str(original_lots), str(lots_match),
                playable.work_yield_drops.size(), str(revisited.floor_drop_descriptors)])
    var drop = playable.work_yield_drops[0]
    playable.player.teleport_to(drop.global_position)
    playable.recompute_occupancy()
    var denied_descriptor: Dictionary = revisited.floor_drop_descriptors.duplicate(true)
    var denied_lots: Dictionary = drop.get_lot_summary().duplicate(true)
    var denied_pending: Dictionary = revisited.get_pending_output_store().get_summary() \
        .duplicate(true)
    playable.player.request_interact()
    if playable.inventory_state.get_quantity("field_bandage") != full_stack_quantity \
            or revisited.floor_drop_descriptors != denied_descriptor \
            or drop.get_lot_summary() != denied_lots \
            or revisited.get_pending_output_store().get_summary() != denied_pending:
        return _fail_bool("full inventory mutated the exact physical field receipt")
    _remove_all(playable.inventory_state, "field_bandage")
    playable.player.request_interact()
    if playable.inventory_state.get_quantity("field_bandage") != 1 \
            or not revisited.floor_drop_descriptors.is_empty() \
            or not revisited.get_pending_output_store().peek_remaining_lots(
                receipt_id).is_empty():
        return _fail_bool(
            ("away field floor holder was not ordinarily collected exactly once qty=%d " \
            + "descriptors=%s remaining=%s drops=%d occupancy=%s player=%s drop=%s") % [
                playable.inventory_state.get_quantity("field_bandage"),
                str(revisited.floor_drop_descriptors),
                str(revisited.get_pending_output_store().peek_remaining_lots(receipt_id)),
                playable.work_yield_drops.size(),
                str(playable.current_occupancy.ship_id) \
                    if playable.current_occupancy != null else "<null>",
                str(playable.player.global_position), str(drop.global_position)])
    playable.player.request_interact()
    if playable.inventory_state.get_quantity("field_bandage") != 1 \
            or not playable.recipe_picker_panel.is_open() \
            or playable.recipe_picker_panel.get_station_kind() != "workbench":
        return _fail_bool(
            "collected floor holder did not yield to the overlapped station on next press")
    playable.recipe_picker_panel.close()
    return true


func _validate_component_move_round_trips(playable) -> bool:
    # Leave room for two physical components during the cross-ship handoff.
    # The prior crafting scenarios deliberately populate the shared player
    # inventory; those unrelated stacks are not part of this move authority.
    for item_id in [
        "scrap_metal", "adhesive_paste", "plating", "field_bandage",
        "synth_fiber", "medical_gauze",
    ]:
        _remove_all(playable.inventory_state, item_id)
    var away = playable.get_current_host_for_validation()
    var home = playable.get_home_ship_for_validation()
    if away == null or home == null or away == home:
        return _fail_bool("component move proof did not start on an away ship")
    away.get_access().claim("player_local")
    var away_id: String = str(away.ship_id)
    var away_marker_id: String = str(away.marker_id)
    var home_id: String = str(home.ship_id)
    var away_placement = away.get_live_component_placement()
    var home_placement = home.get_live_component_placement()
    if away_placement == null or home_placement == null:
        return _fail_bool("component move proof lacked physical placement owners")
    var home_link_projection: Dictionary = _capture_component_link_projection(home_placement)
    if home_link_projection.is_empty():
        return _fail_bool("component move proof lacked both hard and soft live links")

    # Select the lowest stable lot in a profile that has a second away slot and
    # a home destination. The selected-lot policy is stable lot-ID order, so
    # later dismounting the other slot cannot substitute a different component.
    var home_sequence: int = int(home_placement.get_summary().get(
        "condition_lot_sequence", 0))
    var source: Dictionary = {}
    var away_destination: Dictionary = {}
    var home_destination: Dictionary = {}
    var mounted: Array = []
    for entry_v in away_placement.placed:
        if entry_v is Dictionary and bool((entry_v as Dictionary).get("mounted", false)) \
                and (entry_v as Dictionary).get("source_lot", null) is Dictionary:
            mounted.append((entry_v as Dictionary).duplicate(true))
    mounted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str((a.get("source_lot", {}) as Dictionary).get("lot_id", "")) \
            < str((b.get("source_lot", {}) as Dictionary).get("lot_id", "")))
    for candidate_v in mounted:
        var candidate: Dictionary = candidate_v as Dictionary
        var candidate_lot: Dictionary = candidate.get("source_lot", {}) as Dictionary
        if _component_lot_sequence(str(candidate_lot.get("lot_id", ""))) <= home_sequence:
            continue
        var profile_id: String = str(candidate.get("component_slot_profile_id", ""))
        for other_v in mounted:
            var other: Dictionary = other_v as Dictionary
            if str(other.get("component_instance_id", "")) \
                    == str(candidate.get("component_instance_id", "")) \
                    or str(other.get("component_slot_profile_id", "")) != profile_id:
                continue
            var other_lot_id: String = str(
                (other.get("source_lot", {}) as Dictionary).get("lot_id", ""))
            if str(candidate_lot.get("lot_id", "")) >= other_lot_id:
                continue
            for home_entry_v in home_placement.placed:
                if not home_entry_v is Dictionary:
                    continue
                var home_entry: Dictionary = home_entry_v as Dictionary
                if bool(home_entry.get("mounted", false)) \
                        and str(home_entry.get("component_slot_profile_id", "")) == profile_id \
                        and str(home_entry.get("item_form", "")) \
                            != str(other.get("item_form", "")) \
                        and str(home_entry.get("item_form", "")) \
                            != str(candidate.get("item_form", "")):
                    source = candidate
                    away_destination = other
                    home_destination = home_entry.duplicate(true)
                    break
            if not source.is_empty():
                break
        if not source.is_empty():
            break
    if source.is_empty():
        return _fail_bool(
            "no generated component lot exceeded the home allocator with compatible destinations")

    var source_slot: String = str(source.component_instance_id)
    var away_slot: String = str(away_destination.component_instance_id)
    var home_slot: String = str(home_destination.component_instance_id)
    var component_id: String = str(source.component_id)
    var item_form: String = str(source.item_form)
    var source_lot: Dictionary = (source.source_lot as Dictionary).duplicate(true)
    var source_lot_id: String = str(source_lot.lot_id)
    if not _open_component_panel_for_owner(playable, away_id) \
            or not playable.begin_p12_uninstall_for_validation(source_slot) \
            or not _complete_active_ship_work(playable) \
            or not playable.begin_p12_uninstall_for_validation(away_slot) \
            or not _complete_active_ship_work(playable):
        return _fail_bool("production away component dismount pair failed")
    var same_ship_selected: PackedStringArray = \
        playable._selected_lot_ids_for_requirements({item_form: 1})
    if same_ship_selected.size() != 1 or str(same_ship_selected[0]) != source_lot_id:
        return _fail_bool("stable component lot selection did not retain the move source")
    playable.ship_modification_panel.select_slot_id(away_slot)
    playable.ship_modification_panel.set_inventory(playable._inventory_qty_dict_for_work())
    if not playable.ship_modification_panel.install_into_selected(component_id, item_form) \
            or not _complete_active_ship_work(playable):
        return _fail_bool("production same-ship component remount failed")
    if not _validate_moved_component_authority(
            away_placement, source_slot, away_slot, source_lot, 1):
        return _fail_bool("same-ship move lost immutable lot/history authority")
    if not playable.request_save() or not playable.request_load():
        return _fail_bool("same-ship component move failed first reload reason=%s" % \
            str(live_main.get_last_restore_failure_reason_for_validation()))
    playable = live_main.get("playable_instance")
    if playable == null or not playable.request_load():
        return _fail_bool("same-ship component move failed second reload")
    playable = live_main.get("playable_instance")
    away = playable.get_current_host_for_validation()
    home = playable.get_home_ship_for_validation()
    away_placement = away.get_live_component_placement() if away != null else null
    home_placement = home.get_live_component_placement() if home != null else null
    if away_placement == null or not _validate_moved_component_authority(
            away_placement, source_slot, away_slot, source_lot, 1):
        return _fail_bool("same-ship component authority changed across two reloads")
    if home_placement == null or not _validate_component_link_projection(
            home_placement, home_link_projection):
        return _fail_bool("hard/soft component links did not reconstruct across reload")

    # Move the same immutable away lot into the lower-sequence home allocator.
    if not _open_component_panel_for_owner(playable, away_id):
        return _fail_bool("cross-ship move could not reopen the away component panel")
    if not playable.begin_p12_uninstall_for_validation(away_slot):
        return _fail_bool("cross-ship move could not begin away uninstall")
    if not _complete_active_ship_work(playable):
        return _fail_bool("cross-ship move could not finish away uninstall")
    if not playable.travel_home():
        return _fail_bool("cross-ship move could not travel home")
    playable.recompute_occupancy()
    home = playable.get_home_ship_for_validation()
    home_placement = home.get_live_component_placement() if home != null else null
    if home_placement == null:
        return _fail_bool("cross-ship move lost the home component placement")
    if not _open_component_panel_for_owner(playable, home_id):
        return _fail_bool("cross-ship move could not open the home component panel")
    if not playable.begin_p12_uninstall_for_validation(home_slot):
        return _fail_bool("cross-ship move could not begin home uninstall slot=%s entry=%s" % [
            home_slot, str(home_placement.get_entry(home_slot))])
    var home_uninstall_record: Dictionary = \
        playable.get_active_ship_work_record_for_validation()
    var expected_home_item: String = str(
        home_placement.get_entry(home_slot).get("item_form", ""))
    var actual_home_item: String = str(
        (home_uninstall_record.get("payload", {}) as Dictionary).get("item_form", ""))
    if actual_home_item != expected_home_item:
        return _fail_bool(
            "home uninstall bound stale item expected=%s actual=%s record=%s" % [
                expected_home_item, actual_home_item, str(home_uninstall_record)])
    if not _complete_active_ship_work(playable):
        return _fail_bool(
            "cross-ship move could not finish home uninstall active=%s result=%s record=%s" % [
                str(playable.has_active_ship_work_for_validation()),
                str(playable.get_last_ship_work_result_for_validation()),
                str(playable.get_active_ship_work_record_for_validation())
                + " expected_item=" + expected_home_item
                + " qty=" + str(playable.inventory_state.get_quantity(expected_home_item))
                + " inventory=" + str(playable.inventory_state.get_summary())])
    var selected_ids: PackedStringArray = playable._selected_lot_ids_for_requirements(
        {item_form: 1})
    if selected_ids.size() != 1 or str(selected_ids[0]) != source_lot_id:
        return _fail_bool("cross-ship install selected a different component lot")
    playable.ship_modification_panel.select_slot_id(home_slot)
    playable.ship_modification_panel.set_inventory(playable._inventory_qty_dict_for_work())
    if not playable.ship_modification_panel.install_into_selected(component_id, item_form) \
            or not _complete_active_ship_work(playable):
        return _fail_bool("production cross-ship component remount failed")
    away = playable._find_ship_by_id(away_id)
    away_placement = away.get_live_component_placement() if away != null else null
    if away_placement == null \
            or not _validate_moved_component_authority(
                away_placement, source_slot, away_slot, source_lot, 0) \
            or not _validate_mounted_lot(home_placement, home_slot, source_lot) \
            or _mounted_lot_count([away_placement, home_placement], source_lot_id) != 1:
        return _fail_bool("cross-ship move duplicated or rewrote immutable lot authority")
    if not playable.request_save() or not playable.request_load():
        return _fail_bool("cross-ship component move failed first reload reason=%s" % \
            str(live_main.get_last_restore_failure_reason_for_validation()))
    playable = live_main.get("playable_instance")
    if playable == null or not playable.request_load():
        return _fail_bool("cross-ship component move failed second reload")
    playable = live_main.get("playable_instance")
    # Component work can legitimately take the persisted propulsion projection
    # offline. Restore the validation ride before exercising the ordinary revisit;
    # the move authority itself remains exactly as saved across both reloads.
    playable.force_repair_all_for_validation()
    playable.board_piloted_ship_for_validation()
    playable.recompute_occupancy()
    var component_revisit: Dictionary = playable.travel_to_marker_id(away_marker_id)
    if not bool(component_revisit.get("success", false)):
        return _fail_bool("cross-ship component revisit travel failed: %s" % str(
            component_revisit))
    if not playable.open_active_dock_barrier_for_validation():
        return _fail_bool("cross-ship component revisit dock barrier did not open")
    if not playable.board_host_for_validation():
        return _fail_bool("cross-ship component revisit could not board source owner")
    playable.recompute_occupancy()
    home = playable.get_home_ship_for_validation()
    away = playable.get_current_host_for_validation()
    if away == null or str(away.ship_id) != away_id:
        return _fail_bool("cross-ship component revisit restored the wrong owner")
    home_placement = home.get_live_component_placement() if home != null else null
    away_placement = away.get_live_component_placement() if away != null else null
    if home_placement == null or away_placement == null \
            or not _validate_mounted_lot(home_placement, home_slot, source_lot) \
            or not _validate_moved_component_authority(
                away_placement, source_slot, away_slot, source_lot, 0) \
            or _mounted_lot_count([away_placement, home_placement], source_lot_id) != 1:
        return _fail_bool(
            ("cross-ship component authority changed across two reloads " \
            + "home_slot=%s home_entry=%s away_source=%s away_current=%s " \
            + "mounted_count=%d expected_lot=%s") % [
                home_slot,
                str(home_placement.get_entry(home_slot)) if home_placement != null else "<null>",
                str(away_placement.get_entry(source_slot)) if away_placement != null else "<null>",
                str(away_placement.get_entry(away_slot)) if away_placement != null else "<null>",
                _mounted_lot_count([away_placement, home_placement], source_lot_id)
                    if home_placement != null and away_placement != null else -1,
                str(source_lot)])
    return true


func _open_component_panel_for_owner(playable, ship_id: String) -> bool:
    if not bool(playable.select_ship_for_modification_for_validation(
            ship_id).get("ok", false)):
        return false
    if playable.ship_modification_panel.is_open():
        playable.ship_modification_panel.set_inventory(
            playable._inventory_qty_dict_for_work())
        return true
    return playable.open_ship_modification_panel_for_validation()


func _complete_active_ship_work(playable) -> bool:
    if not playable.has_active_ship_work_for_validation():
        return false
    playable.vitals_state.stamina = playable.vitals_state.max_stamina
    playable.move_player_to_active_ship_work_target_for_validation()
    for _step in range(200):
        playable.vitals_state.stamina = playable.vitals_state.max_stamina
        playable.advance_active_ship_work_for_validation(0.5)
        if not playable.has_active_ship_work_for_validation():
            return bool(playable.get_last_ship_work_result_for_validation().get("ok", false))
    return false


func _validate_moved_component_authority(
        placement, source_slot: String, current_slot: String,
        source_lot: Dictionary, expected_mounted: int) -> bool:
    var source_entry: Dictionary = placement.get_entry(source_slot)
    var current_entry: Dictionary = placement.get_entry(current_slot)
    if source_entry.is_empty() or current_entry.is_empty() \
            or bool(source_entry.get("mounted", true)):
        return false
    if not _json_values_equal(source_entry.get("source_lot", {}), source_lot) \
            or not _json_values_equal(current_entry.get("source_lot", {}), source_lot):
        return false
    return _mounted_lot_count([placement], str(source_lot.lot_id)) == expected_mounted


func _validate_mounted_lot(
        placement, slot_id: String, source_lot: Dictionary) -> bool:
    var entry: Dictionary = placement.get_entry(slot_id)
    return not entry.is_empty() and bool(entry.get("mounted", false)) \
        and _json_values_equal(entry.get("source_lot", {}), source_lot)


func _capture_component_link_projection(placement) -> Dictionary:
    var hard: Dictionary = {}
    var soft: Dictionary = {}
    for entry_v in placement.placed:
        if not entry_v is Dictionary:
            continue
        var entry: Dictionary = entry_v as Dictionary
        var system_id: String = str(entry.get("linked_system", ""))
        var subcomponent_id: String = str(entry.get("linked_subcomponent", ""))
        if system_id.is_empty() or subcomponent_id.is_empty():
            continue
        var row: Dictionary = {
            "component_instance_id": str(entry.get("component_instance_id", "")),
            "component_id": str(entry.get("component_id", "")),
            "linked_system": system_id,
            "linked_subcomponent": subcomponent_id,
        }
        if bool(entry.get("soft_linked", false)) and soft.is_empty():
            soft = row
        elif not bool(entry.get("soft_linked", false)) and hard.is_empty():
            hard = row
    if hard.is_empty() or soft.is_empty():
        return {}
    return {"hard": hard, "soft": soft}


func _validate_component_link_projection(placement, expected: Dictionary) -> bool:
    for kind in ["hard", "soft"]:
        var expected_row: Dictionary = expected.get(kind, {}) as Dictionary
        var actual: Dictionary = placement.get_entry(str(
            expected_row.get("component_instance_id", "")))
        if actual.is_empty() \
                or str(actual.get("component_id", "")) != str(
                    expected_row.get("component_id", "")) \
                or str(actual.get("linked_system", "")) != str(
                    expected_row.get("linked_system", "")) \
                or str(actual.get("linked_subcomponent", "")) != str(
                    expected_row.get("linked_subcomponent", "")) \
                or bool(actual.get("soft_linked", false)) != (kind == "soft"):
            return false
    return true


func _mounted_lot_count(placements: Array, lot_id: String) -> int:
    var count: int = 0
    for placement in placements:
        if placement == null:
            continue
        for entry_v in placement.placed:
            if entry_v is Dictionary and bool((entry_v as Dictionary).get("mounted", false)) \
                    and str(((entry_v as Dictionary).get(
                        "source_lot", {}) as Dictionary).get("lot_id", "")) == lot_id:
                count += 1
    return count


func _json_values_equal(left: Variant, right: Variant) -> bool:
    return JSON.parse_string(JSON.stringify(left, "", true, true)) \
        == JSON.parse_string(JSON.stringify(right, "", true, true))


func _component_lot_sequence(lot_id: String) -> int:
    var token: String = lot_id.get_slice(":components/lot-", 1)
    return int(token) if not token.is_empty() and token.is_valid_int() else -1


func _open_station_ordinary(playable, station) -> bool:
    if station == null or not is_instance_valid(station) or not station.is_inside_tree():
        return false
    if playable.recipe_picker_panel.is_open():
        playable.recipe_picker_panel.close()
    if playable.inventory_panel.is_open():
        playable.inventory_panel.close()
    playable.player.teleport_to(station.global_position)
    playable.recompute_occupancy()
    playable.player.request_interact()
    return playable.recipe_picker_panel.is_open() \
        and playable.recipe_picker_panel.get_ship_id() == str(station.ship_id) \
        and playable.recipe_picker_panel.get_station_instance_id() \
            == str(station.station_instance_id)


func _select_with_input(playable, expected_id: String) -> bool:
    var panel = playable.recipe_picker_panel
    for _index in range(panel.get_entry_count() + 1):
        if panel.get_selected_id() == expected_id:
            return true
        playable.dispatch_recipe_picker_input_for_validation("ui_down")
    return false


func _station_for(playable, ship_id: String, station_kind: String):
    for station in playable.crafting_stations:
        if is_instance_valid(station) and station.is_inside_tree() \
                and str(station.ship_id) == ship_id \
                and str(station.station_kind) == station_kind:
            return station
    return null


func _first_job_in_state(projection: Dictionary, state: String) -> Dictionary:
    for job_v in projection.get("jobs", []) as Array:
        if job_v is Dictionary and str((job_v as Dictionary).get("state", "")) == state:
            return (job_v as Dictionary).duplicate(true)
    return {}


func _ensure_quantity(inventory, item_id: String, minimum: int) -> void:
    var missing: int = maxi(0, minimum - int(inventory.get_quantity(item_id)))
    if missing > 0:
        inventory.add_item(item_id, missing)


func _remove_all(inventory, item_id: String) -> void:
    var quantity: int = int(inventory.get_quantity(item_id))
    if quantity > 0:
        inventory.remove_item(item_id, quantity)


func _validate_injected_rollback(
        playable, source_path: String, failure_point: String, expected_reason: String) -> bool:
    var service = playable.get_save_load_service()
    var world_before: Dictionary = _stable_world_dict(playable._build_world_snapshot())
    var active_run_before: String = service.get_active_run_id()
    var meta_before: Dictionary = _stable_meta(playable.meta_progression_state.to_dict())
    var visible_before: bool = playable.visible
    var process_before: int = int(playable.process_mode)
    var disk_before: String = FileAccess.get_file_as_string(source_path)
    var audio_server_before: Dictionary = _audio_server_summary()
    var audio_model_before: Dictionary = playable.audio_manager.get_summary()
    var playback_before: int = int(playable.audio_manager.call(
        "get_physical_playback_count_for_validation"))
    var camera_before = playable.get_viewport().get_camera_3d()
    var input_before: Dictionary = _input_map_summary()
    var disk_tree_before: Dictionary = _persistence_file_snapshot()
    live_main.set_restore_failure_point_for_validation(failure_point)
    var replaced: bool = playable.request_load()
    var failures: Array[String] = []
    if replaced: failures.append("replaced")
    if live_main.get("playable_instance") != playable: failures.append("pointer")
    if playable.get_parent() != live_main: failures.append("parent")
    if playable.visible != visible_before: failures.append("visible")
    if int(playable.process_mode) != process_before: failures.append("process")
    if service.get_active_run_id() != active_run_before: failures.append("active_run")
    if service.prepared_load_count_for_validation() != 0: failures.append("prepared")
    if _stable_meta(playable.meta_progression_state.to_dict()) != meta_before:
        failures.append("meta")
    if _stable_world_dict(playable._build_world_snapshot()) != world_before:
        failures.append("world")
    if FileAccess.get_file_as_string(source_path) != disk_before: failures.append("source")
    if _audio_server_summary() != audio_server_before: failures.append("audio_server")
    if playable.audio_manager.get_summary() != audio_model_before: failures.append("audio_model")
    if int(playable.audio_manager.call("get_physical_playback_count_for_validation")) \
            != playback_before:
        failures.append("playback")
    if playable.get_viewport().get_camera_3d() != camera_before: failures.append("camera")
    if _input_map_summary() != input_before: failures.append("input_map")
    var disk_tree_after: Dictionary = _persistence_file_snapshot()
    if disk_tree_after != disk_tree_before:
        failures.append("disk_tree:%s" % str(
            _dictionary_changed_keys(disk_tree_before, disk_tree_after)))
    if str(live_main.get_last_restore_failure_reason_for_validation()) != expected_reason:
        failures.append("reason:%s" % str(
            live_main.get_last_restore_failure_reason_for_validation()))
    if not failures.is_empty():
        return _fail_bool("%s rollback mismatch: %s" % [failure_point, failures])
    return true


func _validate_invalid_json_prepare_read_only(service: RefCounted) -> bool:
    var slot_id: String = "p10-invalid-json"
    var path: String = "user://saves/%s.json" % slot_id
    if not _write_text(path, "{invalid-json"):
        return _fail_bool("could not write invalid JSON fixture")
    var before: Dictionary = _persistence_file_snapshot()
    var rejected: Dictionary = service.prepare_slot_load(slot_id)
    if bool(rejected.get("ok", false)) \
            or str(rejected.get("reason", "")) != "invalid_json_object" \
            or _persistence_file_snapshot() != before:
        return _fail_bool("invalid JSON preparation mutated disk/index/diagnostics")
    return true


func _validate_exact_read_buffer_seal(service: RefCounted, fixture: Dictionary) -> bool:
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    var original: String = JSON.stringify(fixture, "", true, true)
    var replacement: String = original + "\n"
    if not _write_text(path, original):
        return _fail_bool("could not write exact read-buffer seal fixture")
    service.set_after_source_read_hook_for_validation(
        func(hook_path: String, _source_bytes: PackedByteArray) -> void:
            _write_text(hook_path, replacement))
    var prepared: Dictionary = service.prepare_world_load()
    service.set_after_source_read_hook_for_validation(Callable())
    if not bool(prepared.get("ok", false)):
        return _fail_bool("read-buffer race fixture did not prepare its captured bytes: %s" % str(
            prepared))
    var resolved: Dictionary = service.resolve_prepared_load(
        str(prepared.token), str(prepared.seal))
    service.discard_prepared_load(str(prepared.token))
    if bool(resolved.get("ok", false)) \
            or str(resolved.get("reason", "")) != "prepared_source_changed" \
            or _read_text(path) != replacement:
        return _fail_bool("source swapped after read escaped the exact-byte capability seal")
    return true


func _validate_staged_malformed_subsystem_rejections(playable) -> bool:
    var valid_world = playable._build_world_snapshot()
    if valid_world == null:
        return _fail_bool("could not capture malformed subsystem validation baseline")
    var cases: Array[Dictionary] = []
    var malformed_audio: Dictionary = valid_world.to_dict()
    malformed_audio.home_ship.audio_summary["current_voice_log_id"] = 42
    cases.append({"label": "audio", "world": malformed_audio})
    var malformed_settings: Dictionary = valid_world.to_dict()
    malformed_settings.home_ship.settings_summary["motion_reduce"] = "false"
    cases.append({"label": "settings", "world": malformed_settings})
    var malformed_systems: Dictionary = valid_world.to_dict()
    malformed_systems.home_ship.ship_systems_summary["systems"] = []
    cases.append({"label": "ship systems", "world": malformed_systems})
    var service = playable.get_save_load_service()
    for case_v in cases:
        var case: Dictionary = case_v
        var slot_id: String = "p10-malformed-%s" % str(case.label).replace(" ", "-")
        var path: String = "user://saves/%s.json" % slot_id
        var source: String = JSON.stringify(case.world, "", true, true)
        if not _write_text(path, source):
            return _fail_bool("could not write malformed %s staged fixture" % str(case.label))
        var prepared: Dictionary = service.prepare_slot_load(slot_id)
        if not bool(prepared.get("ok", false)):
            return _fail_bool("malformed %s did not reach staged apply: %s" % [
                str(case.label), str(prepared)])
        var pointer_before = live_main.get("playable_instance")
        var camera_before = playable.get_viewport().get_camera_3d()
        var world_before: Dictionary = _stable_world_dict(playable._build_world_snapshot())
        var source_before: String = _read_text(path)
        if live_main.replace_playable_from_prepared(playable, prepared) \
                or live_main.get("playable_instance") != pointer_before \
                or playable.get_viewport().get_camera_3d() != camera_before \
                or _stable_world_dict(playable._build_world_snapshot()) != world_before \
                or _read_text(path) != source_before \
                or service.prepared_load_count_for_validation() != 0:
            return _fail_bool("malformed %s staged rejection was not atomic" % str(case.label))
        _remove_if_exists(path)
    return true


func _persistence_file_snapshot() -> Dictionary:
    var result: Dictionary = {}
    if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://saves")):
        _append_directory_snapshot("user://saves", "saves", result)
    for path in ["user://meta_progression.json", "user://unlock_registry.json"]:
        if FileAccess.file_exists(path):
            result[path] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(path))
    return result


func _append_directory_snapshot(
        absolute_dir: String, relative_dir: String, result: Dictionary) -> void:
    var files: PackedStringArray = DirAccess.get_files_at(absolute_dir)
    files.sort()
    for filename in files:
        var relative_path: String = filename \
            if relative_dir.is_empty() else "%s/%s" % [relative_dir, filename]
        var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
            absolute_dir.path_join(filename))
        result[relative_path] = Marshalls.raw_to_base64(bytes)
    var directories: PackedStringArray = DirAccess.get_directories_at(absolute_dir)
    directories.sort()
    for dirname in directories:
        var child_relative: String = dirname \
            if relative_dir.is_empty() else "%s/%s" % [relative_dir, dirname]
        result["%s/" % child_relative] = "directory"
        _append_directory_snapshot(
            absolute_dir.path_join(dirname), child_relative, result)


func _dictionary_changed_keys(before: Dictionary, after: Dictionary) -> Array[String]:
    var changed: Array[String] = []
    var keys: Array = before.keys()
    for key in after:
        if not keys.has(key):
            keys.append(key)
    keys.sort()
    for key_v in keys:
        var key: String = str(key_v)
        if not before.has(key) or not after.has(key) or before[key] != after[key]:
            changed.append(key)
    return changed


func _stable_meta(summary: Dictionary) -> Dictionary:
    var result: Dictionary = summary.duplicate(true)
    result.erase("saved_at")
    return result


func _input_map_summary() -> Dictionary:
    var summary: Dictionary = {}
    var actions: Array = InputMap.get_actions()
    actions.sort()
    for action_v in actions:
        var action: StringName = action_v
        var events: Array[String] = []
        for event in InputMap.action_get_events(action):
            events.append(event.as_text())
        summary[str(action)] = {
            "deadzone": InputMap.action_get_deadzone(action),
            "events": events,
        }
    return summary


func _audio_server_summary() -> Dictionary:
    var result: Dictionary = {}
    for bus_index in range(AudioServer.bus_count):
        var bus_name: String = str(AudioServer.get_bus_name(bus_index))
        result[bus_name] = {
            "volume_db": AudioServer.get_bus_volume_db(bus_index),
            "muted": AudioServer.is_bus_mute(bus_index),
        }
    return result


func _validate_changed_source_rollback(playable, source_path: String) -> bool:
    var service = playable.get_save_load_service()
    var prepared: Dictionary = service.prepare_world_load()
    if not bool(prepared.get("ok", false)):
        return _fail_bool("source-change rollback could not prepare")
    var original_bytes: String = FileAccess.get_file_as_string(source_path)
    var changed_bytes: String = original_bytes + "\n"
    var world_before: Dictionary = _stable_world_dict(playable._build_world_snapshot())
    if not _write_text(source_path, changed_bytes):
        service.discard_prepared_load(str(prepared.get("token", "")))
        return _fail_bool("source-change rollback could not mutate fixture bytes")
    var replaced: bool = live_main.replace_playable_from_prepared(playable, prepared)
    var unchanged_during_rejection: bool = FileAccess.get_file_as_string(source_path) == changed_bytes
    var restored_source: bool = _write_text(source_path, original_bytes)
    if replaced or live_main.get("playable_instance") != playable \
            or not unchanged_during_rejection or not restored_source \
            or service.prepared_load_count_for_validation() != 0 \
            or _stable_world_dict(playable._build_world_snapshot()) != world_before \
            or str(live_main.get_last_restore_failure_reason_for_validation()) \
                != "prepared_source_changed":
        return _fail_bool("post-prepare source change was not rejected atomically")
    return true


func _validate_malformed_station_descriptors(playable, source_path: String) -> bool:
    var service = playable.get_save_load_service()
    var original_bytes: String = FileAccess.get_file_as_string(source_path)
    var original_v: Variant = JSON.parse_string(original_bytes)
    if not original_v is Dictionary:
        return _fail_bool("production world source was not JSON for station negatives")
    var original: Dictionary = original_v
    var home: Dictionary = original.get("home_ship", {}) as Dictionary
    var crafting: Dictionary = home.get("crafting_summary", {}) as Dictionary
    var position_summary: Dictionary = crafting.get(
        "physical_station_positions_v1", {}) as Dictionary
    var owners: Array = position_summary.get("owners", []) as Array
    if owners.is_empty() or not owners[0] is Dictionary \
            or ((owners[0] as Dictionary).get("stations", []) as Array).is_empty():
        return _fail_bool("production station descriptors were absent")

    var malformed_cases: Array = []
    var duplicate: Dictionary = original.duplicate(true)
    var duplicate_stations: Array = duplicate.home_ship.crafting_summary \
        .physical_station_positions_v1.owners[0].stations
    duplicate_stations.append((duplicate_stations[0] as Dictionary).duplicate(true))
    malformed_cases.append({"label": "duplicate", "world": duplicate})
    var missing_owner: Dictionary = original.duplicate(true)
    missing_owner.home_ship.crafting_summary.physical_station_positions_v1.owners = []
    malformed_cases.append({"label": "missing_owner", "world": missing_owner})
    var foreign_owner: Dictionary = original.duplicate(true)
    foreign_owner.home_ship.crafting_summary.physical_station_positions_v1 \
        .owners[0].ship_id = "foreign-station-owner"
    malformed_cases.append({"label": "foreign_owner", "world": foreign_owner})
    var bad_identity: Dictionary = original.duplicate(true)
    bad_identity.home_ship.crafting_summary.physical_station_positions_v1 \
        .owners[0].stations[0].floor_slot_id = "floor@wrong"
    malformed_cases.append({"label": "identity", "world": bad_identity})
    for case_v in malformed_cases:
        var case: Dictionary = case_v
        if not _write_world_source(service, case.world as Dictionary):
            _write_text(source_path, original_bytes)
            return _fail_bool("could not write malformed station %s" % str(case.label))
        var rejected: Dictionary = service.prepare_world_load()
        if bool(rejected.get("ok", false)):
            service.discard_prepared_load(str(rejected.get("token", "")))
            _write_text(source_path, original_bytes)
            return _fail_bool("malformed station %s was accepted" % str(case.label))

    # A self-consistent but off-layout floor identity passes detached schema
    # validation, then the disposable scene rejects it against authored floors.
    var off_layout: Dictionary = original.duplicate(true)
    var station: Dictionary = off_layout.home_ship.crafting_summary \
        .physical_station_positions_v1.owners[0].stations[0]
    var kind: String = str(station.station_kind)
    station.local_position = [9999.0, 9999.0, 9999.0]
    station.floor_slot_id = "floor@9999000,9999000,9999000"
    station.station_instance_id = "station:%s@9999000,9999000,9999000" % kind
    if not _rewrite_station_references(off_layout.home_ship.crafting_summary, kind, station) \
            or not _write_world_source(service, off_layout):
        _write_text(source_path, original_bytes)
        return _fail_bool("could not prepare off-layout station descriptor")
    var world_before: Dictionary = _stable_world_dict(playable._build_world_snapshot())
    var off_layout_prepared: Dictionary = service.prepare_world_load()
    if not bool(off_layout_prepared.get("ok", false)):
        var rejected_without_mutation: bool = (
            _stable_world_dict(playable._build_world_snapshot()) == world_before \
            and FileAccess.get_file_as_string(source_path) \
                == JSON.stringify(off_layout, "\t", true, true))
        var restored_detached: bool = _write_world_source(service, original)
        if not rejected_without_mutation or not restored_detached:
            return _fail_bool("off-layout detached rejection mutated live or disk state")
        return true
    var replaced: bool = live_main.replace_playable_from_prepared(playable, off_layout_prepared)
    var restored: bool = _write_world_source(service, original)
    if replaced or not restored or live_main.get("playable_instance") != playable \
            or _stable_world_dict(playable._build_world_snapshot()) != world_before \
            or str(live_main.get_last_restore_failure_reason_for_validation()) \
                != "staged_station_layout_mismatch":
        return _fail_bool("off-layout station descriptor did not fail in disposable staging")
    return true


func _rewrite_station_references(
        crafting: Dictionary, kind: String, station: Dictionary) -> bool:
    var summaries: Dictionary = crafting.get("physical_station_summaries", {}) as Dictionary
    var prior_id: String = ""
    var replacement: Dictionary = {}
    for station_id_v in summaries:
        var summary_v: Variant = summaries[station_id_v]
        if summary_v is Dictionary and str((summary_v as Dictionary).get("station_kind", "")) == kind:
            prior_id = str(station_id_v)
            replacement = (summary_v as Dictionary).duplicate(true)
            replacement["station_instance_id"] = str(station.station_instance_id)
            break
    if not prior_id.is_empty():
        summaries.erase(prior_id)
        summaries[str(station.station_instance_id)] = replacement
    var jobs: Dictionary = crafting.get("craft_jobs_v1", {}) as Dictionary
    for owner_v in jobs.get("owners", []) as Array:
        if owner_v is Dictionary and str((owner_v as Dictionary).get(
                "station_instance_id", "")) == prior_id:
            (owner_v as Dictionary)["station_instance_id"] = str(station.station_instance_id)
    return true


func _write_world_source(service, world: Dictionary) -> bool:
    if not _write_text(
            SaveLoadServiceScript.WORLD_SLOT_FILE,
            JSON.stringify(world, "\t", true, true)):
        return false
    service.call(
        "_write_cloud_manifest", "world", SaveLoadServiceScript.WORLD_SLOT_FILE,
        str(world.get("slice_version", "")))
    return true


func _stable_world_dict(world) -> Dictionary:
    var result: Dictionary = world.to_dict()
    result["saved_at"] = ""
    if result.get("home_ship", null) is Dictionary:
        result.home_ship["saved_at"] = ""
    if result.get("meta_progression_summary", null) is Dictionary:
        result.meta_progression_summary["saved_at"] = ""
    return JSON.parse_string(JSON.stringify(result, "", true, true)) as Dictionary


func _validate_legacy_run(service: RefCounted, fixture: Dictionary) -> bool:
    var slot_id: String = "p10-legacy"
    var path: String = "user://saves/%s.json" % slot_id
    var original: String = JSON.stringify(fixture, "  ", true, true)
    if not _write_text(path, original):
        return _fail_bool("could not write legacy run")
    service.set_active_run_id("fixture-run")
    var prepared: Dictionary = service.prepare_run_load(slot_id, "fixture-run")
    if not bool(prepared.get("ok", false)) or not bool(prepared.get("migrated", false)) \
            or _read_text(path) != original or FileAccess.file_exists(path.trim_suffix(".json") + ".migrated.json"):
        return _fail_bool("legacy run was not prepared without source mutation")
    var world = _prepared_world(service, prepared)
    var snapshot = RunSnapshotScript.from_dict(
        world.home_ship if world != null else {},
        SaveLoadServiceScript.CURRENT_SLICE_VERSION,
        Engine.get_version_info()["string"])
    if snapshot == null or str(world.slice_version) != "world-6" \
            or str(snapshot.slice_version) != "gate2-current-run-6":
        return _fail_bool("legacy run did not migrate to v6")
    var legacy_component: Dictionary = snapshot.component_placement_summary
    var legacy_placed: Array = legacy_component.get("placed", []) as Array
    if int(legacy_component.get("condition_authority_version", 0)) != 1 \
            or int(legacy_component.get("condition_lot_sequence", 0)) != 1 \
            or legacy_placed.size() != 1 \
            or str(((legacy_placed[0] as Dictionary).source_lot as Dictionary).origin.kind) != "legacy_unrecorded_component" \
            or absf(float(((legacy_placed[0] as Dictionary).source_lot as Dictionary).condition) - 0.42) > 0.0001:
        return _fail_bool("trusted legacy component did not receive one stable neutral lot")
    var crafting = CraftingStateScript.new()
    if not crafting.configure_legacy_restore_owner("ship-home", "player:fixture-run") \
            or not crafting.apply_summary(snapshot.crafting_summary):
        return _fail_bool("legacy crafting bridge could not materialize")
    var scheduler: RefCounted = crafting.get_craft_job_scheduler()
    var summary: Dictionary = scheduler.get_summary()
    var jobs: Array = summary.get("jobs", []) as Array
    if jobs.size() != 3:
        return _fail_bool("legacy job count/order was not retained")
    var paid: Dictionary = jobs[0] as Dictionary
    if str(paid.get("state", "")) != "running" \
            or absf(float(paid.get("progress_seconds", 0.0)) - 6.0) > 0.0001 \
            or not paid.get("ingredient_escrow", []).is_empty() \
            or not paid.get("legacy_consumed_history_v1", null) is Dictionary:
        return _fail_bool("paid legacy work lost progress or paid-history evidence")
    for index in range(1, jobs.size()):
        var blocked: Dictionary = jobs[index] as Dictionary
        if str(blocked.get("state", "")) != "blocked_unreserved" \
                or not blocked.get("ingredient_escrow", []).is_empty() \
                or not blocked.get("consumed_lots", []).is_empty():
            return _fail_bool("legacy queue acquired value before admission")
    var inventory = InventoryStateScript.new("player:fixture-run")
    var pending = PendingOutputStoreScript.new()
    if not pending.configure("ship-home") \
            or not crafting.bind_legacy_migration_jobs(inventory, null, null, pending):
        return _fail_bool("migration-only station did not bind its live holder")
    crafting.tick(9.0)
    if inventory.get_quantity("scrap_metal") != 0:
        return _fail_bool("paid legacy work charged inventory again")
    var finished: Dictionary = crafting.finish_craft()
    if str(finished.get("item_id", "")) != "plating" \
            or str(finished.get("quality_tier", "")) != "good" \
            or not bool(finished.get("pending", false)):
        return _fail_bool("paid legacy output did not preserve historical quality")
    var blocked_id: String = str((jobs[1] as Dictionary).get("job_id", ""))
    var before_failed: Dictionary = scheduler.get_job(blocked_id)
    var denied: Dictionary = crafting.admit_legacy_unreserved(blocked_id, inventory)
    if bool(denied.get("ok", false)) or scheduler.get_job(blocked_id) != before_failed:
        return _fail_bool("failed legacy admission mutated blocked intent")
    var recipe_id: String = str(before_failed.get("recipe_id", ""))
    var recipe: Dictionary = crafting.get_recipe(recipe_id)
    for item_variant in (recipe.get("ingredients", {}) as Dictionary):
        inventory.add_item(str(item_variant), int(recipe.ingredients[item_variant]))
    var quantities_before: Dictionary = inventory.items.duplicate(true)
    var admitted: Dictionary = crafting.admit_legacy_unreserved(blocked_id, inventory, null, 99)
    if not bool(admitted.get("ok", false)) \
            or str(scheduler.get_job(blocked_id).get("state", "")) != "queued":
        return _fail_bool("explicit legacy admission did not reserve current inputs: %s / %s" % [
            str(admitted), str(scheduler.get_job(blocked_id))])
    var station_id: String = str(before_failed.get("station_instance_id", ""))
    var legacy_ship_id: String = str(before_failed.get("ship_id", ""))
    if crafting.enqueue_craft(recipe_id, 1, null, inventory, null, 0, legacy_ship_id, station_id) != 0:
        return _fail_bool("migration-only station accepted generic new work")
    var cancelled: Dictionary = crafting.cancel_job(blocked_id, legacy_ship_id, station_id)
    if not bool(cancelled.get("ok", false)) or inventory.items != quantities_before:
        return _fail_bool("newly reserved legacy admission did not refund exactly once: cancelled=%s before=%s after=%s" % [
            str(cancelled), str(quantities_before), str(inventory.items)])
    if not service.write_prepared_migration_copy(str(prepared.token)) \
            or not FileAccess.file_exists(path.trim_suffix(".json") + ".migrated.json") \
            or _read_text(path) != original:
        return _fail_bool("accepted migration sidecar changed its source")
    service.discard_prepared_load(str(prepared.token))
    var stale: Dictionary = service.prepare_run_load(slot_id, "fixture-run")
    if not bool(stale.get("ok", false)):
        return _fail_bool("legacy run could not be prepared for stale-token proof")
    if not _write_text(path, original + "\n") \
            or service.write_prepared_migration_copy(str(stale.token)):
        return _fail_bool("changed source did not invalidate prepared migration token")
    service.discard_prepared_load(str(stale.token))
    return true


func _validate_current_run(service: RefCounted, fixture: Dictionary) -> bool:
    var slot_id: String = "p10-current"
    var path: String = "user://saves/%s.json" % slot_id
    if not _write_text(path, JSON.stringify(fixture, "", true, true)):
        return _fail_bool("could not write current run")
    var prepared: Dictionary = service.prepare_run_load(slot_id, "fixture-run")
    if bool(prepared.get("ok", false)) or _read_text(path) != JSON.stringify(fixture, "", true, true):
        return _fail_bool("standalone transactional v5 did not preserve its open owner-graph rejection")
    var malformed_legacy_hotbar: Dictionary = fixture.duplicate(true)
    malformed_legacy_hotbar.inventory_summary["combat_hotbar_text"] = 17
    var malformed_legacy_result: Dictionary = SaveMigrationServiceScript.new().migrate_run(
        malformed_legacy_hotbar)
    if malformed_legacy_result.get("dict", null) is Dictionary \
            or str(malformed_legacy_result.get("reason", "")) \
                != "combat_migration_invalid_hotbar_text":
        return _fail_bool("legacy non-String combat hotbar text did not reject exactly")
    var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_run(fixture)
    if not migrated.get("dict", null) is Dictionary:
        return _fail_bool("valid v5 run did not migrate to a detached v6 dictionary")
    fixture = (migrated.dict as Dictionary).duplicate(true)
    var layout_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(fixture.layout_path)))
    var definitions_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/combat/threat_archetypes.json"))
    if not layout_v is Dictionary or not definitions_v is Dictionary:
        return _fail_bool("could not load canonical combat initialization inputs")
    var initialized: Dictionary = ThreatInitialStateBuilderScript.build_initial_v2(
        layout_v as Dictionary, (layout_v as Dictionary).get("encounters", []),
        Vector3.ZERO, definitions_v as Dictionary)
    if not bool(initialized.get("ok", false)):
        return _fail_bool("could not initialize current v6 combat: %s" % str(initialized))
    fixture.inventory_summary["threat_summary"] = initialized.summary
    var current_hotbar_text: String = "Current hotbar | Threat 0.625 | exact"
    fixture.inventory_summary["combat_hotbar_text"] = current_hotbar_text
    var snapshot = RunSnapshotScript.from_dict(
        fixture, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
        Engine.get_version_info()["string"])
    if snapshot == null:
        return _fail_bool("migrated current v6 could not decode as an internal world member")
    if str(snapshot.inventory_summary.get("combat_hotbar_text", "")) != current_hotbar_text:
        return _fail_bool("current nonempty combat hotbar text changed during decode")
    var missing_current_hotbar: Dictionary = fixture.duplicate(true)
    missing_current_hotbar.inventory_summary.erase("combat_hotbar_text")
    if RunSnapshotScript.from_dict(
            missing_current_hotbar, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
            Engine.get_version_info()["string"]) != null:
        return _fail_bool("current v6 accepted missing combat hotbar text")
    var malformed_current_hotbar: Dictionary = fixture.duplicate(true)
    malformed_current_hotbar.inventory_summary["combat_hotbar_text"] = 17
    if RunSnapshotScript.from_dict(
            malformed_current_hotbar, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
            Engine.get_version_info()["string"]) != null:
        return _fail_bool("current v6 accepted non-String combat hotbar text")
    if not _validate_current_component_contract_mutants(fixture):
        return false
    if not _validate_current_terminal_contract_mutants(fixture):
        return false
    var malformed_oxygen_context: Dictionary = fixture.duplicate(true)
    if not malformed_oxygen_context.get("oxygen_summary", null) is Dictionary:
        malformed_oxygen_context["oxygen_summary"] = {}
    malformed_oxygen_context.oxygen_summary["player_in_breach_zone"] = "true"
    if RunSnapshotScript.from_dict(
            malformed_oxygen_context, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
            Engine.get_version_info()["string"]) != null:
        return _fail_bool("current v5 accepted malformed oxygen overlap context")
    var missing_authority: Dictionary = fixture.duplicate(true)
    missing_authority.component_placement_summary.erase("condition_authority_version")
    if RunSnapshotScript.from_dict(
            missing_authority, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
            Engine.get_version_info()["string"]) != null:
        return _fail_bool("current v5 accepted missing component authority fields")
    var missing_lot: Dictionary = fixture.duplicate(true)
    (missing_lot.component_placement_summary.placed[0] as Dictionary).erase("source_lot")
    if RunSnapshotScript.from_dict(
            missing_lot, SaveLoadServiceScript.CURRENT_SLICE_VERSION,
            Engine.get_version_info()["string"]) != null:
        return _fail_bool("current v5 received trusted-legacy missing-lot privilege")
    var crafting = CraftingStateScript.new()
    if not crafting.apply_summary(snapshot.crafting_summary):
        return _fail_bool("current craft jobs were rejected")
    var normalized_crafting: Dictionary = crafting.get_summary()
    var crafting_replay = CraftingStateScript.new()
    if not crafting_replay.apply_summary(normalized_crafting) \
            or crafting_replay.get_summary() != normalized_crafting:
        return _fail_bool("current craft jobs did not round-trip exactly")
    var knowledge = RecipeKnowledgeStateScript.new()
    knowledge.configure("player:fixture-run", crafting._recipes)
    if not knowledge.apply_summary(snapshot.recipe_knowledge_summary):
        return _fail_bool("current knowledge evidence was rejected")
    var normalized_knowledge: Dictionary = knowledge.get_summary()
    var knowledge_replay = RecipeKnowledgeStateScript.new()
    knowledge_replay.configure("player:fixture-run", crafting._recipes)
    if not knowledge_replay.apply_summary(normalized_knowledge) \
            or knowledge_replay.get_summary() != normalized_knowledge:
        return _fail_bool("current knowledge evidence did not round-trip exactly")
    var before_replay: Dictionary = knowledge.get_summary()
    var replay_result: Dictionary = knowledge.receive_codex_discovery(
        "unused", "codex:alpha-2", crafting._recipes)
    if not bool(replay_result.get("ok", false)) \
            or not bool(replay_result.get("already_received", false)) \
            or knowledge.get_summary() != before_replay:
        return _fail_bool("knowledge receipt replay was not idempotent")
    var placement = ComponentPlacementStateScript.new()
    if not placement.apply_summary(snapshot.component_placement_summary, "ship_start"):
        return _fail_bool("current component source lot was rejected")
    var normalized_placement: Dictionary = placement.get_summary()
    var placement_replay = ComponentPlacementStateScript.new()
    if not placement_replay.apply_summary(normalized_placement) \
            or placement_replay.get_summary() != normalized_placement:
        return _fail_bool("component source lot did not round-trip exactly")
    return true


func _validate_current_component_contract_mutants(fixture: Dictionary) -> bool:
    var expected_version: String = SaveLoadServiceScript.CURRENT_SLICE_VERSION
    var expected_godot: String = Engine.get_version_info()["string"]
    for malformed_mounted in [null, "false", 0]:
        var malformed: Dictionary = fixture.duplicate(true)
        var entry: Dictionary = malformed.component_placement_summary.placed[0]
        if malformed_mounted == null:
            entry.erase("mounted")
        else:
            entry["mounted"] = malformed_mounted
        if RunSnapshotScript.from_dict(malformed, expected_version, expected_godot) != null:
            return _fail_bool("current component accepted malformed mounted=%s" % str(
                malformed_mounted))
        var malformed_model = ComponentPlacementStateScript.new()
        if malformed_model.apply_summary(
                malformed.component_placement_summary, "ship_start"):
            return _fail_bool("component model accepted malformed mounted=%s" % str(
                malformed_mounted))
    var duplicate_bypass: Dictionary = fixture.duplicate(true)
    var duplicate_entry: Dictionary = (
        duplicate_bypass.component_placement_summary.placed[0] as Dictionary).duplicate(true)
    duplicate_entry["component_instance_id"] = "%s-history" % str(
        duplicate_entry.component_instance_id)
    duplicate_entry["mounted"] = "false"
    duplicate_bypass.component_placement_summary.placed.append(duplicate_entry)
    duplicate_bypass.component_placement_summary["count"] = (
        duplicate_bypass.component_placement_summary.placed as Array).size()
    if RunSnapshotScript.from_dict(
            duplicate_bypass, expected_version, expected_godot) != null:
        return _fail_bool("malformed mounted string bypassed duplicate lot authority")
    var duplicate_model = ComponentPlacementStateScript.new()
    if duplicate_model.apply_summary(
            duplicate_bypass.component_placement_summary, "ship_start"):
        return _fail_bool("component model allowed malformed mounted duplicate bypass")
    for origin_mutation in ["erase_kind", "wrong_kind", "erase_ship"]:
        var malformed_origin: Dictionary = fixture.duplicate(true)
        var source_lot: Dictionary = (
            malformed_origin.component_placement_summary.placed[0].source_lot as Dictionary)
        source_lot["lot_id"] = "ship:ship_start:components/lot-000001"
        source_lot["origin"] = {
            "kind": "generated_component",
            "ship_id": "ship_start",
            "slot_id": "slot-power-1",
            "placement_seed": int(malformed_origin.component_placement_summary.seed),
        }
        var origin: Dictionary = source_lot.origin as Dictionary
        match origin_mutation:
            "erase_kind":
                origin.erase("kind")
            "wrong_kind":
                origin["kind"] = "forged_component"
            "erase_ship":
                origin.erase("ship_id")
        if RunSnapshotScript.from_dict(
                malformed_origin, expected_version, expected_godot) != null:
            return _fail_bool("reserved component lot accepted malformed %s" % origin_mutation)
        var placement = ComponentPlacementStateScript.new()
        if placement.apply_summary(
                malformed_origin.component_placement_summary, "ship_start"):
            return _fail_bool("component model accepted malformed %s" % origin_mutation)
    return true


func _validate_current_terminal_contract_mutants(fixture: Dictionary) -> bool:
    var expected_version: String = SaveLoadServiceScript.CURRENT_SLICE_VERSION
    var expected_godot: String = Engine.get_version_info()["string"]
    for deleted_key in [
        "refunded_lots_v1",
        "legacy_unreserved_cancelled_v1",
        "legacy_unrecorded_cancelled_v1",
    ]:
        var deleted_job_field: Dictionary = fixture.duplicate(true)
        (deleted_job_field.crafting_summary.craft_jobs_v1.jobs[0] as Dictionary).erase(
            deleted_key)
        if RunSnapshotScript.from_dict(
                deleted_job_field, expected_version, expected_godot) != null:
            return _fail_bool("craft-jobs-2 accepted deleted %s" % deleted_key)
    var deleted_history: Dictionary = fixture.duplicate(true)
    deleted_history.crafting_summary.field_crafting.field_pending_v1.erase(
        "receipt_history_v1")
    if RunSnapshotScript.from_dict(
            deleted_history, expected_version, expected_godot) != null:
        return _fail_bool("field-pending-2 accepted deleted receipt history")
    var changed_schema: Dictionary = fixture.duplicate(true)
    changed_schema.crafting_summary.field_crafting.field_pending_v1["schema"] = (
        "field-pending-1")
    if RunSnapshotScript.from_dict(
            changed_schema, expected_version, expected_godot) != null:
        return _fail_bool("current run accepted downgraded field pending schema")
    return true


func _validate_terminal_authority_matrix(
        service: RefCounted, world_fixture: Dictionary, run_fixture: Dictionary) -> bool:
    if not _validate_field_receipt_authority_mutants(service, world_fixture):
        return false
    if not _validate_refund_receipt_authority_mutants(service, world_fixture):
        return false
    if not _validate_legacy_terminal_contracts(service, world_fixture, run_fixture):
        return false
    return true


func _validate_field_receipt_authority_mutants(
        service: RefCounted, fixture: Dictionary) -> bool:
    var mutations: Array[Dictionary] = []
    var wrong_sequence: Dictionary = fixture.duplicate(true)
    wrong_sequence.home_ship.crafting_summary.field_crafting.field_pending_v1[
        "receipt_sequence"] = 3
    mutations.append({"label": "field receipt wrong sequence", "world": wrong_sequence})

    var wrong_origin: Dictionary = fixture.duplicate(true)
    var wrong_origin_lot: Dictionary = (
        wrong_origin.home_ship.crafting_summary.field_crafting.field_pending_v1
            .receipt_history_v1[0].original_lots[0] as Dictionary)
    wrong_origin_lot.origin["field_receipt_id"] = "field_crafting/job-000003/output"
    var wrong_origin_record: Dictionary = wrong_origin.home_pending_outputs_v1.records[0]
    wrong_origin_record.original_lots = [wrong_origin_lot.duplicate(true)]
    wrong_origin_record.remaining_lots = [wrong_origin_lot.duplicate(true)]
    mutations.append({"label": "field receipt forged origin", "world": wrong_origin})

    var wrong_content: Dictionary = fixture.duplicate(true)
    var wrong_content_lot: Dictionary = (
        wrong_content.home_ship.crafting_summary.field_crafting.field_pending_v1
            .receipt_history_v1[0].original_lots[0] as Dictionary)
    wrong_content_lot["item_id"] = "scrap_metal"
    wrong_content_lot["quantity"] = 2
    var wrong_content_record: Dictionary = wrong_content.home_pending_outputs_v1.records[0]
    wrong_content_record.original_lots = [wrong_content_lot.duplicate(true)]
    wrong_content_record.remaining_lots = [wrong_content_lot.duplicate(true)]
    mutations.append({"label": "field receipt forged content", "world": wrong_content})

    var duplicate_history: Dictionary = fixture.duplicate(true)
    duplicate_history.home_ship.crafting_summary.field_crafting.field_pending_v1 \
        .receipt_history_v1.append(duplicate_history.home_ship.crafting_summary \
            .field_crafting.field_pending_v1.receipt_history_v1[0].duplicate(true))
    mutations.append({"label": "duplicate field receipt history", "world": duplicate_history})

    for key in ["ship_id", "station_instance_id", "source_holder_id"]:
        var wrong_link: Dictionary = fixture.duplicate(true)
        var record: Dictionary = wrong_link.home_pending_outputs_v1.records[0]
        match key:
            "ship_id":
                record[key] = "ship-foreign"
            "station_instance_id":
                record[key] = "station:forged@0,0,0"
            "source_holder_id":
                record[key] = "player:forged"
        mutations.append({"label": "field receipt wrong %s" % key, "world": wrong_link})

    for mutation in mutations:
        if not _validate_rejected_world(
                service, mutation.world as Dictionary, str(mutation.label)):
            return false
    return true


func _validate_refund_receipt_authority_mutants(
        service: RefCounted, fixture: Dictionary) -> bool:
    var refund_fixture: Dictionary = _build_current_refund_world(fixture)
    if refund_fixture.is_empty():
        return _fail_bool("could not build production refund authority fixture")
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    if not _write_text(path, JSON.stringify(refund_fixture, "", true, true)):
        return _fail_bool("could not write current refund authority fixture")
    var accepted: Dictionary = service.prepare_world_load()
    var accepted_world = _prepared_world(service, accepted)
    if not bool(accepted.get("ok", false)) or accepted_world == null:
        return _fail_bool("exact production refund authority was rejected: %s" % str(accepted))
    service.discard_prepared_load(str(accepted.token))

    var jobs: Array = refund_fixture.home_ship.crafting_summary.craft_jobs_v1.jobs
    var records: Array = refund_fixture.home_pending_outputs_v1.records
    if jobs.size() != 1 or records.size() != 1:
        return _fail_bool("refund authority fixture omitted its exact job/receipt")
    var mutations: Array[Dictionary] = []

    var wrong_pending_lot: Dictionary = refund_fixture.duplicate(true)
    (wrong_pending_lot.home_pending_outputs_v1.records[0].original_lots[0] as Dictionary)[
        "quality_score"] = 0.8750000000000001
    mutations.append({"label": "refund altered pending lot", "world": wrong_pending_lot})

    var wrong_pending_origin: Dictionary = refund_fixture.duplicate(true)
    (wrong_pending_origin.home_pending_outputs_v1.records[0].original_lots[0] as Dictionary) \
        .origin["kind"] = "forged_refund"
    mutations.append({"label": "refund altered pending origin", "world": wrong_pending_origin})

    for content_mutation in ["item", "quantity"]:
        var forged: Dictionary = refund_fixture.duplicate(true)
        var job_lot: Dictionary = forged.home_ship.crafting_summary.craft_jobs_v1.jobs[0] \
            .refunded_lots_v1[0]
        match content_mutation:
            "item":
                job_lot["item_id"] = "ferrous_shard"
            "quantity":
                job_lot["quantity"] = int(job_lot.quantity) + 1
        var record: Dictionary = forged.home_pending_outputs_v1.records[0]
        record.original_lots = (forged.home_ship.crafting_summary.craft_jobs_v1.jobs[0] \
            .refunded_lots_v1 as Array).duplicate(true)
        record.remaining_lots = (record.original_lots as Array).duplicate(true)
        mutations.append({
            "label": "refund self-consistent forged %s" % content_mutation,
            "world": forged,
        })

    for key in ["ship_id", "station_instance_id", "source_holder_id"]:
        var wrong_link: Dictionary = refund_fixture.duplicate(true)
        var record: Dictionary = wrong_link.home_pending_outputs_v1.records[0]
        record[key] = "ship-foreign" if key == "ship_id" else "p10-forged"
        mutations.append({"label": "refund wrong %s" % key, "world": wrong_link})

    for mutation in mutations:
        if not _validate_rejected_world(
                service, mutation.world as Dictionary, str(mutation.label)):
            return false
    return true


func _build_current_refund_world(base: Dictionary) -> Dictionary:
    var crafting = CraftingStateScript.new()
    var inventory = InventoryStateScript.new("player:fixture-world")
    inventory.add_item("scrap_metal", 1)
    inventory.add_item("wiring_bundle", 2)
    inventory.add_item("reactive_gel", 1)
    inventory.add_item("power_cell", 10)
    var store = PendingOutputStoreScript.new()
    if not store.configure("ship_start"):
        return {}
    var station_id: String = "station:fabricator@0,550,0"
    if not crafting.bind_station_runtime_context(
            "ship_start", station_id, "fabricator", inventory,
            null, SkillFixture.new(), store):
        return {}
    if crafting.enqueue_craft(
            "craft_power_cell", 1, null, inventory, MaterialStateScript.new(), 4,
            "ship_start", station_id) != 1:
        return {}
    var job_rows: Array = crafting.get_craft_job_scheduler().get_summary().jobs
    if job_rows.size() != 1 or inventory.add_item("scrap_metal", 20) != 20:
        return {}
    var job_id: String = str((job_rows[0] as Dictionary).job_id)
    var cancelled: Dictionary = crafting.cancel_job(job_id, "ship_start", station_id)
    if not bool(cancelled.get("ok", false)) \
            or str(cancelled.get("result", "")) != "recoverable_refund":
        return {}
    var summary: Dictionary = crafting.get_summary()
    var world: Dictionary = base.duplicate(true)
    world.home_ship["inventory_summary"] = inventory.get_summary()
    world.home_ship.crafting_summary["craft_jobs_v1"] = summary.craft_jobs_v1
    world.home_ship.crafting_summary["physical_station_summaries"] = (
        summary.physical_station_summaries)
    world.home_ship.crafting_summary["physical_station_positions_v1"] = {
        "schema": "physical-station-positions-1",
        "owners": [{
            "ship_id": "ship_start",
            "stations": [{
                "station_kind": "fabricator",
                "station_instance_id": station_id,
                "floor_slot_id": "floor@0,550,0",
                "local_position": [0.0, 0.55, 0.0],
            }],
        }],
    }
    world["home_pending_outputs_v1"] = store.get_summary()
    return world


func _validate_legacy_terminal_contracts(
        service: RefCounted, world_fixture: Dictionary, run_fixture: Dictionary) -> bool:
    var legacy_unrecorded: Dictionary = _legacy_terminal_world(
        world_fixture, run_fixture, false)
    if legacy_unrecorded.is_empty() or not _round_trip_legacy_terminal_world(
            service, legacy_unrecorded, true):
        return false
    var legacy_forfeited: Dictionary = _legacy_terminal_world(
        world_fixture, run_fixture, true)
    if legacy_forfeited.is_empty() or not _round_trip_legacy_terminal_world(
            service, legacy_forfeited, false):
        return false

    for forged_key in [
        "refunded_lots_v1", "legacy_unreserved_cancelled_v1",
        "legacy_unrecorded_cancelled_v1",
    ]:
        var forged_jobs: Dictionary = legacy_unrecorded.duplicate(true)
        var forged_job: Dictionary = forged_jobs.home_ship.crafting_summary.craft_jobs_v1.jobs[0]
        forged_job[forged_key] = [] if forged_key == "refunded_lots_v1" else false
        if not _validate_rejected_world(
                service, forged_jobs, "craft-jobs-1 forged %s" % forged_key):
            return false

    var forged_field_history: Dictionary = world_fixture.duplicate(true)
    forged_field_history.home_ship.crafting_summary.field_crafting.craft_jobs_v1[
        "schema"] = "craft-jobs-1"
    forged_field_history.home_ship.crafting_summary.field_crafting.field_pending_v1 \
        .erase("schema")
    if not _validate_rejected_world(
            service, forged_field_history, "legacy field envelope forged current history"):
        return false
    return true


func _legacy_terminal_world(
        world_fixture: Dictionary, run_fixture: Dictionary, consumed: bool) -> Dictionary:
    var world: Dictionary = world_fixture.duplicate(true)
    var source_row: Dictionary = (
        run_fixture.crafting_summary.craft_jobs_v1.jobs[0] as Dictionary).duplicate(true)
    var station_id: String = "station:workbench@0,550,0"
    var job_id: String = "ship_start/%s/job-000001" % station_id
    source_row["job_id"] = job_id
    source_row["ship_id"] = "ship_start"
    source_row["station_instance_id"] = station_id
    source_row["source_holder_id"] = "player:fixture-world"
    source_row["escrow_holder_id"] = "ship_start/%s/escrow" % station_id
    source_row["state"] = "cancelled"
    source_row["phase"] = "cancelled"
    source_row["ingredient_escrow"] = []
    source_row["output_lots"] = []
    source_row["output_receipt_id"] = ""
    source_row["receipt_emitted"] = false
    if consumed:
        source_row["consumed_lots"] = (
            run_fixture.crafting_summary.craft_jobs_v1.jobs[0].ingredient_escrow as Array) \
            .duplicate(true)
        source_row["progress"] = 3.75
        source_row["progress_seconds"] = 3.75
        source_row["input_quality_score"] = 0.5
        source_row["input_skill_level"] = 4
        source_row["station_effective_tier"] = 0
        source_row["station_powered_at_start"] = true
    else:
        source_row["consumed_lots"] = []
        source_row["progress"] = 0.0
        source_row["progress_seconds"] = 0.0
    for current_key in [
        "refunded_lots_v1", "legacy_unreserved_cancelled_v1",
        "legacy_unrecorded_cancelled_v1",
    ]:
        source_row.erase(current_key)
    var crafting: Dictionary = world.home_ship.crafting_summary
    crafting["craft_jobs_v1"] = {
        "schema": "craft-jobs-1",
        "jobs": [source_row],
        "owners": [{
            "ship_id": "ship_start",
            "station_instance_id": station_id,
            "sequence": 1,
            "job_ids": [],
        }],
    }
    crafting["physical_station_summaries"] = {
        JSON.stringify(["ship_start", station_id]): {
            "ship_id": "ship_start",
            "station_instance_id": station_id,
            "active_job_id": "",
            "station_kind": "workbench",
            "level": 0,
            "tier": 0,
            "max_queue": 8,
            "powered": true,
            "active_recipe_id": "",
            "progress_seconds": 0.0,
            "required_seconds": 0.0,
            "status": 0,
            "queue": [],
        },
    }
    crafting["physical_station_positions_v1"] = {
        "schema": "physical-station-positions-1",
        "owners": [{
            "ship_id": "ship_start",
            "stations": [{
                "station_kind": "workbench",
                "station_instance_id": station_id,
                "floor_slot_id": "floor@0,550,0",
                "local_position": [0.0, 0.55, 0.0],
            }],
        }],
    }
    return world


func _round_trip_legacy_terminal_world(
        service: RefCounted, source: Dictionary, expect_tombstone: bool) -> bool:
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    var original: String = JSON.stringify(source, "", true, true)
    if not _write_text(path, original):
        return _fail_bool("could not write legacy terminal fixture")
    var expected_job: Dictionary = {}
    for reload_index in range(3):
        var prepared: Dictionary = service.prepare_world_load("fixture-world")
        var world = _prepared_world(service, prepared)
        if not bool(prepared.get("ok", false)) or world == null:
            return _fail_bool("legacy terminal reload %d rejected: %s" % [
                reload_index + 1, str(prepared)])
        var rows: Array = world.to_dict().home_ship.crafting_summary.craft_jobs_v1.jobs
        if rows.size() != 1:
            return _fail_bool("legacy terminal reload omitted its job")
        var job: Dictionary = rows[0]
        if bool(job.get("legacy_unrecorded_cancelled_v1", false)) != expect_tombstone \
                or not (job.get("refunded_lots_v1", []) as Array).is_empty() \
                or (expect_tombstone and not (job.get("consumed_lots", []) as Array).is_empty()) \
                or (not expect_tombstone and (job.get("consumed_lots", []) as Array).is_empty()):
            return _fail_bool("legacy terminal evidence normalized incorrectly: %s" % str(job))
        if reload_index > 0 and not _json_values_equal(job, expected_job):
            return _fail_bool("legacy terminal evidence changed after normalized resave")
        expected_job = job.duplicate(true)
        var normalized: Dictionary = world.to_dict()
        service.discard_prepared_load(str(prepared.token))
        if _read_text(path) != original and reload_index == 0:
            return _fail_bool("legacy terminal preparation changed source bytes")
        original = JSON.stringify(normalized, "", true, true)
        if not _write_text(path, original):
            return _fail_bool("could not resave normalized legacy terminal fixture")
    return true


func _validate_rejected_run(service: RefCounted, slot_id: String, fixture: Dictionary) -> bool:
    var path: String = "user://saves/%s.json" % slot_id
    var original: String = JSON.stringify(fixture, "  ", true, true)
    if not _write_text(path, original):
        return _fail_bool("could not write rejected run fixture")
    var prepared: Dictionary = service.prepare_run_load(slot_id)
    if bool(prepared.get("ok", false)) or _read_text(path) != original \
            or not FileAccess.file_exists(path) \
            or FileAccess.file_exists(path.trim_suffix(".json") + ".migrated.json"):
        return _fail_bool("rejected run changed source bytes/path or wrote a sidecar")
    return true


func _validate_legacy_world(service: RefCounted, fixture: Dictionary) -> bool:
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    var original: String = JSON.stringify(fixture, "  ", true, true)
    if not _write_text(path, original):
        return _fail_bool("could not write legacy world")
    var prepared: Dictionary = service.prepare_world_load("legacy-world")
    var prepared_world = _prepared_world(service, prepared)
    if not bool(prepared.get("ok", false)) or not bool(prepared.get("migrated", false)) \
            or prepared_world == null or str(prepared_world.slice_version) != "world-6" \
            or str(prepared_world.home_ship.get("slice_version", "")) != "gate2-current-run-6" \
            or str(prepared_world.home_ship.get("recipe_knowledge_summary", {}).get("owner_id", "")) != "player:legacy-world" \
            or _read_text(path) != original:
        return _fail_bool("ordered world/home migration did not prepare atomically")
    var normalized_first: Dictionary = prepared_world.to_dict()
    var first_home: Dictionary = normalized_first.home_ship
    var first_knowledge: Dictionary = first_home.recipe_knowledge_summary
    if str(first_knowledge.get("migration_origin", "")) != "legacy_unrecorded":
        return _fail_bool("legacy knowledge evidence marker was lost")
    service.discard_prepared_load(str(prepared.token))
    if not _write_text(path, JSON.stringify(normalized_first, "", true, true)):
        return _fail_bool("could not write first normalized legacy world")
    var second: Dictionary = service.prepare_world_load("legacy-world")
    if not bool(second.get("ok", false)):
        return _fail_bool("bound legacy knowledge failed second reload: %s" % str(second))
    var second_world = _prepared_world(service, second)
    if second_world == null:
        return _fail_bool("bound legacy knowledge second candidate missing")
    var second_dict: Dictionary = second_world.to_dict()
    service.discard_prepared_load(str(second.token))
    if not _write_text(path, JSON.stringify(second_dict, "", true, true)):
        return _fail_bool("could not write second normalized legacy world")
    var third: Dictionary = service.prepare_world_load("legacy-world")
    var third_world = _prepared_world(service, third)
    if not bool(third.get("ok", false)) or third_world == null \
            or third_world.to_dict().home_ship.recipe_knowledge_summary != first_knowledge:
        return _fail_bool("bound legacy knowledge failed stable third load")
    service.discard_prepared_load(str(third.token))
    return true


func _validate_current_world(service: RefCounted, fixture: Dictionary) -> bool:
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    if not _write_text(path, JSON.stringify(fixture, "", true, true)):
        return _fail_bool("could not write current world")
    var prepared: Dictionary = service.prepare_world_load()
    if not bool(prepared.get("ok", false)) or not bool(prepared.get("migrated", false)):
        return _fail_bool("v5 world with partial pending field output did not migrate: %s" % str(prepared))
    var ws = _prepared_world(service, prepared)
    if ws == null:
        return _fail_bool("current world prepared token could not be inspected")
    if str(ws.home_access_v1.get("owner_id", "")) != "player:foreign" \
            or int(((ws.home_pending_outputs_v1.records[0] as Dictionary).remaining_lots[0] as Dictionary).quantity) != 1:
        return _fail_bool("current world changed access owner or pending quantity")
    service.discard_prepared_load(str(prepared.token))
    service.set_active_run_id("fixture-world")
    if not service.save_to_slot("p10-modern-world", ws, "manual", false, "P10 World"):
        return _fail_bool("modern manual slot did not save a coherent world")
    var modern_path: String = "user://saves/p10-modern-world.json"
    var modern_dict: Variant = JSON.parse_string(_read_text(modern_path))
    if not modern_dict is Dictionary \
            or str((modern_dict as Dictionary).get("slice_version", "")) != "world-6" \
            or not (modern_dict as Dictionary).get("home_pending_outputs_v1", null) is Dictionary:
        return _fail_bool("modern manual slot wrote a standalone run")
    var reloaded: Dictionary = service.prepare_slot_load("p10-modern-world")
    if not bool(reloaded.get("ok", false)):
        return _fail_bool("modern coherent slot did not reload")
    service.discard_prepared_load(str(reloaded.token))
    return true


func _validate_rejected_world(
        service: RefCounted, fixture: Dictionary, label: String) -> bool:
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    var original: String = JSON.stringify(fixture, "  ", true, true)
    if not _write_text(path, original):
        return _fail_bool("could not write %s fixture" % label)
    var prepared: Dictionary = service.prepare_world_load()
    if bool(prepared.get("ok", false)) or _read_text(path) != original \
            or not FileAccess.file_exists(path) \
            or FileAccess.file_exists(path.trim_suffix(".json") + ".migrated.json"):
        return _fail_bool("rejected %s changed source bytes/path or wrote a sidecar" % label)
    return true


func _load_fixture(name: String) -> Dictionary:
    var text: String = _read_text("%s/%s" % [FIXTURE_DIR, name])
    var parsed: Variant = JSON.parse_string(text)
    if not parsed is Dictionary:
        return {}
    var fixture: Dictionary = (parsed as Dictionary).duplicate(true)
    _replace_fixture_version(fixture)
    return fixture


func _prepared_world(service: RefCounted, prepared: Dictionary):
    if not bool(prepared.get("ok", false)):
        return null
    var world_dict: Dictionary = service.inspect_prepared_world_for_validation(
        str(prepared.get("token", "")), str(prepared.get("seal", "")))
    return WorldSnapshotScript.from_dict(
        world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
        Engine.get_version_info()["string"])


func _replace_fixture_version(value: Variant) -> void:
    if value is Dictionary:
        var dict: Dictionary = value
        for key in dict.keys():
            if str(key) == "godot_version" and str(dict[key]) == "fixture-current":
                dict[key] = Engine.get_version_info()["string"]
            else:
                _replace_fixture_version(dict[key])
    elif value is Array:
        for item in value as Array:
            _replace_fixture_version(item)


func _ensure_save_dir() -> bool:
    var absolute: String = ProjectSettings.globalize_path("user://saves")
    var error: int = DirAccess.make_dir_recursive_absolute(absolute)
    if error != OK and error != ERR_ALREADY_EXISTS:
        return _fail_bool("could not create isolated save directory")
    return true


func _write_text(path: String, text: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    return true


func _read_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text: String = file.get_as_text()
    file.close()
    return text


func _clear_owned_fixture_files() -> void:
    for slot_id in ["p10-legacy", "p10-current", "p10-future", "p10-bad-component", "p10-bad-field", "p10-modern-world"]:
        var path: String = "user://saves/%s.json" % slot_id
        _remove_if_exists(path)
        _remove_if_exists(path.trim_suffix(".json") + ".migrated.json")
    _remove_if_exists(SaveLoadServiceScript.WORLD_SLOT_FILE)
    _remove_if_exists(SaveLoadServiceScript.WORLD_SLOT_FILE.trim_suffix(".json") + ".migrated.json")
    _remove_if_exists("user://saves/.cloud/world.manifest.json")


func _remove_if_exists(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _begin_title_continue_validation() -> void:
    var current = live_main.get("playable_instance") if live_main != null else null
    if current == null or not current.request_save():
        _fail("could not seed successful title Continue from the final production owner")
        return
    var captured = current._build_world_snapshot()
    if captured == null:
        _fail("title Continue baseline world capture failed")
        return
    title_expected_run_id = str(current.get("_run_id"))
    title_expected_inventory = current.inventory_state.get_summary()
    title_expected_player_position = (captured.home_ship.get(
        "player_position", []) as Array).duplicate()
    title_expected_location = str(captured.current_location)
    title_expected_objective = int(captured.home_ship.get(
        "current_objective_sequence", 0))
    if title_expected_run_id.is_empty() or title_expected_player_position.size() < 3:
        _fail("title Continue baseline omitted run or position authority")
        return
    live_main.process_mode = Node.PROCESS_MODE_DISABLED
    live_main.visible = false
    title_validation = TITLE_SCENE.instantiate()
    get_root().add_child(title_validation)
    title_validation._on_title_continue()
    process_frame.connect(_on_title_validation_frame)


func _on_title_validation_frame() -> void:
    title_validation_frames += 1
    if title_validation_frames > 500:
        _fail("successful title Continue timed out")
        return
    if title_validation == null or not is_instance_valid(title_validation) \
            or title_validation.main_node == null \
            or not is_instance_valid(title_validation.main_node):
        return
    var loaded = title_validation.playable_instance
    if loaded == null or not is_instance_valid(loaded) or not loaded.playable_started \
            or str(loaded.get("_run_id")) != title_expected_run_id:
        return
    if loaded != title_validation.main_node.playable_instance:
        _fail("successful title Continue retained a stale playable pointer")
        return
    var loaded_world = loaded._build_world_snapshot()
    if loaded_world == null \
            or str(loaded_world.current_location) != title_expected_location \
            or not _json_values_equal(
                loaded_world.home_ship.get("player_position", []),
                title_expected_player_position) \
            or int(loaded.get("current_objective_sequence")) != title_expected_objective \
            or not _json_values_equal(
                loaded.inventory_state.get_summary(), title_expected_inventory):
        _fail("successful title Continue changed run/location/position/inventory authority")
        return
    print("FC P10 PASS")
    if is_instance_valid(title_validation):
        title_validation.queue_free()
    if is_instance_valid(live_main):
        live_main.queue_free()
    quit(0)


func _fail_bool(message: String) -> bool:
    _fail(message)
    return false


func _fail(message: String) -> void:
    print("FC P10 FAIL: %s" % message)
    quit(1)
