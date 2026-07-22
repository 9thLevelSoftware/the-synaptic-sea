extends RefCounted
class_name TuningCatalog

## Externalized balance numbers with const-friendly fallbacks.
##
## Pre-polish architecture prerequisite (PKG-A4): land the catalog shell first.
## Each later package migrates its own literals into data/balance/*.json
## opportunistically — this class does not mass-migrate the coordinator.

const DEFAULT_BALANCE_DIR: String = "res://data/balance/"

var _values: Dictionary = {}
var _loaded_paths: PackedStringArray = PackedStringArray()


func clear() -> void:
	_values.clear()
	_loaded_paths = PackedStringArray()


## Load one JSON object file. Keys are flat strings (or dotted paths as single keys).
## Non-dictionary roots and missing files leave existing values untouched and return false.
func load_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return false
	_merge_dict(parsed as Dictionary, "")
	if not path in _loaded_paths:
		_loaded_paths.append(path)
	return true


## Load every `*.json` directly under dir_path (non-recursive).
func load_directory(dir_path: String = DEFAULT_BALANCE_DIR) -> int:
	var loaded: int = 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var full: String = dir_path.path_join(entry) if dir_path.ends_with("/") else "%s/%s" % [dir_path.rstrip("/"), entry]
			# DirAccess + res://: prefer path_join when available
			full = dir_path.rstrip("/") + "/" + entry
			if load_file(full):
				loaded += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return loaded


func has_key(key: String) -> bool:
	return _values.has(key)


func get_float(key: String, default_value: float) -> float:
	if not _values.has(key):
		return default_value
	return float(_values[key])


func get_int(key: String, default_value: int) -> int:
	if not _values.has(key):
		return default_value
	return int(_values[key])


func get_bool(key: String, default_value: bool) -> bool:
	if not _values.has(key):
		return default_value
	return bool(_values[key])


func get_string(key: String, default_value: String) -> String:
	if not _values.has(key):
		return default_value
	return str(_values[key])


func get_value(key: String, default_value: Variant = null) -> Variant:
	if not _values.has(key):
		return default_value
	return _values[key]


func get_loaded_paths() -> PackedStringArray:
	return _loaded_paths.duplicate()


func key_count() -> int:
	return _values.size()


func _merge_dict(d: Dictionary, prefix: String) -> void:
	for k in d.keys():
		var key_str: String = str(k)
		var full_key: String = key_str if prefix.is_empty() else "%s.%s" % [prefix, key_str]
		var v: Variant = d[k]
		if typeof(v) == TYPE_DICTIONARY:
			_merge_dict(v as Dictionary, full_key)
		else:
			_values[full_key] = v
