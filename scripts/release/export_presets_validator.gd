extends RefCounted
class_name ExportPresetsValidator

## REQ-RL-001 export preset validator.
##
## Pure data parser for `export_presets.cfg`. Returns a list of
## preset dictionaries; each preset carries every key the INI section
## contains, with type coercion (`runnable` -> bool, `dedicated_server`
## -> bool).
##
## Used by `export_presets_smoke.gd` to validate the SynapticSea export
## pipeline config before invoking `godot --export-release`.

const REQUIRED_KEYS: Array = [
	"name",
	"platform",
	"runnable",
	"dedicated_server",
	"export_path",
	"include_filter",
	"exclude_filter",
]

func parse(cfg_path: String) -> Array:
	var presets: Array = []
	if cfg_path.is_empty() or not FileAccess.file_exists(cfg_path):
		push_warning("ExportPresetsValidator: cfg not found: %s" % cfg_path)
		return presets
	var file := FileAccess.open(cfg_path, FileAccess.READ)
	if file == null:
		push_warning("ExportPresetsValidator: cannot open cfg, error=%d" % FileAccess.get_open_error())
		return presets
	var text: String = file.get_as_text()
	file.close()
	var current: Dictionary = {}
	var in_options: bool = false
	for raw_line in text.split("\n"):
		var line: String = String(raw_line).strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			# New section. Flush previous.
			if not current.is_empty() and not in_options:
				presets.append(current.duplicate())
			current = {}
			in_options = line == "[preset.0.options]" or line.ends_with(".options]")
			continue
		var eq_idx: int = line.find("=")
		if eq_idx <= 0:
			continue
		var key: String = line.substr(0, eq_idx).strip_edges()
		var value: String = line.substr(eq_idx + 1).strip_edges()
		current[key] = _coerce(value)
	if not current.is_empty() and not in_options:
		presets.append(current.duplicate())
	return presets

func _coerce(raw: String) -> Variant:
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.begins_with("\"") and raw.ends_with("\"") and raw.length() >= 2:
		return raw.substr(1, raw.length() - 2)
	# Strip PackedStringArray(...) and Color(...) wrappers defensively.
	if raw.begins_with("PackedStringArray(") or raw.begins_with("Color("):
		return raw
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	return raw

func get_preset_names(presets: Array) -> Array:
	var names: Array = []
	for preset in presets:
		names.append(str((preset as Dictionary).get("name", "")))
	return names

func has_required_keys(preset: Dictionary) -> bool:
	for key in REQUIRED_KEYS:
		if not (preset as Dictionary).has(key):
			return false
	return true

func validate_paths_under_build(presets: Array) -> bool:
	for preset in presets:
		var p: Dictionary = preset
		var export_path: String = str(p.get("export_path", ""))
		var name_str: String = str(p.get("name", ""))
		var expected_prefix: String = "build/exports/" + name_str + "/"
		if not export_path.begins_with(expected_prefix):
			return false
	return true