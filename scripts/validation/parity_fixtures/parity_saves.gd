extends RefCounted

## Save fixtures. Spawns the existing save smokes (and the capture helper) as
## child Godot processes with user://saves cleared before each run, then
## copies whatever each run left on disk into <out>/save/<run id>/.
##
## The user's real user://saves directory and user:// root *.json files
## (meta_progression.json, unlock_registry.json, ...) are MOVED to
## user://parity_fixture_backup_<unix>/ first and moved back afterwards.

const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")

const NOISE_LINES: Array = [
	"ERROR: Capture not registered: 'gdaimcp'.",
	"WARNING: ObjectDB instances leaked at exit",
]

var summary: Dictionary = {}
var _user_root: String = ""
var _backup_dir: String = ""


func _runs() -> Array:
	return [
		{"id": "main_playable_slice_save_load_smoke", "script": "res://scripts/validation/main_playable_slice_save_load_smoke.gd", "marker": "MAIN PLAYABLE SAVE LOAD PASS", "dest": "save/main_playable_slice_save_load_smoke"},
		{"id": "world_snapshot_smoke", "script": "res://scripts/validation/world_snapshot_smoke.gd", "marker": "WORLD SNAPSHOT PASS", "dest": "save/world_snapshot_smoke"},
		{"id": "main_playable_slice_multislot_save_smoke", "script": "res://scripts/validation/main_playable_slice_multislot_save_smoke.gd", "marker": "MAIN PLAYABLE MULTISLOT SAVE PASS", "dest": "save/main_playable_slice_multislot_save_smoke"},
		{"id": "parity_capture_saves_main", "script": "res://scripts/validation/parity_fixtures/parity_capture_saves.gd", "marker": "PARITY CAPTURE SAVES PASS mode=main", "dest": "save/capture_main_playable", "helper_args": ["--mode", "main"]},
		{"id": "parity_capture_saves_world", "script": "res://scripts/validation/parity_fixtures/parity_capture_saves.gd", "marker": "PARITY CAPTURE SAVES PASS mode=world", "dest": "save/capture_world_snapshot", "helper_args": ["--mode", "world"]},
		{"id": "save_migration_service_smoke", "script": "res://scripts/validation/save_migration_service_smoke.gd", "marker": "SAVE MIGRATION SERVICE PASS", "dest": "save/legacy/save_migration_service_smoke"},
		{"id": "save_migration_world_smoke", "script": "res://scripts/validation/save_migration_world_smoke.gd", "marker": "SAVE MIGRATION WORLD PASS", "dest": "save/legacy/save_migration_world_smoke"},
	]


func run(writer) -> bool:
	_user_root = OS.get_user_data_dir()
	if not _backup_user_data(writer):
		return false
	var ok: bool = true
	var records: Array = []
	for run_variant in _runs():
		var record: Dictionary = _execute(writer, run_variant)
		records.append(record)
		if not bool(record.get("pass", false)):
			ok = false
			writer.errors.append("save run %s did not print its PASS marker" % str(run_variant["id"]))
	_clear_user_data()
	if not _restore_user_data(writer):
		ok = false
	ok = _migration_cases(writer) and ok
	var readme: Dictionary = {
		"schema": "parity.save.readme.v1",
		"notes": [
			"Each run starts with user://saves deleted and every user:// root *.json removed (the user's real data is moved aside and restored afterwards).",
			"'<dest>/…' files marked residual were copied from user:// AFTER the process exited. The stock main-scene smokes delete their run saves on completion, so their residual set is small; parity_capture_saves_main replays the same flow and copies files mid-run (mid_run/) and after run completion (after_completion/).",
			"save/legacy/migration_cases.json holds in-process SaveMigrationService.migrate_run/migrate_world input/output pairs built from the dicts in save_migration_service_smoke.gd and save_migration_world_smoke.gd.",
			"No legacy/migration save fixture FILES are checked into the repo (tests/, tools/fixtures/, scripts/validation/ only embed legacy dicts inline in the migration smokes).",
		],
		"runs": records,
	}
	ok = writer.write_json("save/README.json", readme) and ok
	summary = {"runs": records.size()}
	return ok


func _execute(writer, run_spec: Dictionary) -> Dictionary:
	_clear_user_data()
	DirAccess.make_dir_recursive_absolute(_user_root.path_join("saves"))
	var dest: String = str(run_spec["dest"])
	var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", str(run_spec["script"])]
	if run_spec.has("helper_args"):
		args.append("--")
		args.append_array(run_spec["helper_args"])
		args.append("--out")
		args.append(writer.abs_path(dest))
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), PackedStringArray(args), output, true, false)
	var text: String = ""
	for chunk in output:
		text += str(chunk)
	var lines: PackedStringArray = text.split("\n")
	var marker_line: String = ""
	var unexpected: Array = []
	for raw_line in lines:
		var line: String = raw_line.strip_edges()
		if line.contains(str(run_spec["marker"])) and marker_line.is_empty():
			marker_line = line
		if line.begins_with("ERROR:") or line.begins_with("WARNING:") or line.begins_with("SCRIPT ERROR:") or line.contains("Parse Error"):
			var noise: bool = false
			for noise_line in NOISE_LINES:
				if line.begins_with(noise_line):
					noise = true
			if not noise and not unexpected.has(line):
				unexpected.append(line)
	# Residual files after exit.
	var residual: Array = []
	_copy_tree(writer, _user_root.path_join("saves"), dest.path_join("residual/saves"), residual)
	var root_dir: DirAccess = DirAccess.open(_user_root)
	if root_dir != null:
		for file_name in root_dir.get_files():
			if file_name.ends_with(".json"):
				if writer.copy_file_abs(_user_root.path_join(file_name), dest.path_join("residual").path_join(file_name)):
					residual.append(dest.path_join("residual").path_join(file_name))
	var captured: Array = []
	if run_spec.has("helper_args"):
		_list_tree(writer.abs_path(dest), dest, captured)
		for rel in captured:
			writer._track(rel)
	var log_rel: String = dest.path_join("process_output.txt")
	writer.write_text(log_rel, text)
	var command: String = "\"%s\" %s" % [OS.get_executable_path(), " ".join(PackedStringArray(args))]
	return {
		"id": run_spec["id"],
		"script": run_spec["script"],
		"command": command,
		"exit_code": exit_code,
		"pass_marker": run_spec["marker"],
		"pass": not marker_line.is_empty(),
		"marker_line": marker_line,
		"unexpected_error_or_warning_lines": unexpected,
		"output_log": log_rel,
		"residual_files": residual,
		"captured_files": captured.filter(func(p): return not str(p).contains("/residual/") and not str(p).ends_with("process_output.txt")),
	}


func _copy_tree(writer, source_abs: String, dest_rel: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(source_abs)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		var rel: String = dest_rel.path_join(file_name)
		if writer.copy_file_abs(source_abs.path_join(file_name), rel):
			out.append(rel)
	for sub in dir.get_directories():
		_copy_tree(writer, source_abs.path_join(sub), dest_rel.path_join(sub), out)


func _list_tree(abs_dir: String, rel_dir: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		out.append(rel_dir.path_join(file_name))
	for sub in dir.get_directories():
		_list_tree(abs_dir.path_join(sub), rel_dir.path_join(sub), out)


# --- user data backup / restore ------------------------------------------------

func _backup_user_data(writer) -> bool:
	_backup_dir = _user_root.path_join("parity_fixture_backup_%d" % int(Time.get_unix_time_from_system()))
	if DirAccess.make_dir_recursive_absolute(_backup_dir) != OK:
		writer.errors.append("cannot create backup dir %s" % _backup_dir)
		return false
	var saves: String = _user_root.path_join("saves")
	if DirAccess.dir_exists_absolute(saves):
		if DirAccess.rename_absolute(saves, _backup_dir.path_join("saves")) != OK:
			writer.errors.append("cannot move %s aside" % saves)
			return false
	var root_dir: DirAccess = DirAccess.open(_user_root)
	if root_dir != null:
		for file_name in root_dir.get_files():
			if file_name.ends_with(".json"):
				if DirAccess.rename_absolute(_user_root.path_join(file_name), _backup_dir.path_join(file_name)) != OK:
					writer.errors.append("cannot move %s aside" % file_name)
					return false
	return true


func _restore_user_data(writer) -> bool:
	if _backup_dir.is_empty() or not DirAccess.dir_exists_absolute(_backup_dir):
		return true
	var ok: bool = true
	var backup: DirAccess = DirAccess.open(_backup_dir)
	backup.include_hidden = true
	for file_name in backup.get_files():
		if DirAccess.rename_absolute(_backup_dir.path_join(file_name), _user_root.path_join(file_name)) != OK:
			writer.errors.append("cannot restore %s" % file_name)
			ok = false
	if DirAccess.dir_exists_absolute(_backup_dir.path_join("saves")):
		if DirAccess.rename_absolute(_backup_dir.path_join("saves"), _user_root.path_join("saves")) != OK:
			writer.errors.append("cannot restore saves directory from %s" % _backup_dir)
			ok = false
	else:
		DirAccess.make_dir_recursive_absolute(_user_root.path_join("saves"))
	if ok:
		DirAccess.remove_absolute(_backup_dir)
	return ok


func _clear_user_data() -> void:
	_remove_tree(_user_root.path_join("saves"))
	var root_dir: DirAccess = DirAccess.open(_user_root)
	if root_dir != null:
		for file_name in root_dir.get_files():
			if file_name.ends_with(".json"):
				DirAccess.remove_absolute(_user_root.path_join(file_name))


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	# Never recurse outside the project's user data directory.
	if not path.begins_with(_user_root) or path == _user_root:
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


# --- migration input/output pairs ------------------------------------------------

func _v1_run_dict() -> Dictionary:
	# Verbatim shape of save_migration_service_smoke.gd::_make_v1_dict().
	return {
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


func _migration_cases(writer) -> bool:
	var migrator = SaveMigrationServiceScript.new()
	var run_cases: Array = []
	for version_variant in SaveMigrationServiceScript.KNOWN_VERSIONS:
		var input: Dictionary = _v1_run_dict()
		input["slice_version"] = str(version_variant)
		run_cases.append({"case": "run_from_%s" % str(version_variant), "input": input.duplicate(true), "result": migrator.migrate_run(input.duplicate(true))})
	var newer: Dictionary = _v1_run_dict()
	newer["slice_version"] = "gate2-current-run-99"
	newer["some_future_field"] = {"magic": 1}
	run_cases.append({"case": "run_newer_than_current", "input": newer.duplicate(true), "result": migrator.migrate_run(newer.duplicate(true))})

	var world_inputs: Array = [
		["world_future_passthrough", {"slice_version": "world-99", "sentinel_field": "keep_me", "home_ship": {"slice_version": "gate2-current-run-99"}}],
		["world_legacy_world_2", {"slice_version": "world-2", "home_ship": {"slice_version": SaveMigrationServiceScript.KNOWN_VERSIONS[0], "player_position": [1.0, 0.0, 2.0]}}],
		["world_current_with_old_home_ship", {"slice_version": SaveMigrationServiceScript.WORLD_TARGET_VERSION, "home_ship": {"slice_version": SaveMigrationServiceScript.KNOWN_VERSIONS[2], "player_position": [4.0, 0.0, 8.0]}}],
	]
	var world_cases: Array = []
	for pair in world_inputs:
		var input: Dictionary = pair[1]
		world_cases.append({"case": pair[0], "input": input.duplicate(true), "result": migrator.migrate_world(input.duplicate(true))})
	var fixture: Dictionary = {
		"schema": "parity.save.migration_cases.v1",
		"source": "res://scripts/systems/save_migration_service.gd",
		"known_versions": SaveMigrationServiceScript.KNOWN_VERSIONS,
		"target_version": SaveMigrationServiceScript.TARGET_VERSION,
		"world_target_version": SaveMigrationServiceScript.WORLD_TARGET_VERSION,
		"notes": ["Inputs are the inline dicts from save_migration_service_smoke.gd (_make_v1_dict, restamped per known version) and save_migration_world_smoke.gd; godot_version is the capturing engine's version string."],
		"migrate_run": run_cases,
		"migrate_world": world_cases,
	}
	return writer.write_json("save/legacy/migration_cases.json", fixture)
