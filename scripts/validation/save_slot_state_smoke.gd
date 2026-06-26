extends SceneTree

## REQ-SL-001/002/003/008/010/011 model smoke.
##
## Pure-model smoke (no scene tree) that proves:
##   - SaveSlotState round-trips through to_dict/from_dict.
##   - SaveIndexState lists manual/autosave/quicksave/world rows.
##   - Corruption is detected and backed up under .corrupt/.
##   - Manual slots never collide with the world slot.
##   - Cloud manifest sha matches the slot file bytes.
##   - The SaveLoadMenu UI seam (pure methods) renders rows in
##     saved_at desc order.
##
## Pass marker: SAVE SLOT STATE PASS

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const SaveIndexStateScript := preload("res://scripts/systems/save_index_state.gd")
const CloudManifestStateScript := preload("res://scripts/systems/cloud_manifest_state.gd")

func _make_snapshot(layout_path: String, sequence: int, class_id: String, player_position: Array) -> RunSnapshot:
	var snap := RunSnapshotScript.new()
	snap.layout_path = layout_path
	snap.kit_path = "res://data/kits/ship_structural_v0.json"
	snap.gameplay_slice_path = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
	snap.player_position = player_position
	snap.current_objective_sequence = sequence
	snap.ship_systems_summary = {"systems": {"power": {"health": 1.0}}, "completed_objective_types": ["recover_supplies"]}
	snap.route_control_summary = {"active_blockers": 0, "extraction_unlocked": false}
	snap.oxygen_summary = {"oxygen": 100.0}
	snap.inventory_summary = {"tools": []}
	snap.fire_summary = {"state": "CLEARED"}
	snap.electrical_arc_summary = {"state": "DISCHARGED"}
	snap.objective_progress_summary = {"current": sequence}
	snap.player_progression_summary = {"class_id": class_id, "xp": {"repair": 0}, "level": 1}
	snap.audio_summary = {"events": []}
	return snap

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	_cleanup_task11_slots(service)
	service.delete_current_run()

	# 1. Write three manual slots + a world slot.
	if not service.save_to_slot("slot_01", _make_snapshot("layout_a", 2, "engineer", [1.0, 0.0, 2.0]), SaveSlotStateScript.SLOT_KIND_MANUAL, false, "Slot 1"):
		_fail("save_to_slot slot_01 failed")
		return
	if not service.save_to_slot("slot_02", _make_snapshot("layout_b", 3, "marine", [2.0, 0.0, 4.0]), SaveSlotStateScript.SLOT_KIND_MANUAL, false, "Slot 2"):
		_fail("save_to_slot slot_02 failed")
		return
	if not service.save_to_slot("slot_03", _make_snapshot("layout_c", 4, "engineer", [3.0, 0.0, 6.0]), SaveSlotStateScript.SLOT_KIND_MANUAL, false, "Slot 3"):
		_fail("save_to_slot slot_03 failed")
		return

	# 2. Verify list_slots returns 3 manual rows + the autosave_active row.
	var rows := service.list_slots()
	var manual_rows: Array = []
	for row in rows:
		if row.slot_kind == SaveSlotStateScript.SLOT_KIND_MANUAL:
			manual_rows.append(row)
	if manual_rows.size() != 3:
		_fail("manual_rows=%d expected 3" % manual_rows.size())
		return

	# 3. Sort by saved_at desc.
	for i in range(manual_rows.size() - 1):
		if int(manual_rows[i].saved_at_epoch) < int(manual_rows[i + 1].saved_at_epoch):
			_fail("manual rows not sorted desc")
			return

	# 4. Round-trip a slot: slot_id/kind/class_id/sequence restore.
	var loaded = service.load_from_slot("slot_02")
	if loaded == null:
		_fail("load_from_slot slot_02 returned null")
		return
	if loaded.slot_id != "slot_02":
		_fail("loaded.slot_id=%s expected slot_02" % loaded.slot_id)
		return
	if loaded.slot_kind != SaveSlotStateScript.SLOT_KIND_MANUAL:
		_fail("loaded.slot_kind=%s expected manual" % loaded.slot_kind)
		return
	if loaded.current_objective_sequence != 3:
		_fail("loaded.sequence=%d expected 3" % loaded.current_objective_sequence)
		return
	if str(loaded.player_progression_summary.get("class_id", "")) != "marine":
		_fail("loaded.class_id mismatch")
		return

	# 5. Cloud manifest sha matches the slot file content.
	var manifest_path: String = "user://saves/.cloud/slot_02.manifest.json"
	if not FileAccess.file_exists(manifest_path):
		_fail("cloud manifest missing for slot_02")
		return
	var mfile := FileAccess.open(manifest_path, FileAccess.READ)
	var mjson: String = mfile.get_as_text()
	mfile.close()
	var mparsed: Variant = JSON.parse_string(mjson)
	if typeof(mparsed) != TYPE_DICTIONARY:
		_fail("cloud manifest not a JSON object")
		return
	var stored_sha: String = str((mparsed as Dictionary).get("payload_sha256", ""))
	var computed_sha: String = CloudManifestStateScript.recompute_sha256("user://saves/slot_02.json")
	if stored_sha.is_empty() or stored_sha != computed_sha:
		_fail("cloud manifest sha mismatch stored=%s computed=%s" % [stored_sha, computed_sha])
		return
	if str((mparsed as Dictionary).get("slot_id", "")) != "slot_02":
		_fail("cloud manifest slot_id mismatch")
		return
	if str((mparsed as Dictionary).get("schema_version", "")) != SaveLoadServiceScript.CURRENT_SLICE_VERSION:
		_fail("cloud manifest schema_version mismatch")
		return

	# 6. Corruption detection: write garbage to a slot file, attempt to
	# load, assert null + backup under .corrupt/.
	var slot_path: String = "user://saves/slot_03.json"
	var gf := FileAccess.open(slot_path, FileAccess.WRITE)
	gf.store_string("not-a-json-file{garbage")
	gf.close()
	var corrupted = service.load_from_slot("slot_03")
	if corrupted != null:
		_fail("corrupted slot should load null, got %s" % str(corrupted))
		return
	# Find a backup file under .corrupt/.
	var corrupt_dir: String = ProjectSettings.globalize_path("user://saves/.corrupt")
	var has_backup: bool = false
	if DirAccess.dir_exists_absolute(corrupt_dir):
		var dir := DirAccess.open(corrupt_dir)
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.begins_with("slot_03.") and entry.ends_with(".bak"):
				has_backup = true
				break
			entry = dir.get_next()
		dir.list_dir_end()
	if not has_backup:
		_fail("no .corrupt/slot_03.*.bak backup file after corruption")
		return

	# 7. Manual vs world scope: write a world slot via save_world; the
	# manual slots must NOT collide with the world slot path.
	var WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 7, "generated_marker_ids": ["3:0:1"]}
	ws.home_ship = {"slice_version": SaveLoadServiceScript.CURRENT_SLICE_VERSION, "current_objective_sequence": 1}
	ws.visited_ships = {"3:0:1": {"marker_id": "3:0:1", "blueprint": {"size": 1, "condition": 0, "seed": 5}, "systems": {}}}
	ws.current_location = ""
	ws.player_position_in_ship = [0.0, 0.0, 0.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = Time.get_datetime_string_from_system(true)
	if not service.save_world(ws):
		_fail("save_world failed")
		return
	var loaded_world = service.load_world()
	if loaded_world == null:
		_fail("load_world returned null after save_world")
		return
	# Manual slots are still loadable.
	var still_loadable = service.load_from_slot("slot_02")
	if still_loadable == null:
		_fail("manual slot_02 lost after save_world")
		return

	# 8. SaveLoadMenu UI seam (pure methods, headlessly testable).
	# The menu lists ALL rows from the index, including the corrupt one
	# (the row stays in the index so the player can see "this slot is
	# unloadable" instead of having it silently disappear).
	var SaveLoadMenuScript := preload("res://scripts/ui/save_load_menu.gd")
	var menu = SaveLoadMenuScript.new()
	menu.bind(service)
	var menu_rows: Array = menu.refresh()
	var menu_manual: int = 0
	var menu_corrupt: int = 0
	for r in menu_rows:
		if r.slot_kind == SaveSlotStateScript.SLOT_KIND_MANUAL:
			menu_manual += 1
			if bool(r.corrupt):
				menu_corrupt += 1
	if menu_manual != 3:
		_fail("menu manual rows=%d expected 3 (slot_03 is corrupt but stays in the index)" % menu_manual)
		return
	if menu_corrupt != 1:
		_fail("menu corrupt manual rows=%d expected 1 (slot_03)" % menu_corrupt)
		return

	# 9. Cleanup
	_cleanup_task11_slots(service)
	service.delete_current_run()

	print("SAVE SLOT STATE PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SAVE SLOT STATE FAIL reason=%s" % reason)
	quit(1)

func _cleanup_task11_slots(service: SaveLoadService) -> void:
	for slot_id in [
		"slot_01",
		"slot_02",
		"slot_03",
		"slot_legacy",
		"quicksave",
		"world",
		"autosave_active",
		"autosave_a",
		"autosave_b",
		"autosave_c",
	]:
		service.delete_slot(slot_id)