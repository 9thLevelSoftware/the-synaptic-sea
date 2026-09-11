extends SceneTree

## Save-file capture helper for the Unity parity fixture exporter.
##
## The stock save smokes delete their save files before exiting (run
## completion deletes the run save), so this helper replays the same main-scene
## flow as main_playable_slice_save_load_smoke.gd / *_multislot_save_smoke.gd
## and copies the real on-disk files mid-run.
##
## Usage (normally spawned by export_parity_fixtures.gd, which clears and
## restores user://saves around it):
##   godot --headless --path <project> --script \
##     res://scripts/validation/parity_fixtures/parity_capture_saves.gd -- \
##     --mode main|world --out <absolute dir>
##
## Marker: PARITY CAPTURE SAVES PASS mode=<mode> files=<n>

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const TIMEOUT_FRAMES: int = 900

var mode: String = ""
var out_dir: String = ""
var main_node: Node
var frame_count: int = 0
var finished: bool = false
var copied_files: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		if args[i] == "--mode" and i + 1 < args.size():
			mode = args[i + 1]
			i += 2
		elif args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]
			i += 2
		else:
			i += 1
	if out_dir.is_empty() or not (mode in ["main", "world"]):
		_fail("usage: --mode main|world --out <dir>")
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	if mode == "world":
		_capture_world()
		return
	SaveLoadService.new().delete_current_run()
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	main_node = scene.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)


func _capture_world() -> void:
	# Same WorldSnapshot as world_snapshot_smoke.gd, persisted through the
	# real SaveLoadService.save_world() path.
	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 99, "player_position": [1.0, 0.0, 2.0], "generated_marker_ids": ["3:1:0"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1", "player_position": [5.0, 1.0, 5.0]}
	ws.visited_ships = {
		"3:1:0": {"ship_id": "ship_3:1:0", "marker_id": "3:1:0", "blueprint": {"size": 1, "condition": 2, "seed": 7}, "systems": {"k": "v"}},
	}
	ws.current_location = "3:1:0"
	ws.player_position_in_ship = [10.0, 2.0, 3.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = "2026-06-21T00:00:00"
	_store(out_dir.path_join("world_snapshot_to_dict.json"), JSON.stringify(ws.to_dict(), "\t"))
	var service := SaveLoadService.new()
	if not service.save_world(ws):
		_fail("save_world failed")
		return
	_copy_user_data(out_dir.path_join("user_data"))
	finished = true
	print("PARITY CAPTURE SAVES PASS mode=world files=%d" % copied_files)
	quit(0)


func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable ship did not finish loading")
		return
	_capture_main(playable)


func _capture_main(playable: PlayableGeneratedShip) -> void:
	finished = true
	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if not playable.request_save():
		_fail("request_save returned false")
		return
	var snapshot: RunSnapshot = playable.get_last_saved_snapshot()
	if snapshot == null:
		_fail("last saved snapshot null")
		return
	if not service.save_to_slot("slot_01", snapshot, SaveSlotStateScript.SLOT_KIND_MANUAL, false, "Manual 1"):
		_fail("save_to_slot slot_01 failed")
		return
	if not service.save_to_slot("quicksave", snapshot, SaveSlotStateScript.SLOT_KIND_QUICK, true, "Quicksave"):
		_fail("save_to_slot quicksave failed")
		return
	if not service.save_current_run(snapshot):
		_fail("save_current_run failed")
		return
	_copy_user_data(out_dir.path_join("mid_run"))
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation failed")
		return
	_copy_user_data(out_dir.path_join("after_completion"))
	print("PARITY CAPTURE SAVES PASS mode=main files=%d" % copied_files)
	_quit_clean(0)


## Copies every file under user://saves (including .cloud/.corrupt) and every
## *.json directly under user:// into dest.
func _copy_user_data(dest: String) -> void:
	var user_root: String = OS.get_user_data_dir()
	_copy_tree(user_root.path_join("saves"), dest.path_join("saves"))
	var root_dir: DirAccess = DirAccess.open(user_root)
	if root_dir != null:
		for file_name in root_dir.get_files():
			if file_name.ends_with(".json"):
				_copy_file(user_root.path_join(file_name), dest.path_join(file_name))


func _copy_tree(source: String, dest: String) -> void:
	var dir: DirAccess = DirAccess.open(source)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		_copy_file(source.path_join(file_name), dest.path_join(file_name))
	for sub in dir.get_directories():
		_copy_tree(source.path_join(sub), dest.path_join(sub))


func _copy_file(source: String, dest: String) -> void:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		push_error("PARITY CAPTURE SAVES cannot write %s" % dest)
		return
	file.store_buffer(bytes)
	file.close()
	copied_files += 1


func _store(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
		copied_files += 1


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node == null:
		return null
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	finished = true
	push_error("PARITY CAPTURE SAVES FAIL mode=%s reason=%s" % [mode, reason])
	_quit_clean(1)


func _quit_clean(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		# Stop per-frame processing before teardown so nodes that cache the
		# player (e.g. CeilingFadeController) do not tick against freed objects.
		main_node.process_mode = Node.PROCESS_MODE_DISABLED
		main_node.queue_free()
	quit(code)
