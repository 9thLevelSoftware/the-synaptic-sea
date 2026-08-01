extends RefCounted
class_name PropVisualBindingCatalog

const DEFAULT_INDEX_PATH: String = "res://data/props/visual_bindings.generated.json"
const SCENE_PATH_PREFIX: String = "res://assets/imported/props/"
const INDEX_DOCUMENT_KIND: String = "prop_visual_binding_index"
const BINDING_DOCUMENT_KIND: String = "prop_visual_binding"
const GROUPS: Array[String] = ["components", "objectives", "dressing"]

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
	if root.get("document_kind", "") != INDEX_DOCUMENT_KIND:
		_errors.append("catalog document_kind must be %s" % INDEX_DOCUMENT_KIND)
	if not _is_major_schema_one(root.get("schema_version")):
		_errors.append("catalog schema_version must have major version 1")

	var loaded_groups: Dictionary = {}
	for group_name in GROUPS:
		loaded_groups[group_name] = _validate_group(root.get(group_name), group_name)
	if not _errors.is_empty():
		return false

	_component_bindings = loaded_groups["components"]
	_objective_bindings = loaded_groups["objectives"]
	_dressing_bindings = loaded_groups["dressing"]
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
	for key in group.keys():
		if typeof(key) != TYPE_STRING or str(key).is_empty():
			_errors.append("catalog group %s contains an invalid binding key" % group_name)
			continue
		var binding: Variant = group[key]
		if not (binding is Dictionary):
			_errors.append("catalog binding %s/%s must be an object" % [group_name, key])
			continue
		if _validate_binding(binding as Dictionary, group_name, str(key)):
			validated[str(key)] = (binding as Dictionary).duplicate(true)
	return validated


func _validate_binding(binding: Dictionary, group_name: String, binding_id: String) -> bool:
	var valid: bool = true
	if binding.get("document_kind", "") != BINDING_DOCUMENT_KIND:
		_errors.append("catalog binding %s/%s has invalid document_kind" % [group_name, binding_id])
		valid = false
	if not _is_major_schema_one(binding.get("schema_version")):
		_errors.append("catalog binding %s/%s has unsupported schema_version" % [group_name, binding_id])
		valid = false

	var scene_path: Variant = binding.get("visual_scene_path", "")
	if typeof(scene_path) != TYPE_STRING or str(scene_path).is_empty():
		_errors.append("catalog binding %s/%s has no visual_scene_path" % [group_name, binding_id])
		return false
	if not str(scene_path).begins_with(SCENE_PATH_PREFIX):
		_errors.append("catalog binding %s/%s scene path is outside imported props" % [group_name, binding_id])
		valid = false
	return valid


func _is_major_schema_one(value: Variant) -> bool:
	if typeof(value) == TYPE_STRING:
		var parts: PackedStringArray = str(value).split(".")
		return not parts.is_empty() and parts[0].is_valid_int() and int(parts[0]) == 1
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return is_finite(float(value)) and int(value) == 1
	return false
