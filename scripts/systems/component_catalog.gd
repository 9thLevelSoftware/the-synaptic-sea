extends RefCounted
class_name ComponentCatalog

## PKG-B2.3a: component definitions + per-role weighted placement sets.

const DEFAULT_PATH: String = "res://data/components/component_catalog.json"

var _components: Dictionary = {}
var _role_sets: Dictionary = {}
var _role_system_links: Dictionary = {}


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
	var comps: Variant = root.get("components", {})
	var roles: Variant = root.get("role_sets", {})
	var links: Variant = root.get("role_system_links", {})
	if typeof(comps) != TYPE_DICTIONARY or typeof(roles) != TYPE_DICTIONARY:
		return false
	_components = (comps as Dictionary).duplicate(true)
	_role_sets = (roles as Dictionary).duplicate(true)
	if typeof(links) == TYPE_DICTIONARY:
		_role_system_links = (links as Dictionary).duplicate(true)
	return not _components.is_empty()


func has_component(component_id: String) -> bool:
	return _components.has(component_id)


func get_component(component_id: String) -> Dictionary:
	if not _components.has(component_id):
		return {}
	return (_components[component_id] as Dictionary).duplicate(true)


func component_count() -> int:
	return _components.size()


func role_set(role: String, slot_kind: String) -> Array:
	var role_key: String = role if _role_sets.has(role) else "default"
	var set_dict: Variant = _role_sets.get(role_key, {})
	if typeof(set_dict) != TYPE_DICTIONARY:
		return []
	var entries: Variant = (set_dict as Dictionary).get(slot_kind, [])
	if typeof(entries) != TYPE_ARRAY:
		return []
	return (entries as Array).duplicate(true)


func systems_for_role(role: String) -> Array:
	var raw: Variant = _role_system_links.get(role, [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return (raw as Array).duplicate(true)


## PKG-B2.3b: reverse lookup for remount / inventory item_form → component_id.
func component_id_for_item_form(item_form: String) -> String:
	if item_form.is_empty():
		return ""
	for cid in _components.keys():
		var def: Dictionary = _components[cid]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var form: String = str((def as Dictionary).get("item_form", cid))
		if form == item_form or str(cid) == item_form:
			return str(cid)
	return ""
