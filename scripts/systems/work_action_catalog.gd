extends RefCounted
class_name WorkActionCatalog

## PKG-B2.2a: data-driven WorkAction definitions.

const DEFAULT_PATH: String = "res://data/work_actions/work_action_catalog.json"

var _actions: Dictionary = {}
var _loaded_path: String = ""


func load_default() -> bool:
	return load_file(DEFAULT_PATH)


func load_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var root: Dictionary = parsed
	var actions_v: Variant = root.get("actions", {})
	if typeof(actions_v) != TYPE_DICTIONARY:
		return false
	_actions.clear()
	for action_id in (actions_v as Dictionary).keys():
		var row: Variant = actions_v[action_id]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_actions[str(action_id)] = (row as Dictionary).duplicate(true)
	_loaded_path = path
	return not _actions.is_empty()


func has_action(action_id: String) -> bool:
	return _actions.has(action_id)


func get_action(action_id: String) -> Dictionary:
	if not _actions.has(action_id):
		return {}
	return (_actions[action_id] as Dictionary).duplicate(true)


func action_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in _actions.keys():
		out.append(str(k))
	out.sort()
	return out


func action_count() -> int:
	return _actions.size()
