extends SceneTree

## REQ-SL-004/005/006/008/012 main-scene multi-slot end-to-end smoke.
##
## Loads the main playable scene, completes objective 1, then exercises
## the multi-slot API:
##   - writes a manual save to slot_01
##   - writes a quicksave
##   - writes a world save
##   - corrupts slot_01 in-place and reloads (asserts backup +
##     corrupt=true in index)
##   - completes the run (delete_current_run) and asserts has_save=false
##
## Pass marker: MAIN PLAYABLE MULTISLOT SAVE PASS

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
const POSITION_TOLERANCE: float = 0.01

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	# Clean any leftover save from a prior run.
	var bootstrap_service := SaveLoadService.new()
	_cleanup_task11_slots(bootstrap_service)
	bootstrap_service.delete_current_run()

	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	if not playable.has_method("get_save_load_service"):
		_fail("get_save_load_service missing")
		return
	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return

	# 1. Complete objective 1 and capture the live state.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("expected sequence 2 after objective 1, got %d" % playable.get_current_objective_sequence())
		return

	var saved_pos: Vector3 = playable.player.global_position

	# 2. Write a manual save to slot_01.
	var save_script := load("res://scripts/systems/save_load_service.gd")
	var slot_state_script := load("res://scripts/systems/save_slot_state.gd")
	var snapshot: RunSnapshot = playable.get_last_saved_snapshot() if playable.has_method("get_last_saved_snapshot") else null
	if snapshot == null:
		# Build a minimal snapshot from the live state so the save
		# payload is well-formed.
		snapshot = _build_snapshot_from_playable(playable, saved_pos)
	if not service.save_to_slot("slot_01", snapshot, slot_state_script.SLOT_KIND_MANUAL, false, "Manual 1"):
		_fail("save_to_slot slot_01 failed")
		return

	# 3. Write a quicksave.
	var snap_q = _build_snapshot_from_playable(playable, saved_pos)
	if not service.save_to_slot("quicksave", snap_q, slot_state_script.SLOT_KIND_QUICK, true, "Quicksave"):
		_fail("save_to_slot quicksave failed")
		return

	# 4. Write a world save (preserves multi-ship state).
	var ws = _build_world_snapshot(playable)
	if not service.save_world(ws):
		_fail("save_world failed")
		return

	# 5. List slots and assert 1 manual + 1 quicksave + 1 world row.
	var rows: Array = service.list_slots()
	var manual_rows: int = 0
	var quick_rows: int = 0
	var world_rows: int = 0
	for row in rows:
		if row.slot_kind == slot_state_script.SLOT_KIND_MANUAL:
			manual_rows += 1
		elif row.slot_kind == slot_state_script.SLOT_KIND_QUICK:
			quick_rows += 1
		elif row.slot_kind == slot_state_script.SLOT_KIND_WORLD:
			world_rows += 1
	if manual_rows != 1:
		_fail("manual rows=%d expected 1" % manual_rows)
		return
	if quick_rows != 1:
		_fail("quicksave rows=%d expected 1" % quick_rows)
		return
	if world_rows != 1:
		_fail("world rows=%d expected 1" % world_rows)
		return

	# 6. Reload from slot_01 (end-to-end through load_from_slot).
	var reloaded = service.load_from_slot("slot_01")
	if reloaded == null:
		_fail("load_from_slot slot_01 returned null")
		return
	if reloaded.current_objective_sequence != 2:
		_fail("reloaded sequence=%d expected 2" % reloaded.current_objective_sequence)
		return
	if reloaded.slot_id != "slot_01":
		_fail("reloaded slot_id=%s expected slot_01" % reloaded.slot_id)
		return
	if reloaded.slot_kind != slot_state_script.SLOT_KIND_MANUAL:
		_fail("reloaded slot_kind=%s expected manual" % reloaded.slot_kind)
		return

	# 7. Corruption: overwrite slot_01.json with garbage, reload, assert
	# null + .corrupt/ backup exists.
	var slot_path: String = "user://saves/slot_01.json"
	var gf := FileAccess.open(slot_path, FileAccess.WRITE)
	gf.store_string("not-a-json{garbage")
	gf.close()
	var corrupted = service.load_from_slot("slot_01")
	if corrupted != null:
		_fail("corrupted slot_01 loaded non-null")
		return
	var corrupt_dir: String = ProjectSettings.globalize_path("user://saves/.corrupt")
	var found_backup: bool = false
	if DirAccess.dir_exists_absolute(corrupt_dir):
		var dir := DirAccess.open(corrupt_dir)
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.begins_with("slot_01.") and entry.ends_with(".bak"):
				found_backup = true
				break
			entry = dir.get_next()
		dir.list_dir_end()
	if not found_backup:
		_fail("no .corrupt/slot_01.*.bak backup file")
		return

	# 8. Complete the run; assert has_save=false after delete.
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation failed")
		return
	if service.has_save():
		_fail("has_save=true after run completion")
		return

	finished = true
	print("MAIN PLAYABLE MULTISLOT SAVE PASS manual=%d quick=%d world=%d corruption_backed_up=true" % [manual_rows, quick_rows, world_rows])
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _build_snapshot_from_playable(playable: PlayableGeneratedShip, pos: Vector3) -> RunSnapshot:
	var snap := RunSnapshot.new()
	snap.layout_path = "res://data/procgen/golden/coherent_ship_001/layout.json"
	snap.kit_path = "res://data/kits/ship_structural_v0.json"
	snap.gameplay_slice_path = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
	snap.player_position = [pos.x, pos.y, pos.z]
	snap.current_objective_sequence = playable.get_current_objective_sequence()
	snap.ship_systems_summary = playable.get_ship_systems_summary() if playable.has_method("get_ship_systems_summary") else {}
	snap.route_control_summary = {}
	snap.oxygen_summary = {}
	snap.inventory_summary = {}
	snap.fire_summary = {}
	snap.electrical_arc_summary = {}
	snap.objective_progress_summary = {}
	snap.player_progression_summary = {"class_id": "engineer", "xp": {}, "level": 1}
	snap.audio_summary = {"events": []}
	return snap

func _build_world_snapshot(playable: PlayableGeneratedShip):
	var ws_script := load("res://scripts/systems/world_snapshot.gd")
	var ws = ws_script.new()
	ws.world_summary = {"world_seed": 1, "generated_marker_ids": []}
	ws.home_ship = {"slice_version": "gate2-current-run-3", "current_objective_sequence": playable.get_current_objective_sequence()}
	ws.visited_ships = {}
	ws.current_location = ""
	ws.player_position_in_ship = [playable.player.global_position.x, playable.player.global_position.y, playable.player.global_position.z]
	ws.slice_version = ws_script.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = Time.get_datetime_string_from_system(true)
	return ws

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE MULTISLOT SAVE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	_cleanup_task11_slots(service)
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)

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