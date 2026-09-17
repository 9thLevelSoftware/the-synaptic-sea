extends SceneTree

## Unity-port parity capture: (a) load -> apply -> build -> save round trip of the
## capture_main_playable save files, (b) golden-ship power subcomponent wear trace.
##
## Usage (normally spawned by parity_run_roundtrip_wear.gd, which moves the
## user's real user://saves + user:// root *.json aside and restores them):
##   godot --headless --path <project> --script \
##     res://scripts/validation/parity_fixtures/parity_capture_roundtrip_wear.gd -- \
##     --mode roundtrip --in <capture_main_playable dir> --out <save_roundtrip dir> --clean-user-data
##   godot ... -- --mode wear --out <models dir> --clean-user-data
##
## --clean-user-data is required: this script deletes user://saves and user://*.json
## before every main-scene instance.
##
## Markers:
##   PARITY ROUNDTRIP PASS files=<n> applied=<n>
##   PARITY WEAR PASS ticks=<n> samples=<n>

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const WEAR_STEP_SECONDS: float = 0.25
const WEAR_TICKS: int = 120
const LOAD_TIMEOUT_FRAMES: int = 300

var mode: String = ""
var in_dir: String = ""
var out_dir: String = ""
var clean_ok: bool = false
var main_node: Node = null
var _failed: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--mode":
				mode = args[i + 1] if i + 1 < args.size() else ""
				i += 2
			"--in":
				in_dir = args[i + 1] if i + 1 < args.size() else ""
				i += 2
			"--out":
				out_dir = args[i + 1] if i + 1 < args.size() else ""
				i += 2
			"--clean-user-data":
				clean_ok = true
				i += 1
			_:
				i += 1
	if not clean_ok or out_dir.is_empty() or not (mode in ["roundtrip", "wear"]) or (mode == "roundtrip" and in_dir.is_empty()):
		_fail("usage: --mode roundtrip --in <dir> --out <dir> --clean-user-data | --mode wear --out <dir> --clean-user-data")
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	if mode == "roundtrip":
		_run_roundtrip()
	else:
		_run_wear()


# --- boot / teardown ----------------------------------------------------------

## Instantiates a fresh main.tscn and returns its PlayableGeneratedShip once the
## loader reports a loaded ship. The coordinator's _process is disabled right
## after add_child (the loader is synchronous inside _ready), so no engine-driven
## coordinator tick ever runs.
func _boot() -> PlayableGeneratedShip:
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	main_node = scene.instantiate()
	get_root().add_child(main_node)
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable != null:
		playable.set_process(false)
	var frames: int = 0
	while playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		await process_frame
		frames += 1
		if playable == null:
			playable = _find_playable(main_node)
			if playable != null:
				playable.set_process(false)
		if frames > LOAD_TIMEOUT_FRAMES:
			return null
	# One frame for deferred calls queued during boot (coordinator _process stays off).
	await process_frame
	return playable


func _teardown() -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.process_mode = Node.PROCESS_MODE_DISABLED
		main_node.queue_free()
	main_node = null
	await process_frame
	await process_frame


# --- (a) round trip -----------------------------------------------------------

func _roundtrip_cases() -> Array:
	return [
		{"rel": "mid_run/saves/current_run.json", "slot_id": SaveLoadService.ACTIVE_AUTOSAVE_SLOT_ID, "kind": SaveSlotStateScript.SLOT_KIND_AUTO, "quick": false, "display": "current_run_alias", "user_path": SaveLoadService.SAVE_PATH},
		{"rel": "mid_run/saves/quicksave.json", "slot_id": "quicksave", "kind": SaveSlotStateScript.SLOT_KIND_QUICK, "quick": true, "display": "Quicksave", "user_path": "user://saves/quicksave.json"},
		{"rel": "mid_run/saves/slot_01.json", "slot_id": "slot_01", "kind": SaveSlotStateScript.SLOT_KIND_MANUAL, "quick": false, "display": "Manual 1", "user_path": "user://saves/slot_01.json"},
		{"rel": "after_completion/saves/quicksave.json", "slot_id": "quicksave", "kind": SaveSlotStateScript.SLOT_KIND_QUICK, "quick": true, "display": "Quicksave", "user_path": "user://saves/quicksave.json"},
		{"rel": "after_completion/saves/slot_01.json", "slot_id": "slot_01", "kind": SaveSlotStateScript.SLOT_KIND_MANUAL, "quick": false, "display": "Manual 1", "user_path": "user://saves/slot_01.json"},
		{"rel": "residual/saves/quicksave.json", "slot_id": "quicksave", "kind": SaveSlotStateScript.SLOT_KIND_QUICK, "quick": true, "display": "Quicksave", "user_path": "user://saves/quicksave.json"},
		{"rel": "residual/saves/slot_01.json", "slot_id": "slot_01", "kind": SaveSlotStateScript.SLOT_KIND_MANUAL, "quick": false, "display": "Manual 1", "user_path": "user://saves/slot_01.json"},
		{"rel": "mid_run/saves/world.json", "world": true, "user_path": SaveLoadService.WORLD_SLOT_FILE},
	]


func _run_roundtrip() -> void:
	var results: Array = []
	var written: int = 0
	var applied: int = 0
	for case_variant in _roundtrip_cases():
		var c: Dictionary = case_variant
		var record: Dictionary = await _roundtrip_one(c)
		results.append(record)
		if bool(record.get("written", false)):
			written += 1
		if bool(record.get("apply_ok", false)):
			applied += 1
		print("PARITY ROUNDTRIP CASE %s" % JSON.stringify(record))
	_store(out_dir.path_join("roundtrip_results.json"), JSON.stringify({
		"schema": "parity.save_roundtrip.results.v1",
		"engine": Engine.get_version_info()["string"],
		"cases": results,
	}, "\t"))
	_clear_user_data()
	if written != results.size():
		_fail("only %d/%d round-trip files written" % [written, results.size()])
		return
	print("PARITY ROUNDTRIP PASS files=%d applied=%d" % [written, applied])
	quit(0)


func _roundtrip_one(c: Dictionary) -> Dictionary:
	var rel: String = str(c["rel"])
	var is_world: bool = bool(c.get("world", false))
	var record: Dictionary = {"file": rel, "world": is_world, "written": false}
	_clear_user_data()
	var playable: PlayableGeneratedShip = await _boot()
	if playable == null:
		record["error"] = "playable ship did not finish loading"
		await _teardown()
		return record
	var service: SaveLoadService = playable.get_save_load_service()
	record["boot_run_id"] = service.get_active_run_id()
	record["boot_objective_sequence"] = playable.current_objective_sequence
	record["boot_saves_files"] = _list_rel(OS.get_user_data_dir().path_join("saves"), "")
	# Only the fixture file on disk: no index, no .cloud manifest (no sha gate).
	_remove_tree(OS.get_user_data_dir().path_join("saves"))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("saves"))
	var text: String = FileAccess.get_file_as_string(in_dir.path_join(rel)).replace("\r\n", "\n")
	var parsed: Variant = JSON.parse_string(text)
	var file_run_id: String = str((parsed as Dictionary).get("run_id", "")) if parsed is Dictionary else ""
	record["file_run_id"] = file_run_id
	var user_path: String = str(c["user_path"])
	_store(user_path, text)
	if is_world:
		var ws = service.load_world()
		record["load_ok"] = ws != null
		if ws != null:
			record["apply_ok"] = playable._apply_world_snapshot(ws)
			record["objective_sequence_after_apply"] = playable.current_objective_sequence
			record["world_time_after_apply"] = playable.world_time
			service.set_active_run_id(file_run_id)
			record["save_ok"] = service.save_world(playable._build_world_snapshot())
	else:
		var slot_id: String = str(c["slot_id"])
		var snap: RunSnapshot = service.load_from_slot(slot_id)
		record["slot_id"] = slot_id
		record["load_ok"] = snap != null
		if snap != null:
			record["apply_ok"] = playable._apply_run_snapshot(snap)
			record["objective_sequence_after_apply"] = playable.current_objective_sequence
			record["slice_complete_after_apply"] = playable.slice_complete
			service.set_active_run_id(file_run_id)
			var built: RunSnapshot = playable._build_run_snapshot(false)
			record["build_ok"] = built != null
			if built != null:
				record["save_ok"] = service.save_to_slot(slot_id, built, str(c["kind"]), bool(c["quick"]), str(c["display"]))
	record["saves_files_after_save"] = _list_rel(OS.get_user_data_dir().path_join("saves"), "")
	if bool(record.get("save_ok", false)) and FileAccess.file_exists(user_path):
		record["written"] = _copy_file(ProjectSettings.globalize_path(user_path), out_dir.path_join(rel))
	await _teardown()
	return record


# --- (b) wear trace -----------------------------------------------------------

func _run_wear() -> void:
	_clear_user_data()
	var playable: PlayableGeneratedShip = await _boot()
	if playable == null:
		_fail("playable ship did not finish loading")
		return
	var notes: Array = []
	var threat_count_before: int = 0
	if playable.threat_manager != null:
		threat_count_before = playable.threat_manager.threats.size()
		playable.threat_manager.threats.clear()
		for node in playable.threat_manager.placeholder_nodes.values():
			if is_instance_valid(node):
				node.queue_free()
		playable.threat_manager.placeholder_nodes.clear()
	var player: Node3D = playable.player as Node3D
	if player == null:
		_fail("player missing")
		return
	player.set_physics_process(false)
	player.set_process(false)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	playable.set_process(false)
	var start_pos: Vector3 = player.global_position
	var slow_acc_start: float = float(playable.get("_hub_slow_acc"))
	var world_time_start: float = playable.world_time
	var samples: Array = [_wear_sample(playable, 0.0)]
	var t: float = 0.0
	var slice_flipped_at: Variant = null
	for tick in range(WEAR_TICKS):
		var was_complete: bool = playable.slice_complete
		playable._process(WEAR_STEP_SECONDS)
		t += WEAR_STEP_SECONDS
		if not was_complete and playable.slice_complete and slice_flipped_at == null:
			slice_flipped_at = t
		samples.append(_wear_sample(playable, t))
	var end_pos: Vector3 = player.global_position
	notes.append("All %d _process(%.2f) calls run synchronously inside one engine frame (after one boot frame); playable.set_process(false) was applied right after add_child, before any engine frame, so no engine-driven coordinator tick happened at boot or in between." % [WEAR_TICKS, WEAR_STEP_SECONDS])
	notes.append("Player: set_physics_process(false), set_process(false), velocity = Vector3.ZERO.")
	notes.append("Threats: threat_manager.threats.clear() (%d removed) and placeholder nodes freed; no other state touched." % threat_count_before)
	notes.append("Hub SLOW band: _hub_slow_acc=%s and world_time=%s before tick 1 (nothing reset). _recompute_expanded_ship_systems fires when the accumulator reaches ShipRuntime.SLOW_INTERVAL_SECONDS=0.35, i.e. on every 2nd 0.25 s tick with slow_dt=0.5." % [str(slow_acc_start), str(world_time_start)])
	notes.append("'power_percent' is read from playable.get_ship_systems_summary() (ShipSystemsManager.get_summary() has no power_percent key; recorded as manager_summary_power_percent=null).")
	var data: Dictionary = {
		"schema": "parity.models.power_wear.v1",
		"engine": Engine.get_version_info()["string"],
		"layout": playable.layout_path,
		"step_seconds": WEAR_STEP_SECONDS,
		"ticks": WEAR_TICKS,
		"threats_cleared": true,
		"threat_count_cleared": threat_count_before,
		"hub_slow_acc_start": slow_acc_start,
		"player_position_start": [start_pos.x, start_pos.y, start_pos.z],
		"player_position_end": [end_pos.x, end_pos.y, end_pos.z],
		"player_moved": start_pos != end_pos,
		"slice_complete_flipped_at": slice_flipped_at,
		"slice_completion_summary_end": playable.get_slice_completion_summary(),
		"notes": notes,
		"user_saves_after": _list_rel(OS.get_user_data_dir().path_join("saves"), ""),
		"samples": samples,
	}
	var path: String = out_dir.path_join("power_wear_coherent_ship_001.json")
	_store(path, JSON.stringify(data, "\t"))
	var lossy: bool = JSON.stringify(JSON.parse_string(JSON.stringify(data))) != JSON.stringify(JSON.parse_string(JSON.stringify(data, "", true, true)))
	if lossy:
		_store(out_dir.path_join("power_wear_coherent_ship_001.fullprec.json"), JSON.stringify(data, "\t", true, true))
	await _teardown()
	_clear_user_data()
	print("PARITY WEAR PASS ticks=%d samples=%d moved=%s slice_flipped=%s fullprec=%s" % [WEAR_TICKS, samples.size(), str(data["player_moved"]), str(slice_flipped_at != null), str(lossy)])
	quit(0)


func _wear_sample(playable: PlayableGeneratedShip, t: float) -> Dictionary:
	var systems: Dictionary = {}
	var mgr = playable.ship_systems_manager
	var manager_power_percent: Variant = null
	if mgr != null:
		for sid in mgr.system_order:
			var subs: Dictionary = {}
			for sub in mgr.systems[sid].subcomponents:
				subs[str(sub.subcomponent_id)] = float(sub.health)
			systems[str(sid)] = subs
		var ms: Dictionary = mgr.get_summary()
		manager_power_percent = ms.get("power_percent", null)
	var summary: Dictionary = playable.get_ship_systems_summary()
	return {
		"t": t,
		"world_time": playable.world_time,
		"run_play_time_seconds": playable.run_play_time_seconds,
		"slice_complete": playable.slice_complete,
		"hub_slow_acc": float(playable.get("_hub_slow_acc")),
		"manager_summary_power_percent": manager_power_percent,
		"power_percent": summary.get("power_percent", null),
		"vitals_health": float(playable.vitals_state.health) if playable.vitals_state != null else null,
		"oxygen": playable.get_oxygen_summary().get("oxygen", null),
		"systems": systems,
	}


# --- helpers ------------------------------------------------------------------

func _clear_user_data() -> void:
	var root: String = OS.get_user_data_dir()
	_remove_tree(root.path_join("saves"))
	var dir: DirAccess = DirAccess.open(root)
	if dir != null:
		for file_name in dir.get_files():
			if file_name.ends_with(".json"):
				DirAccess.remove_absolute(root.path_join(file_name))


func _remove_tree(path: String) -> void:
	var root: String = OS.get_user_data_dir()
	if not path.begins_with(root) or path == root or not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _list_rel(abs_dir: String, rel: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.include_hidden = true
	for file_name in dir.get_files():
		out.append(file_name if rel.is_empty() else rel.path_join(file_name))
	for sub in dir.get_directories():
		out.append_array(_list_rel(abs_dir.path_join(sub), sub if rel.is_empty() else rel.path_join(sub)))
	out.sort()
	return out


func _copy_file(source: String, dest: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		push_error("PARITY ROUNDTRIP cannot write %s" % dest)
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _store(path: String, text: String) -> void:
	var target: String = path
	if path.begins_with("user://"):
		target = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


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
	if _failed:
		return
	_failed = true
	push_error("PARITY ROUNDTRIP/WEAR FAIL mode=%s reason=%s" % [mode, reason])
	if main_node != null and is_instance_valid(main_node):
		main_node.process_mode = Node.PROCESS_MODE_DISABLED
		main_node.queue_free()
	quit(1)
