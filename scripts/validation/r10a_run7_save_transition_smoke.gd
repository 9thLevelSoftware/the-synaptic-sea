extends SceneTree

## R10-A run-7 schema and historical run-6 migration boundary.
## Marker: R10-A RUN7 SAVE TRANSITION PASS current=true legacy=true standalone=true fixture=true

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

const RUN_5: String = "gate2-current-run-5"
const RUN_6: String = "gate2-current-run-6"
const RUN_7: String = "gate2-current-run-7"
const RUN_8_FIXTURE: String = "res://tests/fixtures/feature_completion/p10_run_v8_future.json"
const PRESERVED_RUN_7_FIXTURE: String = "res://tests/fixtures/feature_completion/p10_run_v7_future.json"
const PRESERVED_RUN_7_SHA256: String = "af9987a7508ae5bfe69da9ea06382628b821b545c3426712aeb1e6ec1180dac2"


func _initialize() -> void:
	if SaveMigrationServiceScript.TARGET_VERSION != RUN_7 \
			or SaveLoadServiceScript.CURRENT_SLICE_VERSION != RUN_7:
		_fail("run-7 is not the current run boundary")
		return
	if not _validate_current_contract():
		return
	if not _validate_historical_migration():
		return
	if not _validate_standalone_and_pre_v6_ordering():
		return
	if not _validate_future_fixtures():
		return
	print("R10-A RUN7 SAVE TRANSITION PASS current=true legacy=true standalone=true fixture=true")
	quit(0)


func _validate_current_contract() -> bool:
	var current: Dictionary = _valid_run_dictionary(RUN_7)
	if current.has("player_position") or current.has("hallucination_summary"):
		return _fail_bool("current encoder emitted forbidden pose or hallucination key")
	if RunSnapshotScript.SUMMARY_FIELDS.has("hallucination_summary") \
			or RunSnapshotScript.SUMMARY_FIELDS.size() != 32:
		return _fail_bool("run-7 summary membership is not the exact 32 fields")
	var decoded = RunSnapshotScript.from_dict(current, RUN_7, "fixture-current")
	if decoded == null or decoded.get_summary_count() != 31:
		return _fail_bool("valid current run did not decode with summary count 31")
	for forbidden_key in ["player_position", "hallucination_summary"]:
		for forbidden_value in [{}, [], [1.0, 2.0, 3.0], "legacy"]:
			var mutant: Dictionary = current.duplicate(true)
			mutant[forbidden_key] = forbidden_value
			if RunSnapshotScript.from_dict(mutant, RUN_7, "fixture-current") != null:
				return _fail_bool("current run accepted forbidden %s presence" % forbidden_key)
	return true


func _validate_historical_migration() -> bool:
	var migrator = SaveMigrationServiceScript.new()
	var legacy: Dictionary = _valid_run_dictionary(RUN_6)
	legacy["player_position"] = [1.25, -2.5, 3.75]
	legacy["hallucination_summary"] = _valid_hallucination_summary()
	var source_before: Dictionary = legacy.duplicate(true)
	var migrated: Dictionary = migrator.migrate_run(legacy)
	var migrated_dict: Variant = migrated.get("dict", null)
	if not migrated_dict is Dictionary \
			or str((migrated_dict as Dictionary).get("slice_version", "")) != RUN_7 \
			or (migrated_dict as Dictionary).has("player_position") \
			or (migrated_dict as Dictionary).has("hallucination_summary"):
		return _fail_bool("valid run-6 did not migrate to strict run-7: %s" % str(migrated))
	if legacy != source_before:
		return _fail_bool("run-6 migration mutated its source")
	if RunSnapshotScript.from_dict(migrated_dict, RUN_7, "fixture-current") == null:
		return _fail_bool("migrated run-7 failed current decoding")
	var legacy_base_event: Dictionary = {
		"id": 2, "kind": "ambient", "position": [0.0, 1.0, 2.0], "ttl": 2.0,
	}
	var legacy_base_summary: Dictionary = _valid_hallucination_summary()
	legacy_base_summary.erase("spawn_timers")
	legacy_base_summary.erase("pool_loaded")
	legacy_base_summary["active_events"] = [legacy_base_event]
	var legacy_timer_summary: Dictionary = legacy_base_summary.duplicate(true)
	legacy_timer_summary["spawn_timers"] = {"ambient": 1.25}
	var forced_summary: Dictionary = _valid_hallucination_summary()
	forced_summary.active_events[0]["forced"] = true
	for historical_variant in [
		legacy_base_summary, legacy_timer_summary, _valid_hallucination_summary(),
		forced_summary,
	]:
		var variant_source: Dictionary = source_before.duplicate(true)
		variant_source["hallucination_summary"] = historical_variant
		var variant_result: Dictionary = migrator.migrate_run(variant_source)
		if not variant_result.get("dict", null) is Dictionary \
				or (variant_result.dict as Dictionary).has("hallucination_summary"):
			return _fail_bool("known historical hallucination variant did not migrate")
	var serialized_path: String = "user://historical-run6-with-hallucination.json"
	var serialized_file := FileAccess.open(serialized_path, FileAccess.WRITE)
	if serialized_file == null:
		return _fail_bool("could not write serialized historical run-6 fixture")
	serialized_file.store_string(JSON.stringify(source_before, "\t", false, true))
	serialized_file.close()
	var serialized_variant: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(serialized_path))
	if not serialized_variant is Dictionary:
		return _fail_bool("could not parse serialized historical run-6 fixture")
	var serialized_summary: Dictionary = (serialized_variant as Dictionary).get(
		"hallucination_summary", {}) as Dictionary
	var serialized_event: Dictionary = (serialized_summary.get(
		"active_events", []) as Array)[0] as Dictionary
	if typeof(serialized_summary.get("seed", null)) != TYPE_FLOAT \
			or typeof(serialized_summary.get("step", null)) != TYPE_FLOAT \
			or typeof(serialized_summary.get("current_tier", null)) != TYPE_FLOAT \
			or typeof(serialized_event.get("id", null)) != TYPE_FLOAT:
		return _fail_bool("serialized historical integer fields did not exercise JSON floats")
	var serialized_result: Dictionary = migrator.migrate_run(serialized_variant)
	if not serialized_result.get("dict", null) is Dictionary \
			or (serialized_result.dict as Dictionary).has("hallucination_summary"):
		return _fail_bool("serialized historical hallucination did not migrate")

	for legacy_hallucination in [null, {}]:
		var optional: Dictionary = source_before.duplicate(true)
		if legacy_hallucination == null:
			optional.erase("hallucination_summary")
		else:
			optional["hallucination_summary"] = legacy_hallucination
		var optional_result: Dictionary = migrator.migrate_run(optional)
		if not optional_result.get("dict", null) is Dictionary \
				or (optional_result.dict as Dictionary).has("hallucination_summary"):
			return _fail_bool("historical absent/empty hallucination did not migrate")

	var malformed_cases: Array[Dictionary] = [
		{"value": "episode", "reason": "legacy_hallucination_not_dictionary"},
		{"value": {"seed": 7}, "reason": "legacy_hallucination_invalid_shape"},
		{"value": _valid_hallucination_summary().merged({"spawn_timers": {"hud": "soon"}}, true), "reason": "legacy_hallucination_invalid_timer"},
		{"value": _valid_hallucination_summary().merged({"active_events": [{"id": 1, "kind": "hud", "position": [0.0, INF, 0.0], "ttl": 1.0, "entry_id": "", "caption": "", "audio_event": ""}]}, true), "reason": "legacy_hallucination_invalid_event"},
		{"value": _valid_hallucination_summary().merged({"seed": true}, true), "reason": "legacy_hallucination_invalid_shape"},
		{"value": _valid_hallucination_summary().merged({"current_tier": "3"}, true), "reason": "legacy_hallucination_invalid_shape"},
		{"value": _valid_hallucination_summary().merged({"step": 1.5}, true), "reason": "legacy_hallucination_invalid_shape"},
		{"value": _valid_hallucination_summary().merged({"active_events": [{"id": "3", "kind": "hud", "position": [0.0, 1.0, 0.0], "ttl": 1.0, "entry_id": "", "caption": "", "audio_event": ""}]}, true), "reason": "legacy_hallucination_invalid_event"},
		{"value": _valid_hallucination_summary().merged({"active_events": [{"id": 2.5, "kind": "hud", "position": [0.0, 1.0, 0.0], "ttl": 1.0, "entry_id": "", "caption": "", "audio_event": ""}]}, true), "reason": "legacy_hallucination_invalid_event"},
	]
	for malformed in malformed_cases:
		var mutant: Dictionary = source_before.duplicate(true)
		mutant["hallucination_summary"] = malformed.value
		var rejected: Dictionary = migrator.migrate_run(mutant)
		if rejected.get("dict", null) != null \
				or str(rejected.get("reason", "")) != str(malformed.reason):
			return _fail_bool("malformed legacy hallucination lost exact reason: %s" % str(rejected))

	var bad_pose: Dictionary = source_before.duplicate(true)
	bad_pose["player_position"] = [0.0, NAN, 0.0]
	var bad_pose_result: Dictionary = migrator.migrate_run(bad_pose)
	if bad_pose_result.get("dict", null) != null \
			or str(bad_pose_result.get("reason", "")) != "legacy_run6_invalid_player_position":
		return _fail_bool("malformed legacy pose lost exact reason: %s" % str(bad_pose_result))
	return true


func _validate_standalone_and_pre_v6_ordering() -> bool:
	var service = SaveLoadServiceScript.new()
	service.set_active_run_id("r10a-run7-transition")
	var saves_dir: String = "user://saves"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(saves_dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves_dir))
	for version in [RUN_6, RUN_7]:
		var slot_id: String = "r10a-standalone-%s" % version.trim_prefix("gate2-current-")
		var path: String = "user://saves/%s.json" % slot_id
		var standalone: Dictionary = _valid_run_dictionary(version)
		if version == RUN_6:
			standalone["player_position"] = [4.0, 5.0, 6.0]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _fail_bool("could not write standalone fixture")
		file.store_string(JSON.stringify(standalone, "\t", false, true))
		file.close()
		var denied: Dictionary = service.prepare_slot_load(slot_id, "r10a-run7-transition")
		if bool(denied.get("ok", false)) \
				or str(denied.get("reason", "")) != "unclosed_owner_graph":
			return _fail_bool("standalone %s did not deny unclosed graph: %s" % [version, str(denied)])

	var run5: Dictionary = _valid_run_dictionary(RUN_5)
	run5["player_position"] = [7.0, 8.0, 9.0]
	run5["hallucination_summary"] = _valid_hallucination_summary()
	run5.inventory_summary.erase("threat_summary")
	run5.inventory_summary.erase("combat_hotbar_text")
	var intermediate: Dictionary = SaveMigrationServiceScript.new().migrate_run_to_closed_run6(run5)
	if not intermediate.get("dict", null) is Dictionary:
		return _fail_bool("pre-v6 run did not reach literal run-6 intermediate")
	var intermediate_run: Dictionary = intermediate.dict as Dictionary
	if str(intermediate_run.get("slice_version", "")) != RUN_6 \
			or intermediate_run.get("player_position", null) != [7.0, 8.0, 9.0] \
			or not intermediate_run.has("hallucination_summary"):
		return _fail_bool("run-6 intermediate erased pose/episode before world closure")
	var closed_world: Dictionary = service._closed_world_dict_from_run(
		intermediate_run, "r10a-run7-transition")
	if str(closed_world.get("slice_version", "")) != "world-6" \
			or str((closed_world.home_ship as Dictionary).get("slice_version", "")) != RUN_6 \
			or closed_world.get("player_position_in_ship", null) != [7.0, 8.0, 9.0]:
		return _fail_bool("pre-v6 adapter did not close literal world-6 before pose erasure")
	return true


func _validate_future_fixtures() -> bool:
	if FileAccess.get_sha256(PRESERVED_RUN_7_FIXTURE) != PRESERVED_RUN_7_SHA256:
		return _fail_bool("preserved run-7 fixture bytes changed")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUN_8_FIXTURE))
	if not parsed is Dictionary or str((parsed as Dictionary).get("slice_version", "")) != "gate2-current-run-8":
		return _fail_bool("run-8 future fixture is missing or malformed")
	var rejected: Dictionary = SaveMigrationServiceScript.new().migrate_run(parsed)
	if rejected.get("dict", null) != null:
		return _fail_bool("run-8 future fixture was accepted")
	return true


func _valid_run_dictionary(version: String) -> Dictionary:
	var snapshot = RunSnapshotScript.new()
	snapshot.slice_version = version
	snapshot.godot_version = "fixture-current"
	snapshot.recipe_knowledge_summary["owner_id"] = "player:r10a-run7-transition"
	var threat_manager = ThreatManagerScript.new()
	snapshot.inventory_summary = {
		"tools": [],
		"combat_hotbar_text": "",
		"threat_summary": threat_manager.get_summary(),
	}
	threat_manager.free()
	return snapshot.to_dict()


func _valid_hallucination_summary() -> Dictionary:
	return {
		"seed": 17,
		"step": 24,
		"health_drain_per_second": 0.5,
		"stamina_recovery_mult": 0.5,
		"active_events": [{
			"id": 3,
			"kind": "hud",
			"position": [1.0, 0.0, 2.0],
			"ttl": 1.5,
			"entry_id": "hud_false_oxygen",
			"caption": "OXYGEN CRITICAL",
			"audio_event": "sfx.sanity.hud_glitch",
		}],
		"spawn_timers": {"ambient": 2.5, "hud": 1.0, "phantom": 0.5, "whisper": 3.0},
		"current_tier": 3,
		"pool_loaded": true,
	}


func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	push_error("R10-A RUN7 SAVE TRANSITION FAIL reason=%s" % reason)
	quit(1)
