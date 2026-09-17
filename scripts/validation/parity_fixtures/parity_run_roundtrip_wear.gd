extends SceneTree

## Runner for parity_capture_roundtrip_wear.gd. Moves the user's real
## user://saves and user:// root *.json aside (same helpers as parity_saves.gd),
## spawns the capture in --mode roundtrip and --mode wear as child processes,
## restores the user's data, and writes <fixtures>/save_roundtrip/README.json
## plus the process output logs.
##
## Usage:
##   godot --headless --path <project> --script \
##     res://scripts/validation/parity_fixtures/parity_run_roundtrip_wear.gd -- \
##     --fixtures <.../fixtures/godot> [--sha <git sha>]
##
## Marker: PARITY ROUNDTRIP WEAR RUNNER PASS runs=<n>

const ParityWriterScript := preload("res://scripts/validation/parity_fixtures/parity_writer.gd")
const ParitySavesScript := preload("res://scripts/validation/parity_fixtures/parity_saves.gd")
const CAPTURE_SCRIPT: String = "res://scripts/validation/parity_fixtures/parity_capture_roundtrip_wear.gd"


func _initialize() -> void:
	var fixtures: String = ""
	var sha: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		if args[i] == "--fixtures" and i + 1 < args.size():
			fixtures = args[i + 1]
			i += 2
		elif args[i] == "--sha" and i + 1 < args.size():
			sha = args[i + 1]
			i += 2
		else:
			i += 1
	if fixtures.is_empty():
		push_error("PARITY ROUNDTRIP WEAR RUNNER FAIL reason=usage: --fixtures <dir> [--sha <sha>]")
		quit(1)
		return
	fixtures = fixtures.replace("\\", "/")
	var writer = ParityWriterScript.new(fixtures)
	var saves = ParitySavesScript.new()
	saves._user_root = OS.get_user_data_dir()
	if not saves._backup_user_data(writer):
		push_error("PARITY ROUNDTRIP WEAR RUNNER FAIL reason=backup failed %s" % str(writer.errors))
		quit(1)
		return
	var runs: Array = [
		{"id": "parity_capture_roundtrip", "marker": "PARITY ROUNDTRIP PASS", "log": "save_roundtrip/process_output_roundtrip.txt",
			"args": ["--mode", "roundtrip", "--in", writer.abs_path("save/capture_main_playable"), "--out", writer.abs_path("save_roundtrip"), "--clean-user-data"]},
		{"id": "parity_capture_power_wear", "marker": "PARITY WEAR PASS", "log": "models/power_wear_process_output.txt",
			"args": ["--mode", "wear", "--out", writer.abs_path("models"), "--clean-user-data"]},
	]
	var records: Array = []
	var ok: bool = true
	for run in runs:
		var record: Dictionary = _execute(writer, saves, run)
		records.append(record)
		ok = ok and bool(record["pass"])
	saves._clear_user_data()
	if not saves._restore_user_data(writer):
		ok = false
	var readme: Dictionary = {
		"schema": "parity.save.readme.v1",
		"source_git_sha": sha,
		"engine": Engine.get_version_info()["string"],
		"notes": [
			"Both runs start with user://saves deleted and every user:// root *.json removed; the capture script re-clears them before every fresh main.tscn instance (the user's real data is moved aside and restored afterwards).",
			"Round trip, per file (fresh main.tscn instance each, coordinator _process disabled right after add_child so no engine tick runs): after boot user://saves is emptied again (no index, no .cloud manifest -> no sha gate), the fixture text (CRLF->LF) is written to the slot file, SaveLoadService.load_from_slot(slot_id) (current_run.json: slot 'autosave_active', i.e. load_current_run) -> PlayableGeneratedShip._apply_run_snapshot -> SaveLoadService.set_active_run_id(<file run_id>) -> save_to_slot(slot_id, _build_run_snapshot(false), kind, quick, display) (current_run.json: 'autosave_active', 'auto', false, 'current_run_alias' == save_current_run). The written slot file is copied byte-for-byte to save_roundtrip/<same relative path>.",
			"World: mid_run/saves/world.json -> user://saves/world.json -> load_world -> _apply_world_snapshot -> set_active_run_id(<file run_id>) -> save_world(_build_world_snapshot()) -> save_roundtrip/mid_run/saves/world.json.",
			"save_roundtrip/roundtrip_results.json records per file: load_ok, apply_ok, objective_sequence_after_apply, build/save results, and the user://saves listing right after boot and after the save.",
			"saved_at / saved_at_epoch: the loaded RunSnapshot keeps the file's saved_at_epoch (save_to_slot only stamps it when 0) but _build_run_snapshot / _build_world_snapshot stamp a fresh saved_at, so saved_at is wall-clock.",
			"Power wear trace: models/power_wear_coherent_ship_001.json (notes inside describe the tick setup).",
		],
		"runs": records,
	}
	ok = writer.write_json("save_roundtrip/README.json", readme) and ok
	if not ok or not writer.errors.is_empty():
		push_error("PARITY ROUNDTRIP WEAR RUNNER FAIL errors=%s" % str(writer.errors))
		quit(1)
		return
	print("PARITY ROUNDTRIP WEAR RUNNER PASS runs=%d" % records.size())
	quit(0)


func _execute(writer, saves, run: Dictionary) -> Dictionary:
	saves._clear_user_data()
	DirAccess.make_dir_recursive_absolute(saves._user_root.path_join("saves"))
	var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CAPTURE_SCRIPT, "--"]
	args.append_array(run["args"])
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray(args), output, true, false)
	var text: String = ""
	for chunk in output:
		text += str(chunk)
	var marker_line: String = ""
	var unexpected: Array = []
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if marker_line.is_empty() and line.contains(str(run["marker"])):
			marker_line = line
		if line.begins_with("ERROR:") or line.begins_with("WARNING:") or line.begins_with("SCRIPT ERROR:") or line.contains("Parse Error"):
			var noise: bool = false
			for noise_line in ParitySavesScript.NOISE_LINES:
				if line.begins_with(noise_line):
					noise = true
			if not noise and not unexpected.has(line):
				unexpected.append(line)
	writer.write_text(str(run["log"]), text)
	return {
		"id": run["id"],
		"script": CAPTURE_SCRIPT,
		"command": "\"%s\" %s" % [OS.get_executable_path(), " ".join(PackedStringArray(args))],
		"exit_code": exit_code,
		"pass_marker": run["marker"],
		"pass": not marker_line.is_empty() and exit_code == 0,
		"marker_line": marker_line,
		"output_log": run["log"],
		"unexpected_error_or_warning_lines": unexpected,
	}
