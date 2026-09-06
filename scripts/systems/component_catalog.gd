extends RefCounted
class_name ComponentCatalog

## PKG-B2.3a: component definitions + per-role weighted placement sets.

const DEFAULT_PATH: String = "res://data/components/component_catalog.json"

var _components: Dictionary = {}
var _role_sets: Dictionary = {}
var _role_system_links: Dictionary = {}
var _slot_profiles: Dictionary = {}


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
	var profiles: Variant = root.get("slot_profiles", {})
	if typeof(comps) != TYPE_DICTIONARY or typeof(roles) != TYPE_DICTIONARY:
		return false
	_components = (comps as Dictionary).duplicate(true)
	_role_sets = (roles as Dictionary).duplicate(true)
	if typeof(links) == TYPE_DICTIONARY:
		_role_system_links = (links as Dictionary).duplicate(true)
	if typeof(profiles) == TYPE_DICTIONARY:
		_slot_profiles = (profiles as Dictionary).duplicate(true)
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


## Exact authored fit contract named by a generated physical slot record.
## Callers must pass the recorded profile ID; slot_kind is never a fallback.
func get_slot_profile(profile_id: String) -> Dictionary:
	if profile_id.is_empty() or not _slot_profiles.has(profile_id):
		return {}
	return (_slot_profiles[profile_id] as Dictionary).duplicate(true)


func validate_component_fit(component_id: String, slot: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": ""}
	if not has_component(component_id):
		out["reason"] = "unknown_component"
		return out
	var profile_id: String = str(slot.get("component_slot_profile_id", ""))
	var profile: Dictionary = get_slot_profile(profile_id)
	if profile.is_empty():
		out["reason"] = "missing_fit_contract"
		return out
	var definition: Dictionary = get_component(component_id)
	var required_slot: String = str(definition.get("slot", ""))
	var actual_slot: String = str(slot.get("slot_kind", ""))
	if required_slot.is_empty() or (required_slot != "any" and required_slot != actual_slot):
		out["reason"] = "incompatible_slot"
		return out
	var component_footprint: Variant = definition.get("footprint_cells", [])
	var slot_footprint: Variant = profile.get("footprint_cells", [])
	if not (component_footprint is Array) or not (slot_footprint is Array) \
			or (component_footprint as Array).is_empty() or (slot_footprint as Array).is_empty():
		out["reason"] = "missing_fit_contract"
		return out
	if not _same_footprint(component_footprint as Array, slot_footprint as Array):
		out["reason"] = "incompatible_footprint"
		return out
	var accepted_sockets: Array = []
	var plural: Variant = definition.get("socket_types", null)
	if plural is Array and not (plural as Array).is_empty():
		accepted_sockets = (plural as Array).duplicate()
	else:
		var singular: String = str(definition.get("socket_type", ""))
		if not singular.is_empty():
			accepted_sockets.append(singular)
	var slot_socket: String = str(profile.get("socket_type", ""))
	if slot_socket.is_empty() or not accepted_sockets.has(slot_socket):
		out["reason"] = "incompatible_socket"
		return out
	var component_type: String = str(definition.get("component_type", ""))
	var allowed: Variant = profile.get("allowed_component_types", [])
	if component_type.is_empty() or not (allowed is Array) or not (allowed as Array).has(component_type):
		out["reason"] = "incompatible_type"
		return out
	out["ok"] = true
	out["profile"] = profile
	out["definition"] = definition
	return out


func catalogued_inventory_components(inventory: Dictionary) -> Array:
	var rows: Array = []
	for item_v in inventory.keys():
		var item_form: String = str(item_v)
		if int(inventory.get(item_v, 0)) <= 0:
			continue
		var component_id: String = component_id_for_item_form(item_form)
		if component_id.is_empty():
			continue
		rows.append({"component_id": component_id, "item_form": item_form})
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("item_form", "")) < str(right.get("item_form", "")))
	return rows


func _same_footprint(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if int(left[index]) != int(right[index]):
			return false
	return true


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
