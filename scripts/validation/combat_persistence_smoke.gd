extends SceneTree

## R02: versioned combat persistence, deterministic initialization, and atomic
## rejection. Marker: COMBAT PERSISTENCE PASS

const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")
const ThreatInitialStateBuilderScript := preload("res://scripts/systems/threat_initial_state_builder.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")

const DEFINITIONS_PATH: String = "res://data/combat/threat_archetypes.json"
const RUN_FIXTURE_PATH: String = "res://tests/fixtures/feature_completion/p10_run_v5_transactional.json"
const WORLD_FIXTURE_PATH: String = "res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"


class VitalsFixture extends RefCounted:
    var health: float = 100.0


func _init() -> void:
    var definitions: Dictionary = _read_json(DEFINITIONS_PATH)
    if definitions.is_empty():
        _fail("canonical threat definitions did not load")
        return
    var layout: Dictionary = {
        "rooms": [{"id": "room_hull"}],
        "encounters": [{
            "id": "hull_contact", "room_id": "room_hull", "cell": [2, 3],
            "local_position": [1.25, 0.5, -2.0],
            "encounter_kind": "hull_tendril", "count": 1,
        }],
    }
    var anchor := Vector3(8.0, 2.0, -5.0)
    var initial: Dictionary = ThreatInitialStateBuilderScript.build_initial_v2(
        layout, layout.encounters, anchor, definitions)
    if not bool(initial.get("ok", false)):
        _fail("initializer rejected canonical inputs: %s" % str(initial))
        return
    var current: Dictionary = initial.summary
    var row: Dictionary = current.threats[0]
    if absf(float(row.structure_damage) - 0.4) > 0.000001 \
            or row.world_position != [9.25, 2.5, -7.0]:
        _fail("initializer lost structure damage or relocated anchor")
        return

    var factory = ThreatManagerScript.new()
    get_root().add_child(factory)
    factory.threat_archetypes = definitions.duplicate(true)
    factory.configure_for_layout(layout, layout.encounters, anchor)
    if factory.get_summary() != current:
        factory.free()
        _fail("factory and pure initializer summaries differ")
        return
    factory.free()

    if not _validate_codec_matrix(current):
        return
    if not _validate_atomic_manager_and_callback(current):
        return
    if not _validate_legacy_owner_traversal(current):
        return
    if not _validate_historical_world_pairings(current):
        return
    if not _validate_current_outer_boundaries(current):
        return
    if not _validate_home_bootstrap_profiles():
        return
    if not _validate_active_away_bootstrap():
        return
    if not _validate_prepare_rollback(current):
        return

    print("COMBAT PERSISTENCE PASS schema=threat-manager-2 hull=0.4 callback=true owners=home+away")
    quit(0)


func _validate_codec_matrix(current: Dictionary) -> bool:
    var encoded: String = JSON.stringify(current, "", true, true)
    var round_one: Variant = JSON.parse_string(encoded)
    var validated_one: Dictionary = ThreatSaveContractScript.validate_current(round_one)
    var canonical_encoded: String = JSON.stringify(validated_one.get("summary", {}), "", true, true)
    var round_two: Variant = JSON.parse_string(canonical_encoded)
    var validated_two: Dictionary = ThreatSaveContractScript.validate_current(round_two)
    if not bool(validated_one.get("ok", false)) or not bool(validated_two.get("ok", false)) \
            or JSON.stringify(validated_two.get("summary", {}), "", true, true) != canonical_encoded:
        return _fail_bool("current nonzero combat did not round-trip twice exactly first=%s second=%s equal=%s" % [
            str(validated_one.get("reason", "")), str(validated_two.get("reason", "")),
            str(JSON.stringify(validated_two.get("summary", {}), "", true, true) == canonical_encoded)])

    var legacy: Dictionary = current.duplicate(true)
    legacy.erase("schema")
    for threat_v in legacy.threats:
        (threat_v as Dictionary).erase("structure_damage")
    var source_before: String = JSON.stringify(legacy, "", true, true)
    var migrated: Dictionary = ThreatSaveContractScript.migrate_legacy(legacy)
    if not bool(migrated.get("ok", false)) \
            or absf(float(migrated.summary.threats[0].structure_damage) - 0.4) > 0.000001 \
            or JSON.stringify(legacy, "", true, true) != source_before:
        return _fail_bool("frozen legacy hull-tendril migration failed or mutated source")
    if bool(ThreatSaveContractScript.migrate_legacy(migrated.summary).get("ok", false)):
        return _fail_bool("current manager was accepted through the legacy codec")

    var incoming_current: Dictionary = current.duplicate(true)
    incoming_current["last_attack_result"] = _incoming_receipt(
        "hull_contact_0", 5.5)
    var incoming_validated: Dictionary = ThreatSaveContractScript.validate_current(
        incoming_current)
    if not bool(incoming_validated.get("ok", false)) \
            or incoming_validated.summary.last_attack_result \
                != incoming_current.last_attack_result:
        return _fail_bool("production incoming-damage receipt was not preserved exactly")

    var cases: Array[Dictionary] = []
    var missing: Dictionary = current.duplicate(true)
    missing.threats[0].erase("structure_damage")
    cases.append({"label": "missing", "value": missing})
    var negative: Dictionary = current.duplicate(true)
    negative.threats[0]["structure_damage"] = -0.01
    cases.append({"label": "negative", "value": negative})
    var boolean_value: Dictionary = current.duplicate(true)
    boolean_value.threats[0]["structure_damage"] = true
    cases.append({"label": "bool", "value": boolean_value})
    var string_value: Dictionary = current.duplicate(true)
    string_value.threats[0]["structure_damage"] = "0.4"
    cases.append({"label": "string", "value": string_value})
    var nonfinite: Dictionary = current.duplicate(true)
    nonfinite.threats[0]["structure_damage"] = NAN
    cases.append({"label": "nonfinite", "value": nonfinite})
    var wrong_schema: Dictionary = current.duplicate(true)
    wrong_schema["schema"] = "threat-manager-3"
    cases.append({"label": "unknown schema", "value": wrong_schema})
    var duplicate_id: Dictionary = current.duplicate(true)
    duplicate_id.threats.append(duplicate_id.threats[0].duplicate(true))
    cases.append({"label": "duplicate id", "value": duplicate_id})
    var wrong_weapon_type: Dictionary = current.duplicate(true)
    wrong_weapon_type["last_attack_result"] = _weapon_receipt(
        "flare_pistol", "hull_contact_0", 7.125)
    wrong_weapon_type.last_attack_result["weapon_id"] = 17
    cases.append({"label": "wrong attack weapon type", "value": wrong_weapon_type})
    var unknown_attack_field: Dictionary = current.duplicate(true)
    unknown_attack_field["last_attack_result"] = _weapon_receipt(
        "flare_pistol", "hull_contact_0", 7.125)
    unknown_attack_field.last_attack_result["damage"] = 7.125
    cases.append({"label": "unknown attack receipt field", "value": unknown_attack_field})
    for invalid_ammo in [true, NAN, 1.5]:
        var wrong_ammo: Dictionary = current.duplicate(true)
        wrong_ammo["last_attack_result"] = _weapon_receipt(
            "flare_pistol", "hull_contact_0", 7.125)
        wrong_ammo.last_attack_result["ammo_remaining"] = invalid_ammo
        cases.append({
            "label": "invalid integral ammunition %s" % str(invalid_ammo),
            "value": wrong_ammo,
        })
    for case_v in cases:
        if bool(ThreatSaveContractScript.validate_current(case_v.value).get("ok", false)):
            return _fail_bool("current codec accepted %s structure" % str(case_v.label))

    var mixed_legacy: Dictionary = legacy.duplicate(true)
    mixed_legacy.threats[0]["structure_damage"] = 0.4
    if bool(ThreatSaveContractScript.migrate_legacy(mixed_legacy).get("ok", false)):
        return _fail_bool("legacy codec accepted v2-only structure_damage")
    var unknown_legacy: Dictionary = legacy.duplicate(true)
    unknown_legacy.threats[0]["archetype_id"] = "hull_tendril_custom"
    if bool(ThreatSaveContractScript.migrate_legacy(unknown_legacy).get("ok", false)):
        return _fail_bool("legacy codec inferred an unknown archetype")

    var initialized_empty: Dictionary = current.duplicate(true)
    initialized_empty["encounter_markers"] = []
    initialized_empty["threats"] = []
    var empty_manager = ThreatManagerScript.new()
    get_root().add_child(empty_manager)
    if not empty_manager.apply_summary(initialized_empty) \
            or empty_manager.get_active_threat_count() != 0 \
            or empty_manager.get_summary() != initialized_empty:
        empty_manager.free()
        return _fail_bool("canonical initialized-empty manager respawned threats")
    empty_manager.free()
    return true


func _validate_atomic_manager_and_callback(current: Dictionary) -> bool:
    var manager = ThreatManagerScript.new()
    get_root().add_child(manager)
    if not manager.apply_summary(current):
        manager.free()
        return _fail_bool("manager rejected valid current summary")
    manager.last_attack_result = _weapon_receipt(
        "flare_pistol", "hull_contact_0", 7.125)
    manager._last_attack_weapon_id = "flare_pistol"
    manager.set_engaged_los("hull_contact_0", false)
    var authoritative_before: String = JSON.stringify(manager.get_summary(), "", true, true)
    var children_before: int = manager.get_child_count()
    var invalid: Dictionary = manager.get_summary()
    invalid.threats[0]["structure_damage"] = -1.0
    if manager.apply_summary(invalid) \
            or JSON.stringify(manager.get_summary(), "", true, true) != authoritative_before \
            or manager.get_child_count() != children_before \
            or manager._last_attack_weapon_id != "flare_pistol" \
            or manager.engaged_los != {"hull_contact_0": false}:
        manager.free()
        return _fail_bool("invalid manager application mutated live authority or derived nodes")

    var persisted: Dictionary = JSON.parse_string(authoritative_before)
    var restored = ThreatManagerScript.new()
    get_root().add_child(restored)
    restored.set_engaged_los("stale_los", false)
    if not restored.apply_summary(persisted):
        manager.free()
        restored.free()
        return _fail_bool("post-save manager restore failed")
    if not restored.engaged_los.is_empty():
        manager.free()
        restored.free()
        return _fail_bool("successful manager restore retained stale engaged LOS")
    var callback_amounts: Array[float] = []
    restored.on_structure_attack = func(_threat, amount: float) -> void:
        callback_amounts.append(amount)
    var restored_threat = restored.threats[0]
    restored_threat.state = "attack"
    restored_threat.attack_cooldown = 0.0
    restored.set_player_signals(2.0, 2.0, 2.0, false, "room_hull")
    restored.tick_threats(0.1, VitalsFixture.new(), null, {}, Vector3(9.25, 2.5, -7.0))
    if callback_amounts.size() != 1 or absf(callback_amounts[0] - 0.4) > 0.000001:
        manager.free()
        restored.free()
        return _fail_bool("restored hull tendril emitted no exact structural callback")
    manager.free()
    restored.free()
    return true


func _validate_legacy_owner_traversal(current: Dictionary) -> bool:
    var source: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    if source.is_empty():
        return _fail_bool("world v5 fixture did not load")
    source["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship["godot_version"] = Engine.get_version_info()["string"]
    var home_legacy: Dictionary = _legacy_copy(current)
    var away_legacy: Dictionary = _legacy_copy(current)
    away_legacy.threats[0]["instance_id"] = "inactive_away_hull"
    away_legacy.threats[0]["health"] = 7.25
    source.home_ship.inventory_summary["threat_summary"] = home_legacy
    source.visited_ships["marker-away"]["combat"] = away_legacy
    var source_before: String = JSON.stringify(source, "", true, true)
    var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_world(source)
    if not migrated.get("dict", null) is Dictionary:
        return _fail_bool("mixed owner legacy combat did not migrate")
    var result: Dictionary = migrated.dict
    if absf(float(result.home_ship.inventory_summary.threat_summary.threats[0].structure_damage) - 0.4) > 0.000001 \
            or str(result.visited_ships["marker-away"].combat.threats[0].instance_id) != "inactive_away_hull" \
            or absf(float(result.visited_ships["marker-away"].combat.threats[0].health) - 7.25) > 0.000001 \
            or JSON.stringify(source, "", true, true) != source_before:
        return _fail_bool("home/inactive-away migration crossed owners or mutated source")
    var bad: Dictionary = source.duplicate(true)
    bad.visited_ships["marker-away"].combat.threats[0]["archetype_id"] = "unknown_owner"
    var bad_before: String = JSON.stringify(bad, "", true, true)
    var bad_result: Dictionary = SaveMigrationServiceScript.new().migrate_world(bad)
    if bad_result.get("dict", null) != null \
            or str(bad_result.get("reason", "")) \
                != "legacy_combat_unknown_archetype:unknown_owner" \
            or JSON.stringify(bad, "", true, true) != bad_before:
        return _fail_bool("mixed valid-home/invalid-away migration lost reason or atomicity: %s" % str(
            bad_result))
    return true


func _validate_historical_world_pairings(current: Dictionary) -> bool:
    var migrator = SaveMigrationServiceScript.new()
    var allowed: Dictionary = {
        "world-1": ["gate2-current-run-1"],
        "world-2": ["gate2-current-run-1"],
        "world-3": ["gate2-current-run-1"],
        "world-4": [
            "gate2-current-run-1", "gate2-current-run-3", "gate2-current-run-4",
        ],
        "world-5": ["gate2-current-run-5"],
        "world-6": ["gate2-current-run-6"],
    }
    var all_runs: Array[String] = [
        "gate2-current-run-1", "gate2-current-run-2", "gate2-current-run-3",
        "gate2-current-run-4", "gate2-current-run-5", "gate2-current-run-6",
    ]
    for world_version_v in allowed:
        var world_version: String = str(world_version_v)
        for run_version in all_runs:
            var pair: Dictionary = migrator._validate_world_home_pair({
                "home_ship": {"slice_version": run_version},
            }, world_version)
            if bool(pair.get("ok", false)) != (allowed[world_version] as Array).has(run_version):
                return _fail_bool("historical pair matrix drifted for %s/%s: %s" % [
                    world_version, run_version, str(pair)])
    for malformed_pair in [
        {"home_ship": {}},
        {"home_ship": {"slice_version": true}},
    ]:
        var malformed: Dictionary = migrator._validate_world_home_pair(
            malformed_pair, "world-5")
        if bool(malformed.get("ok", false)) \
                or not str(malformed.get("reason", "")).begins_with(
                    "world_home_version_mismatch:world-5:"):
            return _fail_bool("malformed embedded version lost structured reason: %s" % str(malformed))

    var world_v5: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    for impossible_run in ["gate2-current-run-4", "gate2-current-run-6"]:
        var mutant: Dictionary = world_v5.duplicate(true)
        mutant.home_ship["slice_version"] = impossible_run
        var before: String = JSON.stringify(mutant, "", true, true)
        var rejected: Dictionary = migrator.migrate_world(mutant)
        var expected_reason: String = \
            "world_home_version_mismatch:world-5:expected=gate2-current-run-5:actual=%s" \
            % impossible_run
        if rejected.get("dict", null) != null \
                or str(rejected.get("reason", "")) != expected_reason \
                or JSON.stringify(mutant, "", true, true) != before:
            return _fail_bool("world-v5 impossible home pair was not exact/read-only: %s" % str(
                rejected))

    var run_v5: Dictionary = _read_json(RUN_FIXTURE_PATH)
    run_v5.inventory_summary["threat_summary"] = _legacy_copy(current)
    run_v5.inventory_summary.threat_summary.threats[0]["archetype_id"] = "unknown_home"
    var run_before: String = JSON.stringify(run_v5, "", true, true)
    var run_rejected: Dictionary = migrator.migrate_run(run_v5)
    if run_rejected.get("dict", null) != null \
            or str(run_rejected.get("reason", "")) \
                != "legacy_combat_unknown_archetype:unknown_home" \
            or JSON.stringify(run_v5, "", true, true) != run_before:
        return _fail_bool("run combat migration lost codec reason or mutated source: %s" % str(
            run_rejected))
    return true


func _validate_current_outer_boundaries(current: Dictionary) -> bool:
    var v5: Dictionary = _read_json(RUN_FIXTURE_PATH)
    v5["godot_version"] = Engine.get_version_info()["string"]
    var migration: Dictionary = SaveMigrationServiceScript.new().migrate_run(v5)
    if not migration.get("dict", null) is Dictionary:
        return _fail_bool("run v5 fixture did not migrate")
    var run_v6: Dictionary = migration.dict
    run_v6.inventory_summary["threat_summary"] = current.duplicate(true)
    if RunSnapshotScript.from_dict(
            run_v6, "gate2-current-run-6", Engine.get_version_info()["string"]) == null:
        return _fail_bool("current run-v6 with complete combat was rejected")
    for field in ["crafting_summary", "recipe_knowledge_summary", "component_placement_summary"]:
        var missing_old: Dictionary = run_v6.duplicate(true)
        missing_old.erase(field)
        if RunSnapshotScript.from_dict(
                missing_old, "gate2-current-run-6", Engine.get_version_info()["string"]) != null:
            return _fail_bool("run-v6 accepted missing legacy-required %s" % field)
    var missing_combat: Dictionary = run_v6.duplicate(true)
    missing_combat.inventory_summary.erase("threat_summary")
    if RunSnapshotScript.from_dict(
            missing_combat, "gate2-current-run-6", Engine.get_version_info()["string"]) != null:
        return _fail_bool("run-v6 accepted missing home combat")
    var empty_combat: Dictionary = run_v6.duplicate(true)
    empty_combat.inventory_summary["threat_summary"] = {}
    if RunSnapshotScript.from_dict(
            empty_combat, "gate2-current-run-6", Engine.get_version_info()["string"]) != null:
        return _fail_bool("run-v6 accepted present empty combat")
    var downgraded_jobs: Dictionary = run_v6.duplicate(true)
    downgraded_jobs.crafting_summary.craft_jobs_v1["schema"] = "craft-jobs-1"
    if RunSnapshotScript.from_dict(
            downgraded_jobs, "gate2-current-run-6", Engine.get_version_info()["string"]) != null:
        return _fail_bool("run-v6 accepted downgraded crafting")
    var future_run: Dictionary = {"slice_version": "gate2-current-run-7"}
    if SaveMigrationServiceScript.new().migrate_run(future_run).get("dict", null) != null:
        return _fail_bool("future run-v7 was accepted")
    var world_v6: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    world_v6["slice_version"] = "world-6"
    world_v6.home_ship["slice_version"] = "gate2-current-run-5"
    if SaveMigrationServiceScript.new().migrate_world(world_v6).get("dict", null) != null:
        return _fail_bool("world-v6 accepted embedded home-v5")
    world_v6.home_ship["slice_version"] = "gate2-current-run-7"
    if SaveMigrationServiceScript.new().migrate_world(world_v6).get("dict", null) != null:
        return _fail_bool("world-v6 accepted embedded home-v7")
    var future_world: Dictionary = SaveMigrationServiceScript.new().migrate_world(
        {"slice_version": "world-7"})
    if not bool(future_world.get("newer_than_current", false)) \
            or bool(future_world.get("migrated", false)):
        return _fail_bool("future world-v7 was accepted")
    return true


func _validate_prepare_rollback(current: Dictionary) -> bool:
    var source: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    source["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship.inventory_summary["threat_summary"] = _legacy_copy(current)
    source.visited_ships["marker-away"]["combat"] = _legacy_copy(current)
    source.visited_ships["marker-away"].combat.threats[0]["archetype_id"] = "unknown_owner"
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return _fail_bool("could not write rollback fixture")
    var source_bytes: String = JSON.stringify(source, "", true, true)
    file.store_string(source_bytes)
    file.close()
    var index_before: String = FileAccess.get_file_as_string(SaveLoadServiceScript.INDEX_PATH) \
        if FileAccess.file_exists(SaveLoadServiceScript.INDEX_PATH) else "<absent>"
    var live = ThreatManagerScript.new()
    get_root().add_child(live)
    live.apply_summary(current)
    var live_before: String = JSON.stringify(live.get_summary(), "", true, true)
    var rejected: Dictionary = SaveLoadServiceScript.new().prepare_world_load("rollback-run")
    var index_after: String = FileAccess.get_file_as_string(SaveLoadServiceScript.INDEX_PATH) \
        if FileAccess.file_exists(SaveLoadServiceScript.INDEX_PATH) else "<absent>"
    if bool(rejected.get("ok", false)) \
            or FileAccess.get_file_as_string(path) != source_bytes \
            or index_after != index_before \
            or JSON.stringify(live.get_summary(), "", true, true) != live_before:
        live.free()
        return _fail_bool("rejected mixed owner preparation mutated source/index/live state")
    live.free()
    return true


func _validate_home_bootstrap_profiles() -> bool:
    var service = SaveLoadServiceScript.new()
    var source: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    source["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship["layout_path"] = "res://data/procgen/golden/coherent_ship_002/layout.json"
    source.home_ship["kit_path"] = "res://data/kits/ship_structural_v0.json"
    source.home_ship["gameplay_slice_path"] = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    if not _write_world_source(path, source):
        return _fail_bool("could not write supported home-profile fixture")
    var supported: Dictionary = service.prepare_world_load("fixture-world")
    if not bool(supported.get("ok", false)):
        return _fail_bool("supported coherent002 home profile failed bootstrap: %s" % str(
            supported.get("reason", "invalid")))
    service.discard_prepared_load(str(supported.get("token", "")))

    var forged: Dictionary = source.duplicate(true)
    # Coherent003 is an existing valid document pair, but it is not a production
    # starting Playable scene profile and must not be selected by editable paths.
    forged.home_ship["layout_path"] = "res://data/procgen/golden/coherent_ship_003/layout.json"
    forged.home_ship["gameplay_slice_path"] = "res://data/procgen/golden/coherent_ship_003/gameplay_slice.json"
    var forged_bytes: String = JSON.stringify(forged, "", true, true)
    if not _write_world_source(path, forged):
        return _fail_bool("could not write forged home-profile fixture")
    var rejected: Dictionary = service.prepare_world_load("fixture-world")
    if bool(rejected.get("ok", false)) \
            or str(rejected.get("reason", "")) != "combat_bootstrap_home_profile_unknown" \
            or FileAccess.get_file_as_string(path) != forged_bytes:
        return _fail_bool("existing forged home path was accepted or source changed: %s" % str(rejected))
    return true


func _validate_active_away_bootstrap() -> bool:
    var service = SaveLoadServiceScript.new()
    var valid_blueprint: Dictionary = {
        "size": 0.0,
        "condition": 1.0,
        "seed_value": 17.0,
        "room_count_range": {"min": 2.0, "max": 4.0},
        "generation_context_v1": {
            "biome": "abyssal_synaptic_sea", "difficulty": "standard",
        },
    }
    if not service._valid_bootstrap_blueprint(valid_blueprint):
        return _fail_bool("finite integral JSON blueprint was rejected")
    for rejected_v in [true, NAN, 17.5]:
        var rejected_blueprint: Dictionary = valid_blueprint.duplicate(true)
        rejected_blueprint["seed_value"] = rejected_v
        if service._valid_bootstrap_blueprint(rejected_blueprint):
            return _fail_bool("bootstrap blueprint accepted invalid seed %s" % str(rejected_v))

    var source: Dictionary = _read_json(WORLD_FIXTURE_PATH)
    source["godot_version"] = Engine.get_version_info()["string"]
    source.home_ship["godot_version"] = Engine.get_version_info()["string"]
    source["current_location"] = "marker-away"
    source.visited_ships["marker-away"]["blueprint"] = valid_blueprint
    # Production _attach_derelict_active places marker-away at the canonical
    # host anchor, docks the lifeboat to it, and _current_dock_edges persists
    # that relationship with host == current_location.
    source["dock_edges"] = [{
        "host": "marker-away", "mobile": "lifeboat",
        "port_type": "airlock", "slot_index": -1,
    }]
    source["piloted_ship_id"] = "lifeboat"
    source["aboard_ship_id"] = "lifeboat"
    var path: String = SaveLoadServiceScript.WORLD_SLOT_FILE
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var manifest_path: String = "%s/world.manifest.json" % SaveLoadServiceScript.CLOUD_DIR
    if FileAccess.file_exists(manifest_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return _fail_bool("could not write active-away bootstrap fixture")
    file.store_string(JSON.stringify(source, "", true, true))
    file.close()
    var prepared: Dictionary = service.prepare_world_load("fixture-world")
    if not bool(prepared.get("ok", false)):
        return _fail_bool("active-away legacy bootstrap failed: %s" % str(prepared.get("reason", "invalid")))
    var resolved: Dictionary = service.resolve_prepared_load(
        str(prepared.get("token", "")), str(prepared.get("seal", "")))
    service.discard_prepared_load(str(prepared.get("token", "")))
    if not bool(resolved.get("ok", false)):
        return _fail_bool("active-away bootstrapped candidate did not resolve")
    var candidate = resolved.candidate
    var active: Dictionary = candidate.world_snapshot.visited_ships.get("marker-away", {})
    var combat: Dictionary = active.get("combat", {})
    if str(combat.get("schema", "")) != ThreatSaveContractScript.SCHEMA \
            or not bool(ThreatSaveContractScript.validate_current(combat).get("ok", false)):
        return _fail_bool("active-away bootstrap did not produce canonical combat")
    var documents: Dictionary = service._generate_bootstrap_documents(active)
    var definitions: Dictionary = _read_json(DEFINITIONS_PATH)
    var expected: Dictionary = ThreatInitialStateBuilderScript.build_initial_v2(
        documents.get("layout", {}),
        service._encounter_markers(documents.get("layout", {})),
        Vector3(100.0, 0.0, 0.0),
        definitions)
    if not bool(expected.get("ok", false)) or combat != expected.get("summary", {}):
        return _fail_bool("active-away host-edge bootstrap drifted from production activation anchor")

    var missing_witness: Dictionary = source.duplicate(true)
    missing_witness["dock_edges"] = []
    if not _write_world_source(path, missing_witness):
        return _fail_bool("could not write missing host-witness fixture")
    var missing_result: Dictionary = service.prepare_world_load("fixture-world")
    if bool(missing_result.get("ok", false)) \
            or str(missing_result.get("reason", "")) \
                != "combat_bootstrap_active_anchor_unreconstructable":
        return _fail_bool("away bootstrap inferred stationarity without host witness: %s" % str(
            missing_result))

    var relocated: Dictionary = source.duplicate(true)
    relocated["dock_edges"] = [{
        "host": "", "mobile": "ship-away",
        "port_type": "airlock", "slot_index": -1,
    }]
    relocated["piloted_ship_id"] = "ship-away"
    if not _write_world_source(path, relocated):
        return _fail_bool("could not write relocated active-owner fixture")
    var relocated_result: Dictionary = service.prepare_world_load("fixture-world")
    if bool(relocated_result.get("ok", false)) \
            or str(relocated_result.get("reason", "")) \
                != "combat_bootstrap_active_anchor_unreconstructable":
        return _fail_bool("relocated/mobile active owner received invented anchor: %s" % str(
            relocated_result))
    return true


func _write_world_source(path: String, source: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(source, "", true, true))
    file.close()
    return true


func _legacy_copy(current: Dictionary) -> Dictionary:
    var legacy: Dictionary = current.duplicate(true)
    legacy.erase("schema")
    for threat_v in legacy.threats:
        (threat_v as Dictionary).erase("structure_damage")
    return legacy


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


func _incoming_receipt(source_id: String, damage: float) -> Dictionary:
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
        "source_id": source_id,
        "status_effect_id": "",
        "noise": 0.25,
    }


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _fail_bool(reason: String) -> bool:
    _fail(reason)
    return false


func _fail(reason: String) -> void:
    push_error("COMBAT PERSISTENCE FAIL reason=%s" % reason)
    quit(1)
