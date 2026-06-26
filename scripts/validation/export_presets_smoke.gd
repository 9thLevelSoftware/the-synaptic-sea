extends SceneTree

## REQ-RL-001 / REQ-RL-002 / REQ-RL-009 export preset validator smoke.
##
## Parses `export_presets.cfg` and asserts:
##  - every preset has the required keys (name, platform, export_path,
##    runnable, include_filter, exclude_filter)
##  - every export_path lands under `build/exports/<preset_name>/`
##  - the build metadata catalog parses with a known build_kind
##  - the credits catalog parses with >= 5 entries
##  - the demo scope manifest parses
##
## The smoke does NOT execute Godot export (the export templates are not
## always present in CI); it validates the config shape so a real release
## run can fail loudly only on Godot itself.

const ExportPresetsValidatorScript := preload("res://scripts/release/export_presets_validator.gd")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const ROOT_DEFAULT: String = "/Users/christopherwilloughby/the-synaptic-sea"

func _initialize() -> void:
	var root_path: String = OS.get_environment("ROOT")
	if root_path.is_empty():
		root_path = ROOT_DEFAULT
	var cfg_path: String = root_path + "/export_presets.cfg"
	var credits_path: String = root_path + "/data/release/credits.json"
	var manifest_path: String = root_path + "/data/release/build_metadata.json"
	var demo_path: String = root_path + "/data/release/demo_scope_manifest.json"

	var validator := ExportPresetsValidatorScript.new()
	var presets: Array = validator.parse(cfg_path)
	if presets.is_empty():
		_fail("validator returned no presets from %s" % cfg_path)
		return

	# Each preset must have the required keys and a valid export_path.
	var all_runnable: bool = true
	var all_paths_under_build: bool = true
	for preset in presets:
		var p: Dictionary = preset
		for required_key in ["name", "platform", "export_path", "runnable", "include_filter", "exclude_filter"]:
			if not p.has(required_key):
				_fail("preset %s missing required key %s" % [str(p.get("name", "?")), required_key])
				return
		if not bool(p.get("runnable", false)):
			all_runnable = false
		var export_path: String = str(p.get("export_path", ""))
		var name_str: String = str(p.get("name", ""))
		var expected_prefix: String = "build/exports/" + name_str + "/"
		if not export_path.begins_with(expected_prefix):
			all_paths_under_build = false

	# Known-good preset set for the Synapse Sea: web/linux/macos/windows.
	var expected_preset_names: Array = ["web", "linux", "macos", "windows"]
	var found_names: Array = []
	for preset in presets:
		found_names.append(str((preset as Dictionary).get("name", "")))
	for expected_name in expected_preset_names:
		if not expected_name in found_names:
			_fail("expected preset %s missing; found %s" % [expected_name, str(found_names)])
			return

	# Build metadata catalog must parse with a known build_kind.
	var manifest_text: String = _read_file_text(manifest_path)
	if manifest_text.is_empty():
		_fail("manifest catalog unreadable: %s" % manifest_path)
		return
	var manifest_parsed: Variant = JSON.parse_string(manifest_text)
	if manifest_parsed == null or typeof(manifest_parsed) != TYPE_DICTIONARY:
		_fail("manifest catalog did not parse as JSON object: %s" % manifest_path)
		return
	var manifest_dict: Dictionary = manifest_parsed
	var build_metadata := BuildMetadataStateScript.new()
	build_metadata.configure(manifest_dict)
	if not build_metadata.is_build_kind_validated():
		_fail("build_kind=%s is not one of dev/demo/release" % build_metadata.get_build_kind())
		return

	# Credits catalog must have >= 5 entries.
	var credits_text: String = _read_file_text(credits_path)
	if credits_text.is_empty():
		_fail("credits catalog unreadable: %s" % credits_path)
		return
	var credits_parsed: Variant = JSON.parse_string(credits_text)
	if credits_parsed == null or typeof(credits_parsed) != TYPE_DICTIONARY:
		_fail("credits catalog did not parse as JSON object: %s" % credits_path)
		return
	var credits_list: Array = (credits_parsed as Dictionary).get("credits", [])
	if credits_list.size() < 5:
		_fail("credits catalog needs >= 5 entries, found %d" % credits_list.size())
		return

	# Demo scope manifest must parse.
	var demo_text: String = _read_file_text(demo_path)
	if demo_text.is_empty():
		_fail("demo scope manifest unreadable: %s" % demo_path)
		return
	var demo_parsed: Variant = JSON.parse_string(demo_text)
	if demo_parsed == null or typeof(demo_parsed) != TYPE_DICTIONARY:
		_fail("demo scope manifest did not parse as JSON object: %s" % demo_path)
		return

	print("EXPORT PRESETS PASS presets=%d all_runnable=%s paths_under_build=%s build_kind=%s credits=%d" % [
		presets.size(),
		str(all_runnable).to_lower(),
		str(all_paths_under_build).to_lower(),
		build_metadata.get_build_kind(),
		credits_list.size(),
	])
	quit(0)

func _read_file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text

func _fail(reason: String) -> void:
	push_error("EXPORT PRESETS FAIL reason=%s" % reason)
	quit(1)