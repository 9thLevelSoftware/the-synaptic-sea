extends RefCounted
class_name PropVisualBindingCatalog

const DEFAULT_INDEX_PATH: String = "res://data/props/visual_bindings.generated.json"
const SCENE_PATH_PREFIX: String = "res://assets/imported/props/"
const INDEX_DOCUMENT_KIND: String = "prop_visual_binding_index"
const BINDING_DOCUMENT_KIND: String = "prop_visual_binding"
const GROUPS: Array[String] = ["components", "objectives", "dressing"]
const INDEX_FIELDS: Array[String] = ["schema_version", "document_kind", "components", "objectives", "dressing"]
const BINDING_FIELDS: Array[String] = [
	"asset_id", "binding", "bounds", "collision_policy", "document_kind", "extensions",
	"placement", "prop_kind", "provenance", "schema_version", "source", "visual_scene_path",
]

var _component_bindings: Dictionary = {}
var _objective_bindings: Dictionary = {}
var _dressing_bindings: Dictionary = {}
var _errors: Array[String] = []


func load_from_path(path: String = DEFAULT_INDEX_PATH) -> bool:
	_clear_state()
	if path.is_empty():
		_errors.append("catalog path is empty")
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("cannot open catalog: %s" % path)
		return false

	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		_errors.append("catalog JSON parse failed: %s" % parser.get_error_message())
		return false

	var document: Variant = parser.data
	if not (document is Dictionary):
		_errors.append("catalog document must be an object")
		return false
	var root: Dictionary = document as Dictionary
	for key in root.keys():
		if not INDEX_FIELDS.has(str(key)):
			_errors.append("catalog has unexpected root field: %s" % key)
	if root.size() != INDEX_FIELDS.size():
		_errors.append("catalog root fields are incomplete")
	if root.get("document_kind", "") != INDEX_DOCUMENT_KIND:
		_errors.append("catalog document_kind must be %s" % INDEX_DOCUMENT_KIND)
	if not _is_exact_schema_version(root.get("schema_version")):
		_errors.append("catalog schema_version must be an exact 1.x.y string")

	var loaded_groups: Dictionary = {}
	for group_name in GROUPS:
		loaded_groups[group_name] = _validate_group(root.get(group_name), group_name)
	if not _errors.is_empty():
		return false

	_component_bindings = loaded_groups["components"] as Dictionary
	_objective_bindings = loaded_groups["objectives"] as Dictionary
	_dressing_bindings = loaded_groups["dressing"] as Dictionary
	return true


func get_component_binding(component_id: String) -> Dictionary:
	return _get_binding(_component_bindings, component_id)


func get_objective_binding(placement_id: String) -> Dictionary:
	return _get_binding(_objective_bindings, placement_id)


func get_dressing_binding(visual_prop_id: String) -> Dictionary:
	return _get_binding(_dressing_bindings, visual_prop_id)


func get_errors() -> Array[String]:
	return _errors.duplicate()


func _clear_state() -> void:
	_component_bindings.clear()
	_objective_bindings.clear()
	_dressing_bindings.clear()
	_errors.clear()


func _get_binding(bindings: Dictionary, key: String) -> Dictionary:
	if key.is_empty() or not bindings.has(key):
		return {}
	var binding: Variant = bindings[key]
	if not (binding is Dictionary):
		return {}
	return (binding as Dictionary).duplicate(true)


func _validate_group(value: Variant, group_name: String) -> Dictionary:
	var validated: Dictionary = {}
	if not (value is Dictionary):
		_errors.append("catalog group %s must be an object" % group_name)
		return validated

	var group: Dictionary = value as Dictionary
	var id_owners: Dictionary = {}
	for key in group.keys():
		if typeof(key) != TYPE_STRING or str(key).is_empty():
			_errors.append("catalog group %s contains an invalid binding key" % group_name)
			continue
		var binding: Variant = group[key]
		if not (binding is Dictionary):
			_errors.append("catalog binding %s/%s must be an object" % [group_name, key])
			continue
		if not _validate_binding(binding as Dictionary, group_name, str(key)):
			continue
		var binding_copy: Dictionary = (binding as Dictionary).duplicate(true)
		var binding_meta: Dictionary = binding_copy["binding"] as Dictionary
		var ids: Array = binding_meta["ids"] as Array
		for id_value in ids:
			var id: String = str(id_value)
			if id_owners.has(id):
				var owner: Dictionary = id_owners[id] as Dictionary
				if owner.get("asset_id", "") != binding_copy.get("asset_id", "") \
					or owner.get("visual_scene_path", "") != binding_copy.get("visual_scene_path", ""):
					_errors.append("catalog group %s has colliding binding id: %s" % [group_name, id])
			else:
				id_owners[id] = {
					"asset_id": binding_copy.get("asset_id", ""),
					"visual_scene_path": binding_copy.get("visual_scene_path", ""),
				}
		validated[str(key)] = binding_copy
	return validated


func _validate_binding(binding: Dictionary, group_name: String, binding_id: String) -> bool:
	var valid: bool = true
	for key in binding.keys():
		if not BINDING_FIELDS.has(str(key)):
			_errors.append("catalog binding %s/%s has unexpected field: %s" % [group_name, binding_id, key])
			valid = false
	for field_name in BINDING_FIELDS:
		if not binding.has(field_name):
			_errors.append("catalog binding %s/%s is missing field: %s" % [group_name, binding_id, field_name])
			valid = false
	if binding.size() != BINDING_FIELDS.size():
		valid = false

	if binding.get("document_kind", "") != BINDING_DOCUMENT_KIND:
		_errors.append("catalog binding %s/%s has invalid document_kind" % [group_name, binding_id])
		valid = false
	if not _is_exact_schema_version(binding.get("schema_version")):
		_errors.append("catalog binding %s/%s has unsupported schema_version" % [group_name, binding_id])
		valid = false
	if not _is_nonempty_string(binding.get("asset_id")):
		_errors.append("catalog binding %s/%s has an invalid asset_id" % [group_name, binding_id])
		valid = false
	if binding.get("prop_kind", "") != _expected_prop_kind(group_name):
		_errors.append("catalog binding %s/%s has invalid prop_kind" % [group_name, binding_id])
		valid = false
	if binding.get("collision_policy", "") != "none_visual_only":
		_errors.append("catalog binding %s/%s must use collision_policy none_visual_only" % [group_name, binding_id])
		valid = false

	var scene_path: Variant = binding.get("visual_scene_path", "")
	if not _is_canonical_scene_path(scene_path, group_name):
		_errors.append("catalog binding %s/%s scene path must be canonical imported prop GLB" % [group_name, binding_id])
		valid = false
	elif str(scene_path).get_file().trim_suffix(".glb") != str(binding.get("asset_id", "")):
		_errors.append("catalog binding %s/%s scene basename must match asset_id" % [group_name, binding_id])
		valid = false

	var binding_meta: Variant = binding.get("binding")
	if not (binding_meta is Dictionary):
		_errors.append("catalog binding %s/%s binding must be an object" % [group_name, binding_id])
		valid = false
	else:
		valid = _validate_binding_meta(binding_meta as Dictionary, group_name, binding_id) and valid
		var ids_value: Variant = (binding_meta as Dictionary).get("ids")
		if not (ids_value is Array):
			_errors.append("catalog binding %s/%s ids must include the map key" % [group_name, binding_id])
			valid = false
		else:
			var ids: Array = ids_value as Array
			if not ids.has(binding_id):
				_errors.append("catalog binding %s/%s ids must include the map key" % [group_name, binding_id])
				valid = false
			if group_name != "objectives" and (str(binding.get("asset_id", "")) != binding_id or ids.size() != 1):
				_errors.append("catalog binding %s/%s must map one component/dressing id" % [group_name, binding_id])
				valid = false

	var placement: Variant = binding.get("placement")
	if not (placement is Dictionary):
		_errors.append("catalog binding %s/%s placement must be an object" % [group_name, binding_id])
		valid = false
	else:
		valid = _validate_placement(placement as Dictionary, group_name, binding_id) and valid

	for nested_field in ["bounds", "source", "provenance", "extensions"]:
		if not (binding.get(nested_field) is Dictionary):
			_errors.append("catalog binding %s/%s %s must be an object" % [group_name, binding_id, nested_field])
			valid = false
	return valid


func _validate_binding_meta(binding_meta: Dictionary, group_name: String, binding_id: String) -> bool:
	var valid: bool = true
	for key in binding_meta.keys():
		if not ["namespace", "ids"].has(str(key)):
			_errors.append("catalog binding %s/%s binding has unexpected field: %s" % [group_name, binding_id, key])
			valid = false
	if binding_meta.size() != 2:
		valid = false
	var expected_namespace: String = _expected_namespace(group_name)
	if binding_meta.get("namespace", "") != expected_namespace:
		_errors.append("catalog binding %s/%s has invalid namespace" % [group_name, binding_id])
		valid = false
	var ids_value: Variant = binding_meta.get("ids")
	if not (ids_value is Array) or (ids_value as Array).is_empty():
		_errors.append("catalog binding %s/%s ids must be a nonempty array" % [group_name, binding_id])
		return false
	var ids: Array = ids_value as Array
	var seen: Dictionary = {}
	for id_value in ids:
		if not _is_nonempty_string(id_value):
			_errors.append("catalog binding %s/%s contains an invalid binding id" % [group_name, binding_id])
			valid = false
			continue
		var id: String = str(id_value)
		if seen.has(id):
			_errors.append("catalog binding %s/%s contains duplicate binding id: %s" % [group_name, binding_id, id])
			valid = false
		seen[id] = true
	return valid


func _validate_placement(placement: Dictionary, group_name: String, binding_id: String) -> bool:
	var valid: bool = true
	var expected_fields: Array[String] = ["origin", "offset_m", "rotation_degrees", "allowed_yaw_deg", "scale"]
	if group_name == "dressing":
		expected_fields.append("surface")
	for key in placement.keys():
		if not expected_fields.has(str(key)):
			_errors.append("catalog binding %s/%s placement has unexpected field: %s" % [group_name, binding_id, key])
			valid = false
	for field_name in expected_fields:
		if not placement.has(field_name):
			_errors.append("catalog binding %s/%s placement is missing field: %s" % [group_name, binding_id, field_name])
			valid = false
	if placement.size() != expected_fields.size():
		valid = false
	if placement.get("origin", "") != "scene_origin":
		_errors.append("catalog binding %s/%s placement origin is invalid" % [group_name, binding_id])
		valid = false
	if not _is_finite_vector(placement.get("offset_m")):
		_errors.append("catalog binding %s/%s offset_m must be a finite 3-vector" % [group_name, binding_id])
		valid = false
	if not _is_finite_vector(placement.get("rotation_degrees")):
		_errors.append("catalog binding %s/%s rotation_degrees must be a finite 3-vector" % [group_name, binding_id])
		valid = false
	var scale_value: Variant = placement.get("scale")
	if not _is_finite_number(scale_value) or float(scale_value) <= 0.0:
		_errors.append("catalog binding %s/%s scale must be finite and strictly positive" % [group_name, binding_id])
		valid = false
	var yaw_values: Variant = placement.get("allowed_yaw_deg")
	if not (yaw_values is Array) or (yaw_values as Array).is_empty():
		_errors.append("catalog binding %s/%s allowed_yaw_deg must be a nonempty array" % [group_name, binding_id])
		valid = false
	else:
		var yaws: Array = yaw_values as Array
		for yaw in yaws:
			if not _is_finite_number(yaw):
				_errors.append("catalog binding %s/%s allowed_yaw_deg must be finite" % [group_name, binding_id])
				valid = false
	if group_name == "dressing" and not _is_nonempty_string(placement.get("surface")):
		_errors.append("catalog binding %s/%s dressing surface must be a nonempty string" % [group_name, binding_id])
		valid = false
	return valid


func _is_canonical_scene_path(value: Variant, group_name: String) -> bool:
	if not _is_nonempty_string(value):
		return false
	var path: String = str(value)
	if not path.begins_with(SCENE_PATH_PREFIX) or path.simplify_path() != path:
		return false
	var relative: String = path.substr(SCENE_PATH_PREFIX.length())
	var parts: PackedStringArray = relative.split("/")
	if parts.size() != 2 or parts[0] != group_name:
		return false
	if parts[1].is_empty() or parts[1] == ".glb" or not parts[1].ends_with(".glb"):
		return false
	return not parts.has("") and not parts.has(".") and not parts.has("..")


func _expected_namespace(group_name: String) -> String:
	return {
		"components": "component_id",
		"objectives": "gameplay_placement_id",
		"dressing": "visual_prop_id",
	}.get(group_name, "")


func _expected_prop_kind(group_name: String) -> String:
	return {
		"components": "component",
		"objectives": "objective",
		"dressing": "dressing",
	}.get(group_name, "")


func _is_exact_schema_version(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var parts: PackedStringArray = str(value).split(".")
	return parts.size() == 3 and parts[0] == "1" \
		and _is_semver_number(parts[1]) and _is_semver_number(parts[2])


func _is_semver_number(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()


func _is_finite_vector(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	var values: Array = value as Array
	for item in values:
		if not _is_finite_number(item):
			return false
	return true


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))
