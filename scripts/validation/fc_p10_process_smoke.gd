extends SceneTree

## P10 fresh-process persistence proof.  This is deliberately separate from
## fc_p10_smoke: each mode is started by the Python runner in a new OS process.
## Markers are mode-specific; only the runner emits FC P10 PROCESS PASS.

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _mode: String = ""
var _args: Dictionary = {}
var _main: Node = null
var _frames: int = 0
var _finished: bool = false
var _producer_route: Dictionary = {}


func _initialize() -> void:
    _args = _parse_args(OS.get_cmdline_user_args())
    _mode = str(_args.get("mode", ""))
    if not _valid_args() or not _user_data_is_isolated() \
            or not _all_user_environment_roots_match():
        return
    if _mode == "probe":
        print("FC P10 USER DATA PROBE PASS resolved_user=%s os_user=%s root=%s" % [
            ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/"),
            OS.get_user_data_dir().simplify_path().trim_suffix("/"),
            str(_args.get("user_data", "")).simplify_path(),
        ])
        quit(0)
        return
    _main = MAIN_SCENE.instantiate()
    get_root().add_child(_main)
    process_frame.connect(_on_frame)


func _on_frame() -> void:
    if _finished:
        return
    _frames += 1
    var playable = _main.get("playable_instance") if _main != null else null
    if playable == null or not bool(playable.get("playable_started")):
        if _frames > 500:
            _fail("production playable did not start")
        return
    if _mode == "producer":
        _run_producer_step(playable)
        return
    _finished = true
    var ok: bool = false
    match _mode:
        "consumer1":
            ok = _run_consumer_one(playable)
        "consumer2":
            ok = _run_consumer_two(playable)
        _:
            _fail("unknown mode %s" % _mode)
            return
    if ok:
        print("FC P10 PROCESS %s PASS" % _mode.to_upper())
        _main.queue_free()
        quit(0)


func _run_producer_step(playable) -> void:
    _dismiss_boot_menu(playable)
    if _producer_route.is_empty():
        _producer_route = _prepare_away_pending_and_field_pin(playable)
        return
    # Field crafting advances through PlayableGeneratedShip's ordinary frame
    # processing. Do not invoke its private _process method from this smoke.
    if playable.field_crafting_state.is_crafting():
        if _frames > 1200:
            _fail("producer field craft did not complete through production frames")
        return
    _finished = true
    if _finish_producer(playable, _producer_route):
        print("FC P10 PROCESS PRODUCER PASS")
        _main.queue_free()
        quit(0)


func _finish_producer(playable, route: Dictionary) -> bool:
    var away = playable.get_current_host_for_validation()
    if away == null or str(away.ship_id) != str(route.get("ship_id", "")):
        return _fail_bool("producer field completion lost exact away owner")
    var field_records: Array = away.get_pending_output_store().list_records_for_station("field_crafting", true)
    if field_records.size() != 1 or away.floor_drop_descriptors.size() != 1:
        return _fail_bool("producer field pin did not complete through production frames records=%s descriptors=%s drops=%s field=%s inventory=%s occupancy=%s" % [
            str(field_records), str(away.floor_drop_descriptors), str(playable.work_yield_drops),
            str(playable.field_crafting_state.get_summary()), str(playable.inventory_state.get_lot_summary()),
            str(playable.current_occupancy.ship_id) if playable.current_occupancy != null else "<null>"])
    route["field_receipt_id"] = str((field_records[0] as Dictionary).get("receipt_id", ""))
    playable = _authoritative_playable()
    if playable == null or not _seed_distinct_away_combat(playable) \
            or not _seed_submillisecond_away_arc(playable):
        return _fail_bool("producer could not seed distinct away combat and arc authority")
    if not playable.request_save():
        return _fail_bool("producer production save failed")
    var baseline_path: String = str(_args["baseline"])
    var source_path: String = ProjectSettings.globalize_path(SaveLoadServiceScript.WORLD_SLOT_FILE)
    if not _copy_file(source_path, baseline_path):
        return _fail_bool("producer could not capture production baseline slot")
    var baseline_digest: String = _sha256_file(baseline_path)
    if baseline_digest.is_empty():
        return _fail_bool("producer baseline digest missing")
    var observation: Dictionary = _observe_durable_state(playable, route)
    if observation.is_empty():
        return false
    var expected: Dictionary = {
        "schema": "p10-process-1",
        "baseline_path": baseline_path,
        "baseline_sha256": baseline_digest,
        "observation": observation,
        "fixture_note": "materials and recipe access are explicit validation fixtures; no acquisition claim",
    }
    if not _write_json(str(_args["expected"]), expected):
        return _fail_bool("producer could not write expected observation manifest")
    return true


func _run_consumer_one(playable) -> bool:
    var expected: Dictionary = _read_json(str(_args["expected"]))
    if expected.is_empty() or str(expected.get("schema", "")) != "p10-process-1":
        return _fail_bool("consumer one expected manifest invalid")
    var baseline_path: String = str(_args["baseline"])
    if _sha256_file(baseline_path) != str(expected.get("baseline_sha256", "")):
        return _fail_bool("consumer one baseline digest mismatch")
    if not _install_external_slot(baseline_path):
        return _fail_bool("consumer one could not install baseline disk input")
    if not playable.request_load():
        return _fail_bool("consumer one production load rejected baseline")
    playable = _authoritative_playable()
    var route: Dictionary = expected.get("observation", {}).get("route", {}) as Dictionary
    var expected_observation: Dictionary = expected.get("observation", {}) as Dictionary
    var actual_observation: Dictionary = _observe_durable_state(playable, route) if playable != null else {}
    var observation_diff: Dictionary = _observation_diff(actual_observation, expected_observation)
    if playable == null or not observation_diff.is_empty():
        return _fail_bool("consumer one durable baseline observation mismatch %s" % str(observation_diff))
    if not _exercise_restored_structure_damage(playable):
        return false
    if not _collect_restored_field_drop_once(playable, expected.get("observation", {}) as Dictionary):
        return false
    var station = _station_for(playable, str(route.get("ship_id", "")), "workbench")
    if station == null or not _open_station_ordinary(playable, station) \
            or not _select_with_input(playable, "collect_pending"):
        return _fail_bool("consumer one pending output not reachable through production interaction")
    _remove_all(playable.inventory_state, "plating")
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    var records: Array = _pending_records(playable, route)
    var expected_workbench: Dictionary = expected.observation.get("workbench_receipt", {}) as Dictionary
    var expected_workbench_lots: Array = (expected_workbench.get("remaining_lots", []) as Array).duplicate(true)
    var receipt_id: String = str(expected_workbench.get("receipt_id", ""))
    var receipt_after: Dictionary = _pending_store_for_route(playable, route).get_record(receipt_id)
    var expected_collected: Dictionary = {}
    for lot in expected_workbench_lots:
        if lot is Dictionary:
            expected_collected[str((lot as Dictionary).get("lot_id", ""))] = int((lot as Dictionary).get("quantity", 0))
    var expected_tombstone: Dictionary = expected_workbench.duplicate(true)
    expected_tombstone["state"] = "collected"
    expected_tombstone["remaining_lots"] = []
    expected_tombstone["collected_quantities"] = expected_collected
    if playable.inventory_state.get_quantity("plating") != 1 or not records.is_empty() \
            or not _wire_equals(_lots_for_item(playable.inventory_state.get_lot_summary(), "plating"), expected_workbench_lots) \
            or not _wire_equals(receipt_after, expected_tombstone):
        return _fail_bool("consumer one did not collect the exact output once")
    if not playable.request_save():
        return _fail_bool("consumer one production post-collection save failed")
    var post_path: String = str(_args["post"])
    if not _copy_file(ProjectSettings.globalize_path(SaveLoadServiceScript.WORLD_SLOT_FILE), post_path):
        return _fail_bool("consumer one could not capture post-collection slot")
    var post_digest: String = _sha256_file(post_path)
    if post_digest.is_empty() or post_digest == str(expected.get("baseline_sha256", "")):
        return _fail_bool("consumer one post artifact was missing or unchanged")
    return _write_json(str(_args["post_manifest"]), {
        "schema": "p10-process-post-1", "post_path": post_path, "post_sha256": post_digest,
        "observation": _observe_post_collection_state(playable, route,
            str(expected.observation.get("workbench_receipt_id", ""))),
    })


func _run_consumer_two(playable) -> bool:
    var post: Dictionary = _read_json(str(_args["post_manifest"]))
    if post.is_empty() or str(post.get("schema", "")) != "p10-process-post-1":
        return _fail_bool("consumer two post manifest invalid")
    var post_path: String = str(_args["post"])
    if _sha256_file(post_path) != str(post.get("post_sha256", "")):
        return _fail_bool("consumer two post digest mismatch")
    if not _install_external_slot(post_path) or not playable.request_load():
        return _fail_bool("consumer two production post-collection load failed")
    playable = _authoritative_playable()
    if playable == null:
        return _fail_bool("consumer two load did not leave an authoritative playable")
    var expected: Dictionary = post.get("observation", {}) as Dictionary
    var route: Dictionary = expected.get("route", {}) as Dictionary
    var records: Array = _pending_records(playable, route)
    var receipt_id: String = str(expected.get("workbench_receipt_id", ""))
    var scheduler = playable.crafting_state.get_craft_job_scheduler()
    var job: Dictionary = scheduler.get_job(str(route.get("job_id", "")))
    var store = _pending_store_for_route(playable, route)
    var sidecar: String = ProjectSettings.globalize_path(
        SaveLoadServiceScript.WORLD_SLOT_FILE.trim_suffix(".json") + ".migrated.json")
    if not _post_observations_match(_observe_post_collection_state(playable, route, receipt_id), expected) \
            or not records.is_empty() or str(job.get("state", "")) != "collected" \
            or not (job.get("ingredient_escrow", []) as Array).is_empty() \
            or store == null or not receipt_id.is_empty() and not store.peek_remaining_lots(receipt_id).is_empty() \
            or FileAccess.file_exists(sidecar):
        return _fail_bool("consumer two found duplicate output, reservation, replay, or migrated sidecar")
    return true


func _collect_restored_field_drop_once(playable, expected: Dictionary) -> bool:
    var route: Dictionary = expected.get("route", {}) as Dictionary
    var owner = playable.get_current_host_for_validation()
    if owner == null or str(owner.ship_id) != str(route.get("ship_id", "")) \
            or playable.work_yield_drops.size() != 1 or owner.floor_drop_descriptors.size() != 1:
        return _fail_bool("consumer one restored field holder was not live")
    var expected_receipt: Dictionary = expected.get("field_receipt", {}) as Dictionary
    var receipt_id: String = str(expected_receipt.get("receipt_id", ""))
    var expected_lots: Array = (expected_receipt.get("original_lots", []) as Array).duplicate(true)
    _remove_all(playable.inventory_state, "field_bandage")
    var drop = playable.work_yield_drops[0]
    playable.player.teleport_to(drop.global_position)
    playable.recompute_occupancy()
    playable.player.request_interact()
    var lot_matches: bool = _wire_equals(
        _lots_for_item(playable.inventory_state.get_lot_summary(), "field_bandage"), expected_lots)
    var receipt_after: Dictionary = owner.get_pending_output_store().get_record(receipt_id)
    if playable.inventory_state.get_quantity("field_bandage") != 1 or not lot_matches \
            or not _wire_equals(receipt_after, expected_receipt) or not owner.floor_drop_descriptors.is_empty() \
            or playable.work_yield_drops.size() != 0:
        return _fail_bool("consumer one field holder did not transfer exact receipt lot once")
    playable.player.request_interact()
    if playable.inventory_state.get_quantity("field_bandage") != 1:
        return _fail_bool("consumer one field holder replayed on second interaction")
    return true


func _seed_distinct_home_combat(playable) -> bool:
    var manager = playable.threat_manager
    var home = playable.get_home_ship_for_validation()
    if manager == null or home == null:
        return false
    if manager.get_active_threat_count() == 0:
        manager.inject_validation_encounter(["biomatter_swarm"])
    var summary: Dictionary = manager.get_summary()
    if (summary.get("threats", []) as Array).is_empty():
        return false
    var threat: Dictionary = summary.threats[0]
    threat["health"] = maxf(1.0, float(threat.max_health) - 3.25)
    summary["awareness_indicator"] = 0.1875
    summary["combat_engaged"] = false
    summary.detection["awareness_score"] = 0.3125
    summary["last_attack_result"] = _weapon_receipt(
        "crowbar", str(threat.instance_id), 3.25)
    if not manager.apply_summary(summary):
        return false
    home.combat_summary = manager.get_summary()
    return true


func _seed_distinct_away_combat(playable) -> bool:
    var manager = playable.threat_manager
    var away = playable.get_current_host_for_validation()
    if manager == null or away == null or away == playable.get_home_ship_for_validation():
        return false
    manager.inject_validation_encounter(["hull_tendril"])
    var summary: Dictionary = manager.get_summary()
    if (summary.get("threats", []) as Array).size() != 1:
        return false
    var threat: Dictionary = summary.threats[0]
    threat["health"] = 31.25
    summary["awareness_indicator"] = 0.8375
    summary["combat_engaged"] = true
    summary.detection["awareness_score"] = 1.125
    summary.detection["detected"] = true
    summary.detection["last_reason"] = "combined"
    summary["last_attack_result"] = _weapon_receipt(
        "flare_pistol", str(threat.instance_id), 9.75)
    if not manager.apply_summary(summary):
        return false
    away.combat_summary = manager.get_summary()
    # Persist a valid but deliberately stale presentation cache. A restore may
    # rebuild the active threat runtime, but it must not silently rewrite this
    # accepted String before the first post-load capture.
    playable._last_weapon_hotbar_text = "Weapon: Flare Pistol | R02 process authority"
    return true


func _seed_submillisecond_away_arc(playable) -> bool:
    var state = playable.electrical_arc_state
    var away = playable.get_current_host_for_validation()
    if state == null or away == null or away == playable.get_home_ship_for_validation():
        return false
    var summary: Dictionary = state.get_summary()
    summary["state"] = "DISCHARGED"
    summary["phase"] = 0
    summary["time_in_state"] = 0.00045947811447
    summary["remaining_in_state"] = 1.49954052188553
    if not state.apply_summary(summary):
        return false
    var actual: Dictionary = state.get_summary()
    if float(actual.get("time_in_state", -1.0)) != 0.00045947811447 \
            or float(actual.get("remaining_in_state", -1.0)) != 1.49954052188553:
        return false
    away.arc_summary = actual.duplicate(true)
    return true


func _exercise_restored_structure_damage(playable) -> bool:
    var manager = playable.threat_manager
    if manager == null or not manager.on_structure_attack.is_valid():
        return _fail_bool("consumer one restored no production structure callback")
    var tendril = null
    for threat in manager.threats:
        if str(threat.archetype_id) == "hull_tendril" \
                and absf(float(threat.structure_damage) - 0.4) < 0.000001:
            tendril = threat
            break
    if tendril == null:
        return _fail_bool("consumer one restored no exact hull-tendril structure damage")
    var before: Dictionary = playable.module_integrity_map.get_summary()
    tendril.state = "attack"
    tendril.attack_cooldown = 0.0
    var position := Vector3(
        float(tendril.world_position[0]), float(tendril.world_position[1]),
        float(tendril.world_position[2]))
    manager.set_player_signals(2.0, 2.0, 2.0, false, str(tendril.room_id))
    manager.set_engaged_los(str(tendril.instance_id), true)
    manager.tick_threats(
        0.1, playable.vitals_state, playable.status_effects_state, {}, position)
    playable._refresh_weapon_hotbar()
    var after: Dictionary = playable.module_integrity_map.get_summary()
    if after == before or (after.get("deltas", []) as Array).is_empty():
        return _fail_bool("consumer one restored tendril produced no structural damage delta")
    return true


func _lots_for_item(summary: Dictionary, item_id: String) -> Array:
    var out: Array = []
    for value in summary.get("lots", []) as Array:
        if value is Dictionary and str((value as Dictionary).get("item_id", "")) == item_id:
            out.append((value as Dictionary).duplicate(true))
    return out


func _prepare_away_pending_and_field_pin(playable) -> Dictionary:
    playable.force_repair_all_for_validation()
    playable.board_piloted_ship_for_validation()
    playable.recompute_occupancy()
    if not _seed_distinct_home_combat(playable):
        _fail("producer could not seed distinct home combat authority")
        return {}
    var world = playable.get_synaptic_sea_world()
    var markers: Array = world.markers_in_range(playable.scanner_state.range_radius) if world != null else []
    if markers.is_empty():
        _fail("producer no reachable away marker")
        return {}
    var marker_id: String = str(markers[0].marker_id)
    if not bool(playable.travel_to_marker_id(marker_id).get("success", false)) \
            or not playable.open_active_dock_barrier_for_validation() \
            or not playable.board_host_for_validation():
        _fail("producer away-owner production route failed")
        return {}
    playable.recompute_occupancy()
    var away = playable.get_current_host_for_validation()
    if away == null or away == playable.get_home_ship_for_validation():
        _fail("producer did not occupy away owner")
        return {}
    var ship_id: String = str(away.ship_id)
    var station = _station_for(playable, ship_id, "workbench")
    if station == null or not _open_station_ordinary(playable, station) \
            or not _select_with_input(playable, "weld_plating"):
        _fail("producer away workbench admission was not ordinarily reachable")
        return {}
    # Explicit validation fixture: this proves persistence, not acquisition.
    _ensure_quantity(playable.inventory_state, "scrap_metal", 12)
    _ensure_quantity(playable.inventory_state, "adhesive_paste", 6)
    playable.recipe_picker_panel.refresh()
    if not _select_with_input(playable, "weld_plating"):
        _fail("producer fixture materials did not admit workbench recipe")
        return {}
    playable.dispatch_recipe_picker_input_for_validation("ui_accept")
    var projection: Dictionary = playable.get_station_crafting_projection(
        "workbench", ship_id, str(station.station_instance_id), int(station.binding_generation))
    var running: Dictionary = _first_job(projection, "running")
    if running.is_empty():
        _fail("producer workbench job did not start")
        return {}
    var route: Dictionary = {"marker_id": marker_id, "ship_id": ship_id,
        "station_id": str(station.station_instance_id), "binding_generation": int(station.binding_generation),
        "job_id": str(running.job_id)}
    if not playable.travel_home():
        _fail("producer could not detach away workbench job")
        return {}
    playable.world_time += 60.0
    playable.board_piloted_ship_for_validation()
    if not bool(playable.travel_to_marker_id(marker_id).get("success", false)) \
            or not playable.open_active_dock_barrier_for_validation() \
            or not playable.board_host_for_validation():
        _fail("producer could not revisit away workbench")
        return {}
    playable.recompute_occupancy()
    var completed: Array = _pending_records(playable, route)
    if completed.size() != 1:
        _fail("producer away workbench did not publish exactly one pending receipt")
        return {}
    # Travel names the docked host, but portable work follows the actor's
    # physical occupancy. Re-enter the exact away workbench through the normal
    # interaction path before beginning field work; this is not an owner-ID
    # assignment or a completion shortcut.
    var revisited_station = _station_for(playable, ship_id, "workbench")
    if revisited_station == null or not _open_station_ordinary(playable, revisited_station):
        _fail("producer could not ordinarily re-enter revisited away workbench")
        return {}
    playable.recipe_picker_panel.close()
    playable.recompute_occupancy()
    if playable.current_occupancy == null \
            or str(playable.current_occupancy.ship_id) != ship_id:
        _fail("producer actor was not physically occupied aboard revisited owner")
        return {}
    _remove_all(playable.inventory_state, "field_bandage")
    _ensure_quantity(playable.inventory_state, "synth_fiber", 2)
    _ensure_quantity(playable.inventory_state, "medical_gauze", 1)
    playable.inventory_state.add_item("field_bandage", 99)
    playable.vitals_state.stamina = playable.vitals_state.max_stamina
    if not playable.begin_field_craft_recipe("field_bandage"):
        _fail("producer field craft did not start")
        return {}
    var field_summary: Dictionary = playable.field_crafting_state.get_summary()
    var field_inner: Dictionary = field_summary.get("field_crafting", {}) as Dictionary
    var field_pending: Dictionary = field_inner.get("field_pending_v1", {}) as Dictionary
    if str(field_pending.get("ship_id", "")) != ship_id:
        _fail("producer field craft did not bind exact occupied owner")
        return {}
    # Completion is observed in _run_producer_step after ordinary scene frames.
    return route


func _observe_durable_state(playable, route: Dictionary) -> Dictionary:
    if playable == null or route.is_empty():
        return {}
    var owner = playable.get_current_host_for_validation()
    if owner == null or str(owner.ship_id) != str(route.get("ship_id", "")):
        _fail("durable observation was not aboard the exact persisted owner")
        return {}
    var store = _pending_store_for_route(playable, route)
    var job: Dictionary = playable.crafting_state.get_craft_job_scheduler().get_job(str(route.get("job_id", "")))
    var records: Array = _pending_records(playable, route)
    var field_records: Array = store.list_records_for_station("field_crafting", true)
    if job.is_empty() or records.size() != 1 or field_records.size() != 1:
        _fail("durable observation omitted exact job or receipts")
        return {}
    var placement = playable.get_component_placement_state_for_validation()
    var home = playable.get_home_ship_for_validation()
    return {
        "route": route.duplicate(true),
        "recipe_knowledge": playable.recipe_knowledge_state.get_summary(),
        "inventory_lots": playable.inventory_state.get_lot_summary(),
        "crafting": playable.crafting_state.get_summary(),
        "workbench_job": job.duplicate(true),
        "workbench_receipt": (records[0] as Dictionary).duplicate(true),
        "workbench_receipt_id": str((records[0] as Dictionary).get("receipt_id", "")),
        "field_receipt": (field_records[0] as Dictionary).duplicate(true),
        "field_history": playable.field_crafting_state.get_receipt_history_v1(),
        "component_origins": placement.get_summary() if placement != null else {},
        "home_combat": home.combat_summary.duplicate(true) if home != null else {},
        "away_combat": owner.combat_summary.duplicate(true),
        "away_arc": playable.electrical_arc_state.get_summary().duplicate(true) \
            if playable.electrical_arc_state != null else {},
        "active_combat": playable.threat_manager.get_summary(),
        "combat_hotbar_text": str(playable._last_weapon_hotbar_text),
    }


func _observations_match(actual: Dictionary, expected: Dictionary) -> bool:
    return _observation_diff(actual, expected).is_empty()


func _observation_diff(actual: Dictionary, expected: Dictionary) -> Dictionary:
    if actual.is_empty() or expected.is_empty():
        return {"key": "root", "expected_hash": _value_hash(expected), "actual_hash": _value_hash(actual)}
    # Exact disk-restored owner, lot, knowledge, job/escrow/progress, receipt and
    # component-origin projections. All values are read from the newly restored
    # production playable; no producer model is passed to a consumer. Both sides
    # take the same full-precision JSON wire roundtrip first: producer's expected
    # manifest has already crossed JSON, while a live typed model has not.
    for key in ["route", "recipe_knowledge", "inventory_lots", "crafting", "workbench_job",
            "workbench_receipt", "field_receipt", "field_history", "component_origins",
            "home_combat", "away_combat", "away_arc", "active_combat", "combat_hotbar_text"]:
        var expected_wire: Variant = _wire_value(expected.get(key, null))
        var actual_wire: Variant = _wire_value(actual.get(key, null))
        if actual_wire != expected_wire:
            var diff: Dictionary = {"key": key, "expected_hash": _value_hash(expected_wire),
                "actual_hash": _value_hash(actual_wire)}
            if key == "recipe_knowledge":
                diff["expected_value"] = JSON.stringify(expected_wire, "", true, true)
                diff["actual_value"] = JSON.stringify(actual_wire, "", true, true)
            return diff
    return {}


func _value_hash(value: Variant) -> String:
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        return ""
    context.update(JSON.stringify(value, "", true, true).to_utf8_buffer())
    return context.finish().hex_encode()


func _wire_value(value: Variant) -> Variant:
    return JSON.parse_string(JSON.stringify(value, "", true, true))


func _wire_equals(actual: Variant, expected: Variant) -> bool:
    return _wire_value(actual) == _wire_value(expected)


func _observe_post_collection_state(playable, route: Dictionary, workbench_receipt_id: String) -> Dictionary:
    var owner = playable.get_current_host_for_validation()
    var store = _pending_store_for_route(playable, route)
    if owner == null or store == null:
        return {}
    var scheduler = playable.crafting_state.get_craft_job_scheduler()
    var job: Dictionary = scheduler.get_job(str(route.get("job_id", "")))
    var home = playable.get_home_ship_for_validation()
    return {
        "route": route.duplicate(true),
        "workbench_receipt_id": workbench_receipt_id,
        "inventory_lots": playable.inventory_state.get_lot_summary(),
        "workbench_job": job.duplicate(true),
        "workbench_record": store.get_record(workbench_receipt_id),
        "workbench_records": store.list_records_for_station(str(route.get("station_id", "")), true),
        "field_records": store.list_records_for_station("field_crafting", true),
        "field_history": playable.field_crafting_state.get_receipt_history_v1(),
        "recipe_knowledge": playable.recipe_knowledge_state.get_summary(),
        "crafting": playable.crafting_state.get_summary(),
        "floor_drop_descriptors": owner.floor_drop_descriptors.duplicate(true),
        "component_origins": playable.get_component_placement_state_for_validation().get_summary(),
        "module_integrity": playable.module_integrity_map.get_summary(),
        "home_combat": home.combat_summary.duplicate(true) if home != null else {},
        "away_combat": owner.combat_summary.duplicate(true),
        "active_combat": playable.threat_manager.get_summary(),
        "combat_hotbar_text": str(playable._last_weapon_hotbar_text),
    }


func _post_observations_match(actual: Dictionary, expected: Dictionary) -> bool:
    if actual.is_empty() or expected.is_empty():
        return false
    for key in ["route", "workbench_receipt_id", "inventory_lots", "workbench_job",
            "workbench_record", "workbench_records", "field_records", "field_history",
            "recipe_knowledge", "crafting", "floor_drop_descriptors", "component_origins",
            "module_integrity", "home_combat", "away_combat", "active_combat",
            "combat_hotbar_text"]:
        if not _wire_equals(actual.get(key, null), expected.get(key, null)):
            return false
    return true


func _pending_store_for_route(playable, route: Dictionary):
    var owner = playable.get_current_host_for_validation()
    if owner == null or str(owner.ship_id) != str(route.get("ship_id", "")):
        return null
    return owner.get_pending_output_store() if owner != null else null


func _pending_records(playable, route: Dictionary) -> Array:
    var store = _pending_store_for_route(playable, route)
    return store.list_records_for_station(str(route.get("station_id", ""))) if store != null else []


func _station_for(playable, ship_id: String, station_kind: String):
    for station in playable.crafting_stations:
        if is_instance_valid(station) and station.is_inside_tree() \
                and str(station.ship_id) == ship_id and str(station.station_kind) == station_kind:
            return station
    return null


func _open_station_ordinary(playable, station) -> bool:
    if station == null or not is_instance_valid(station) or not station.is_inside_tree():
        return false
    if playable.recipe_picker_panel.is_open():
        playable.recipe_picker_panel.close()
    playable.player.teleport_to(station.global_position)
    playable.recompute_occupancy()
    playable.player.request_interact()
    return playable.recipe_picker_panel.is_open() \
        and playable.recipe_picker_panel.get_ship_id() == str(station.ship_id) \
        and playable.recipe_picker_panel.get_station_instance_id() == str(station.station_instance_id)


func _select_with_input(playable, expected_id: String) -> bool:
    var panel = playable.recipe_picker_panel
    for _index in range(panel.get_entry_count() + 1):
        if panel.get_selected_id() == expected_id:
            return true
        playable.dispatch_recipe_picker_input_for_validation("ui_down")
    return false


func _first_job(projection: Dictionary, wanted_state: String) -> Dictionary:
    for value in projection.get("jobs", []) as Array:
        if value is Dictionary and str((value as Dictionary).get("state", "")) == wanted_state:
            return (value as Dictionary).duplicate(true)
    return {}


func _ensure_quantity(inventory, item_id: String, minimum: int) -> void:
    var missing: int = maxi(0, minimum - int(inventory.get_quantity(item_id)))
    if missing > 0:
        inventory.add_item(item_id, missing)


func _remove_all(inventory, item_id: String) -> void:
    var quantity: int = int(inventory.get_quantity(item_id))
    if quantity > 0:
        inventory.remove_item(item_id, quantity)


func _dismiss_boot_menu(playable) -> void:
    if playable.menu_coordinator != null:
        playable.menu_coordinator.dismiss_boot_menu()
        playable.menu_coordinator.menu_state.close_all()


func _authoritative_playable():
    return _main.get("playable_instance") if _main != null else null


func _install_external_slot(source: String) -> bool:
    if FileAccess.file_exists(SaveLoadServiceScript.WORLD_SLOT_FILE):
        return false
    return _copy_file(source, ProjectSettings.globalize_path(SaveLoadServiceScript.WORLD_SLOT_FILE))


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


func _copy_file(source: String, destination: String) -> bool:
    if source.is_empty() or destination.is_empty() or not FileAccess.file_exists(source):
        return false
    DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
    var error: Error = DirAccess.copy_absolute(source, destination)
    return error == OK and FileAccess.file_exists(destination)


func _sha256_file(path: String) -> String:
    if path.is_empty() or not FileAccess.file_exists(path):
        return ""
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        return ""
    context.update(bytes)
    return context.finish().hex_encode()


func _write_json(path: String, value: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(value, "\t", false, true))
    file.close()
    return true


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}


func _parse_args(args: PackedStringArray) -> Dictionary:
    var parsed: Dictionary = {}
    for arg in args:
        if not arg.begins_with("--") or not arg.contains("="):
            continue
        var split: PackedStringArray = arg.substr(2).split("=", false, 1)
        if split.size() == 2:
            parsed[split[0]] = split[1]
    return parsed


func _valid_args() -> bool:
    var required: Array[String] = ["mode", "user_data"]
    if _mode == "producer":
        required.append_array(["baseline", "expected"])
    elif _mode == "consumer1":
        required.append_array(["baseline", "expected", "post", "post_manifest"])
    elif _mode == "consumer2":
        required.append_array(["post", "post_manifest"])
    for key in required:
        if str(_args.get(key, "")).is_empty():
            _fail("missing required --%s argument" % key)
            return false
    if not _mode in ["probe", "producer", "consumer1", "consumer2"]:
        _fail("invalid mode")
        return false
    return true


func _user_data_is_isolated() -> bool:
    var expected: String = str(_args.get("user_data", "")).simplify_path()
    var os_user: String = OS.get_user_data_dir().simplify_path().trim_suffix("/")
    var resolved_user: String = ProjectSettings.globalize_path(
        "user://").simplify_path().trim_suffix("/")
    for actual in [os_user, resolved_user]:
        if expected.is_empty() or actual != expected and not actual.begins_with(expected + "/"):
            _fail("Godot user-data path escaped the unique runner directory actual=%s expected=%s" % [
                actual, expected])
            return false
    if os_user != resolved_user:
        _fail("OS/user:// resolution disagreed os=%s user=%s" % [os_user, resolved_user])
        return false
    return true


func _all_user_environment_roots_match() -> bool:
    var expected: String = str(_args.get("user_data", "")).simplify_path()
    for variable in ["APPDATA", "LOCALAPPDATA", "GODOT_USER_PATH", "XDG_DATA_HOME"]:
        var actual: String = OS.get_environment(variable).simplify_path()
        if expected.is_empty() or actual != expected:
            _fail("%s escaped the unique runner directory actual=%s expected=%s" % [
                variable, actual, expected])
            return false
    return true


func _fail_bool(message: String) -> bool:
    _fail(message)
    return false


func _fail(message: String) -> void:
    push_error("FC P10 PROCESS FAIL: %s" % message)
    _finished = true
    quit(1)
