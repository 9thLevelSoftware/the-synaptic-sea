extends SceneTree

## One-shot exporter of Godot "parity fixtures" for the Unity C# port.
##
## Usage:
##   godot --headless --path <project> \
##     --script res://scripts/validation/export_parity_fixtures.gd -- \
##     --out <absolute output dir> [--sha <git sha>] [--skip-saves]
##
## Writes (under <out>):
##   meta.json                   engine version, source sha, binary, UTC time, file list
##   kernel/                     RNG, String.hash, JSON number/string formatting, FNV-1a
##   procgen/                    ShipLayoutGenerator layouts + gameplay slices + recipes
##   procgen/structural_debug/   procgen_structural_debug_export.gd output (child process)
##   loot/                       LootDistribution / LootRoller rolls for every table
##   models/                     pure RefCounted model tick + round-trip fixtures
##   save/                       real save files from the save smokes (child processes)
##
## The pure-GDScript procgen path is used throughout; ShipGenerator.generate_from_seed
## (native DerelictGenerator GDExtension on Windows) is never called.
##
## Marker: PARITY FIXTURES PASS files=<n>

const ParityWriterScript := preload("res://scripts/validation/parity_fixtures/parity_writer.gd")
const ParityKernelScript := preload("res://scripts/validation/parity_fixtures/parity_kernel.gd")
const ParityProcgenScript := preload("res://scripts/validation/parity_fixtures/parity_procgen.gd")
const ParityLootScript := preload("res://scripts/validation/parity_fixtures/parity_loot.gd")
const ParityModelsScript := preload("res://scripts/validation/parity_fixtures/parity_models.gd")
const ParitySavesScript := preload("res://scripts/validation/parity_fixtures/parity_saves.gd")

const MANAGED_ENTRIES: Array = ["kernel", "procgen", "loot", "models", "save", "meta.json"]
const DEBUG_EXPORT_SCRIPT: String = "res://scripts/validation/procgen_structural_debug_export.gd"


func _initialize() -> void:
	var options: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail(str(options.get("error", "bad arguments")))
		return
	var out_dir: String = str(options["out"])
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		_fail("cannot create output directory %s" % out_dir)
		return
	_clear_managed(out_dir)

	var writer = ParityWriterScript.new(out_dir)
	var stages: Dictionary = {}
	var ok: bool = true

	var kernel = ParityKernelScript.new()
	stages["kernel"] = kernel.run(writer)

	var procgen = ParityProcgenScript.new()
	stages["procgen"] = procgen.run(writer)
	stages["procgen_structural_debug"] = _structural_debug_exports(writer, procgen)

	var loot = ParityLootScript.new()
	stages["loot"] = loot.run(writer)

	var models = ParityModelsScript.new()
	stages["models"] = models.run(writer)

	var saves = ParitySavesScript.new()
	if bool(options.get("skip_saves", false)):
		stages["save"] = true
	else:
		stages["save"] = saves.run(writer)

	for stage in stages:
		if not bool(stages[stage]):
			ok = false

	var all_files: Array = []
	_list_files(out_dir, "", all_files)
	all_files = all_files.filter(func(p): return MANAGED_ENTRIES.has(str(p).split("/")[0]) and str(p) != "meta.json")
	all_files.sort()
	var counts: Dictionary = {}
	for rel in all_files:
		var top: String = str(rel).split("/")[0]
		counts[top] = int(counts.get(top, 0)) + 1
	var meta: Dictionary = {
		"schema": "parity.meta.v1",
		"engine_version_info": Engine.get_version_info(),
		"source_repo": "The Synaptic Sea (Godot)",
		"source_git_sha": str(options.get("sha", "")),
		"godot_binary": OS.get_executable_path(),
		"project_path": ProjectSettings.globalize_path("res://"),
		"captured_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"command": "\"%s\" --headless --path \"%s\" --script res://scripts/validation/export_parity_fixtures.gd -- %s" % [
			OS.get_executable_path(), ProjectSettings.globalize_path("res://"), " ".join(OS.get_cmdline_user_args())],
		"stages_ok": stages,
		"errors": writer.errors,
		"summaries": {
			"procgen": procgen.summary,
			"loot": loot.summary,
			"models": models.summary,
			"save": saves.summary,
		},
		"file_counts_by_folder": counts,
		"files": all_files,
	}
	if not writer.write_json("meta.json", meta):
		ok = false
	if not ok or not writer.errors.is_empty():
		for error_text in writer.errors:
			push_error("PARITY FIXTURES ERROR %s" % error_text)
		_fail("one or more stages failed: %s" % JSON.stringify(stages))
		return
	print("PARITY FIXTURES PASS files=%d" % (all_files.size() + 1))
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: String = ""
	var sha: String = ""
	var skip_saves: bool = false
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--out" and i + 1 < args.size():
			out = args[i + 1]
			i += 2
		elif arg == "--sha" and i + 1 < args.size():
			sha = args[i + 1]
			i += 2
		elif arg == "--skip-saves":
			skip_saves = true
			i += 1
		else:
			return {"ok": false, "error": "unknown argument %s" % arg}
	if out.is_empty():
		return {"ok": false, "error": "usage: -- --out <dir> [--sha <git sha>] [--skip-saves]"}
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path(out)
	return {"ok": true, "out": out.replace("\\", "/"), "sha": sha, "skip_saves": skip_saves}


func _structural_debug_exports(writer, procgen) -> bool:
	var ok: bool = true
	var records: Array = []
	for seed_variant in procgen.DEBUG_EXPORT_SEEDS:
		var seed_value: int = int(seed_variant)
		var rel: String = "procgen/structural_debug/seed_%d" % seed_value
		var args: PackedStringArray = PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", DEBUG_EXPORT_SCRIPT,
			"--", "--seed", str(seed_value), "--output-dir", writer.abs_path(rel)])
		var output: Array = []
		var exit_code: int = OS.execute(OS.get_executable_path(), args, output, true, false)
		var text: String = ""
		for chunk in output:
			text += str(chunk)
		var passed: bool = text.contains("PROCGEN STRUCTURAL DEBUG EXPORT PASS seed=%d" % seed_value)
		var unexpected: Array = []
		for raw_line in text.split("\n"):
			var line: String = raw_line.strip_edges()
			if (line.begins_with("ERROR:") or line.begins_with("WARNING:") or line.begins_with("SCRIPT ERROR:")) \
					and not line.begins_with("ERROR: Capture not registered: 'gdaimcp'.") \
					and not line.begins_with("WARNING: ObjectDB instances leaked at exit"):
				unexpected.append(line)
		for name in ["topology.json", "occupancy.json", "edge_map.json", "placements.json", "validation.json", "topdown_layout.png"]:
			if FileAccess.file_exists(writer.abs_path(rel.path_join(name))):
				writer._track(rel.path_join(name))
		if not passed or not unexpected.is_empty():
			ok = false
			writer.errors.append("structural debug export seed %d failed (exit %d): %s" % [seed_value, exit_code, text.right(400)])
		records.append({
			"seed": seed_value,
			"command": "\"%s\" %s" % [OS.get_executable_path(), " ".join(args)],
			"exit_code": exit_code,
			"pass": passed,
			"unexpected_error_or_warning_lines": unexpected,
		})
	var readme: Dictionary = {
		"schema": "parity.procgen.structural_debug.v1",
		"source": DEBUG_EXPORT_SCRIPT,
		"notes": ["Unmodified procgen_structural_debug_export.gd output (compact JSON + trailing newline, its own canonical record sorting) for the same seeds as procgen/layout_s<seed>_small_wrecked_ext.json."],
		"runs": records,
	}
	ok = writer.write_json("procgen/structural_debug/README.json", readme) and ok
	return ok


func _clear_managed(out_dir: String) -> void:
	for entry in MANAGED_ENTRIES:
		var path: String = out_dir.path_join(str(entry))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		elif DirAccess.dir_exists_absolute(path):
			_remove_tree(path)


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _list_files(abs_dir: String, rel_dir: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		out.append(file_name if rel_dir.is_empty() else rel_dir.path_join(file_name))
	for sub in dir.get_directories():
		_list_files(abs_dir.path_join(sub), sub if rel_dir.is_empty() else rel_dir.path_join(sub), out)


func _fail(reason: String) -> void:
	push_error("PARITY FIXTURES FAIL reason=%s" % reason)
	quit(1)
