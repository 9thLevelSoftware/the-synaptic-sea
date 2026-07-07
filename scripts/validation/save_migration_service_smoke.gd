extends SceneTree

## REQ-SL-007/009 migration + permadeath model smoke.
##
## Pure-model smoke (no scene tree) that proves:
##   - SaveMigrationService walks v1 -> v2 -> v3 -> v4 deterministically
##     (v4 defaults per ADR-0046: play_time_seconds/current_location/world_seed).
##   - A v1 save without player_progression_summary migrates forward
##     and gains a default player_progression_summary.
##   - A new-than-current save is rejected (forward-only).
##   - PermadeathResolver writes a death record; load_from_slot then
##     returns null while the death file exists; has_died_in is true.
##   - Migration persists the migrated form to <slot>.migrated.json.
##
## Pass marker: SAVE MIGRATION SERVICE PASS

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")

func _make_v1_dict() -> Dictionary:
	# v1 has 6 model summaries (no player_progression_summary, no audio
	# summary, no slot identity).
	var d: Dictionary = {
		"layout_path": "res://data/procgen/smoke/seed_000017/layout.json",
		"kit_path": "res://data/kits/ship_structural_v0.json",
		"gameplay_slice_path": "res://data/procgen/smoke/seed_000017/gameplay_slice.json",
		"player_position": [1.0, 0.0, 2.0],
		"current_objective_sequence": 4,
		"ship_systems_summary": {"systems": {"power": {"health": 0.5}}},
		"route_control_summary": {"active_blockers": 0, "extraction_unlocked": false},
		"oxygen_summary": {"oxygen": 75.0},
		"inventory_summary": {"tools": []},
		"fire_summary": {"state": "CLEARED"},
		"electrical_arc_summary": {"state": "DISCHARGED"},
		"objective_progress_summary": {"current": 4},
		"slice_version": "gate2-current-run-1",
		"godot_version": Engine.get_version_info()["string"],
		"saved_at": "2026-06-20T00:00:00",
	}
	return d

func _make_newer_dict() -> Dictionary:
	# A "future" save the current service must reject (forward-only).
	var d: Dictionary = _make_v1_dict()
	d["slice_version"] = "gate2-current-run-99"
	d["some_future_field"] = {"magic": 1}
	return d

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	_cleanup_task11_slots(service)
	service.delete_current_run()
	var migrator = SaveMigrationServiceScript.new()

	# 1. Pure migration walk v1 -> v2 -> v3.
	var v1_dict := _make_v1_dict()
	var result_v12: Dictionary = migrator.migrate_run(v1_dict)
	if not bool(result_v12.get("migrated", false)):
		_fail("v1 dict did not migrate (migrated=false)")
		return
	if str((result_v12["dict"] as Dictionary).get("slice_version", "")) != SaveMigrationServiceScript.TARGET_VERSION:
		_fail("v1 dict did not migrate to TARGET_VERSION")
		return
	if not (result_v12["dict"] as Dictionary).has("player_progression_summary"):
		_fail("v1 dict did not gain player_progression_summary after v2 step")
		return
	if not (result_v12["dict"] as Dictionary).has("slot_id"):
		_fail("v1 dict did not gain slot_id after v3 step")
		return
	if not (result_v12["dict"] as Dictionary).has("slot_kind"):
		_fail("v1 dict did not gain slot_kind after v3 step")
		return
	if not (result_v12["dict"] as Dictionary).has("is_autosave"):
		_fail("v1 dict did not gain is_autosave after v3 step")
		return
	if not (result_v12["dict"] as Dictionary).has("is_quicksave"):
		_fail("v1 dict did not gain is_quicksave after v3 step")
		return
	# Session 4 (Tranche 3): the chain now ends at gate2-current-run-4
	# (ADR-0046). Assert the _migrate_v3_to_v4 defaults land — this smoke
	# previously stopped at the v3 fields, leaving a broken v4 step
	# invisible.
	var v4_dict: Dictionary = result_v12["dict"] as Dictionary
	if not v4_dict.has("play_time_seconds") or float(v4_dict.get("play_time_seconds", -1.0)) != 0.0:
		_fail("v1 dict did not gain play_time_seconds=0.0 after v4 step; have=%s" % str(v4_dict.get("play_time_seconds")))
		return
	if not v4_dict.has("current_location") or str(v4_dict.get("current_location", "x")) != "":
		_fail("v1 dict did not gain current_location='' after v4 step; have=%s" % str(v4_dict.get("current_location")))
		return
	if not v4_dict.has("world_seed") or int(v4_dict.get("world_seed", -1)) != 0:
		_fail("v1 dict did not gain world_seed=0 after v4 step; have=%s" % str(v4_dict.get("world_seed")))
		return

	# 2. Forward-only rejection of a new-version save.
	var newer_dict := _make_newer_dict()
	var result_newer: Dictionary = migrator.migrate_run(newer_dict)
	if result_newer.get("dict", null) != null:
		_fail("newer-version dict was accepted (forward-only violation)")
		return

	# 3. End-to-end: write a v1 snapshot to disk via the service so it
	# gets the v1 slice_version stamped; load_from_slot then runs the
	# migration; assert the loaded snapshot is at TARGET_VERSION and
	# has the migrated form on disk.
	var legacy := RunSnapshotScript.new()
	# Manually stamp v1 slice_version so the migration engages.
	legacy.slice_version = "gate2-current-run-1"
	legacy.godot_version = Engine.get_version_info()["string"]
	legacy.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	legacy.current_objective_sequence = 4
	legacy.player_position = [1.0, 0.0, 2.0]
	legacy.ship_systems_summary = {"systems": {"power": {"health": 0.5}}}
	legacy.route_control_summary = {"active_blockers": 0}
	legacy.oxygen_summary = {"oxygen": 75.0}
	legacy.inventory_summary = {"tools": []}
	legacy.fire_summary = {"state": "CLEARED"}
	legacy.electrical_arc_summary = {"state": "DISCHARGED"}
	legacy.objective_progress_summary = {"current": 4}
	legacy.saved_at = "2026-06-20T00:00:00"
	if not service.save_to_slot("slot_legacy", legacy, SaveSlotStateScript.SLOT_KIND_MANUAL, false, "Legacy"):
		_fail("save_to_slot legacy failed")
		return
	var migrated_loaded = service.load_from_slot("slot_legacy")
	if migrated_loaded == null:
		_fail("load_from_slot legacy returned null (migration should have rescued it)")
		return
	if migrated_loaded.slice_version != SaveMigrationServiceScript.TARGET_VERSION:
		_fail("migrated_loaded slice_version=%s expected %s" % [migrated_loaded.slice_version, SaveMigrationServiceScript.TARGET_VERSION])
		return
	if not migrated_loaded.player_progression_summary.has("class_id"):
		_fail("migrated snapshot missing player_progression_summary.class_id default; have=%s" % str(migrated_loaded.player_progression_summary))
		return
	var migrated_path: String = "user://saves/slot_legacy.migrated.json"
	if not FileAccess.file_exists(migrated_path):
		_fail("migrated form not persisted to disk: %s" % migrated_path)
		return

	# 4. Permadeath resolver writes a death record; load_from_slot
	# refuses while the death record exists.
	var resolver = PermadeathResolverScript.new()
	if resolver.has_died_in("slot_legacy"):
		_fail("has_died_in returned true before record_death")
		return
	var record: Dictionary = resolver.record_death("slot_legacy", "oxygen_depleted", "Lost to the void at sequence 4.", 1234.5, 4)
	if record.is_empty():
		_fail("record_death returned empty")
		return
	if not resolver.has_died_in("slot_legacy"):
		_fail("has_died_in returned false after record_death")
		return
	var blocked = service.load_from_slot("slot_legacy")
	if blocked != null:
		_fail("load_from_slot should return null for death-frozen slot, got non-null")
		return
	# Reading the epitaph still works.
	var epitaph: Dictionary = resolver.load_epitaph("slot_legacy")
	if str(epitaph.get("cause", "")) != "oxygen_depleted":
		_fail("epitaph.cause mismatch: %s" % str(epitaph.get("cause", "")))
		return

	# 5. Clearing the death record unblocks future saves.
	if not resolver.clear_death("slot_legacy"):
		_fail("clear_death failed")
		return

	# 6. Determinism: re-run migration on the same v1 dict and confirm
	# the output is identical.
	var r1: Dictionary = migrator.migrate_run(_make_v1_dict())
	var r2: Dictionary = migrator.migrate_run(_make_v1_dict())
	if JSON.stringify(r1["dict"]) != JSON.stringify(r2["dict"]):
		_fail("migration is not deterministic")
		return

	# Cleanup
	_cleanup_task11_slots(service)
	service.delete_current_run()
	resolver.clear_death("slot_legacy")

	print("SAVE MIGRATION SERVICE PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SAVE MIGRATION SERVICE FAIL reason=%s" % reason)
	quit(1)

func _cleanup_task11_slots(service: SaveLoadService) -> void:
	for slot_id in [
		"slot_legacy",
		"slot_01",
		"slot_02",
		"slot_03",
		"quicksave",
		"world",
		"autosave_active",
		"autosave_a",
		"autosave_b",
		"autosave_c",
	]:
		service.delete_slot(slot_id)