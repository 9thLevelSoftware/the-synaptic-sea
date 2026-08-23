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
var _json_scan_text: String = ""
var _json_scan_index: int = 0
var _duplicate_json_key_found: bool = false


func load_from_path(path: String = DEFAULT_INDEX_PATH) -> bool:
	_clear_state()
	if path.is_empty():
		_errors.append("catalog path is empty")
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("cannot open catalog: %s" % path)
		return false

	var raw_document: String = file.get_as_text()
	file.close()
	if _contains_duplicate_json_key(raw_document):
		_errors.append("catalog JSON contains duplicate JSON object key")
		return false
	var parser := JSON.new()
	var parse_error: Error = parser.parse(raw_document)
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


func _contains_duplicate_json_key(text: String) -> bool:
	_json_scan_text = text
	_json_scan_index = 0
	_duplicate_json_key_found = false
	var scan_valid: bool = _scan_json_value()
	_skip_json_whitespace()
	return scan_valid and _json_scan_index == _json_scan_text.length() and _duplicate_json_key_found


func _scan_json_value() -> bool:
	_skip_json_whitespace()
	if _json_scan_index >= _json_scan_text.length():
		return false
	var character: String = _json_scan_text.substr(_json_scan_index, 1)
	if character == "{":
		return _scan_json_object()
	if character == "[":
		return _scan_json_array()
	if character == "\"":
		return _scan_json_string_token() != null
	if character == "t" and _scan_json_literal("true"):
		return true
	if character == "f" and _scan_json_literal("false"):
		return true
	if character == "n" and _scan_json_literal("null"):
		return true
	return _scan_json_number()


func _scan_json_object() -> bool:
	_json_scan_index += 1
	_skip_json_whitespace()
	var seen_keys: Dictionary = {}
	if _json_scan_index < _json_scan_text.length() and _json_scan_text.substr(_json_scan_index, 1) == "}":
		_json_scan_index += 1
		return true
	while _json_scan_index < _json_scan_text.length():
		_skip_json_whitespace()
		var key_value: Variant = _scan_json_string_token()
		if key_value == null:
			return false
		var key: String = str(key_value)
		if seen_keys.has(key):
			_duplicate_json_key_found = true
		seen_keys[key] = true
		_skip_json_whitespace()
		if _json_scan_index >= _json_scan_text.length() or _json_scan_text.substr(_json_scan_index, 1) != ":":
			return false
		_json_scan_index += 1
		if not _scan_json_value():
			return false
		_skip_json_whitespace()
		if _json_scan_index >= _json_scan_text.length():
			return false
		var delimiter: String = _json_scan_text.substr(_json_scan_index, 1)
		if delimiter == "}":
			_json_scan_index += 1
			return true
		if delimiter != ",":
			return false
		_json_scan_index += 1
	return false


func _scan_json_array() -> bool:
	_json_scan_index += 1
	_skip_json_whitespace()
	if _json_scan_index < _json_scan_text.length() and _json_scan_text.substr(_json_scan_index, 1) == "]":
		_json_scan_index += 1
		return true
	while _json_scan_index < _json_scan_text.length():
		if not _scan_json_value():
			return false
		_skip_json_whitespace()
		if _json_scan_index >= _json_scan_text.length():
			return false
		var delimiter: String = _json_scan_text.substr(_json_scan_index, 1)
		if delimiter == "]":
			_json_scan_index += 1
			return true
		if delimiter != ",":
			return false
		_json_scan_index += 1
	return false


func _scan_json_string_token() -> Variant:
	if _json_scan_index >= _json_scan_text.length() or _json_scan_text.substr(_json_scan_index, 1) != "\"":
		return null
	var start: int = _json_scan_index
	_json_scan_index += 1
	while _json_scan_index < _json_scan_text.length():
		var character: String = _json_scan_text.substr(_json_scan_index, 1)
		if character == "\\":
			_json_scan_index += 2
			continue
		_json_scan_index += 1
		if character == "\"":
			var raw_string: String = _json_scan_text.substr(start, _json_scan_index - start)
			var decoded: Variant = JSON.parse_string(raw_string)
			return decoded if typeof(decoded) == TYPE_STRING else null
	return null


func _scan_json_literal(literal: String) -> bool:
	if _json_scan_text.substr(_json_scan_index, literal.length()) != literal:
		return false
	_json_scan_index += literal.length()
	return true


func _scan_json_number() -> bool:
	var start: int = _json_scan_index
	while _json_scan_index < _json_scan_text.length():
		var character: String = _json_scan_text.substr(_json_scan_index, 1)
		if "{}[],: \t\r\n".contains(character):
			break
		_json_scan_index += 1
	return _json_scan_index > start


func _skip_json_whitespace() -> void:
	while _json_scan_index < _json_scan_text.length():
		if not " \t\r\n".contains(_json_scan_text.substr(_json_scan_index, 1)):
			return
		_json_scan_index += 1


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
	if not _is_asset_id(binding.get("asset_id")):
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

	valid = _validate_source(binding.get("source"), group_name, binding_id) and valid
	valid = _validate_bounds(binding.get("bounds"), group_name, binding_id) and valid
	valid = _validate_provenance(binding.get("provenance"), group_name, binding_id) and valid
	if not (binding.get("extensions") is Dictionary):
		_errors.append("catalog binding %s/%s extensions must be an object" % [group_name, binding_id])
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
	var required_fields: Array[String] = ["origin", "offset_m", "rotation_degrees", "allowed_yaw_deg", "scale"]
	var surface_allowed: bool = group_name == "dressing" or group_name == "objectives"
	var allowed_fields: Array[String] = required_fields.duplicate()
	if surface_allowed:
		allowed_fields.append("surface")
	for key in placement.keys():
		if not allowed_fields.has(str(key)):
			_errors.append("catalog binding %s/%s placement has unexpected field: %s" % [group_name, binding_id, key])
			valid = false
	for field_name in required_fields:
		if not placement.has(field_name):
			_errors.append("catalog binding %s/%s placement is missing field: %s" % [group_name, binding_id, field_name])
			valid = false
	if placement.size() < required_fields.size() or placement.size() > allowed_fields.size():
		valid = false
	if not ["scene_origin", "marker_anchor"].has(placement.get("origin", "")):
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
		var seen_yaws: Array = []
		for yaw in yaws:
			if not _is_finite_number(yaw):
				_errors.append("catalog binding %s/%s allowed_yaw_deg must be finite" % [group_name, binding_id])
				valid = false
				continue
			var yaw_number: float = float(yaw)
			if seen_yaws.has(yaw_number):
				_errors.append("catalog binding %s/%s allowed_yaw_deg contains duplicate yaw" % [group_name, binding_id])
				valid = false
			seen_yaws.append(yaw_number)
	if placement.has("surface") and not ["floor", "wall", "ceiling"].has(placement.get("surface", "")):
		_errors.append("catalog binding %s/%s surface must be floor, wall, or ceiling" % [group_name, binding_id])
		valid = false
	return valid


func _validate_source(value: Variant, group_name: String, binding_id: String) -> bool:
	var valid: bool = _validate_exact_object_fields(value, ["sha256", "byte_size", "mesh_count", "gltf_version"], "source", group_name, binding_id)
	if not (value is Dictionary):
		return false
	var source: Dictionary = value as Dictionary
	var sha256: Variant = source.get("sha256")
	if not _is_sha256(sha256):
		_errors.append("catalog binding %s/%s source sha256 must be 64 lowercase hex characters" % [group_name, binding_id])
		valid = false
	var byte_size: Variant = source.get("byte_size")
	if not _is_nonnegative_integer_value(byte_size):
		_errors.append("catalog binding %s/%s source byte_size must be a nonnegative integer" % [group_name, binding_id])
		valid = false
	var mesh_count: Variant = source.get("mesh_count")
	if not _is_positive_integer_value(mesh_count):
		_errors.append("catalog binding %s/%s source mesh_count must be a positive integer" % [group_name, binding_id])
		valid = false
	if source.get("gltf_version", "") != "2.0":
		_errors.append("catalog binding %s/%s source gltf_version must be 2.0" % [group_name, binding_id])
		valid = false
	return valid


func _validate_bounds(value: Variant, group_name: String, binding_id: String) -> bool:
	var valid: bool = _validate_exact_object_fields(value, ["local_min_m", "local_max_m"], "bounds", group_name, binding_id)
	if not (value is Dictionary):
		return false
	var bounds: Dictionary = value as Dictionary
	var local_min: Variant = bounds.get("local_min_m")
	var local_max: Variant = bounds.get("local_max_m")
	if not _is_finite_vector(local_min) or not _is_finite_vector(local_max):
		_errors.append("catalog binding %s/%s bounds must contain finite 3-vectors" % [group_name, binding_id])
		return false
	var min_values: Array = local_min as Array
	var max_values: Array = local_max as Array
	for index in 3:
		if float(min_values[index]) > float(max_values[index]):
			_errors.append("catalog binding %s/%s bounds local_min_m must not exceed local_max_m" % [group_name, binding_id])
			return false
	return valid


func _validate_provenance(value: Variant, group_name: String, binding_id: String) -> bool:
	var valid: bool = _validate_exact_object_fields(value, ["license_state", "source_platform"], "provenance", group_name, binding_id)
	if not (value is Dictionary):
		return false
	var provenance: Dictionary = value as Dictionary
	for field_name in ["license_state", "source_platform"]:
		if not _is_nonempty_string(provenance.get(field_name)):
			_errors.append("catalog binding %s/%s provenance %s must be a nonempty string" % [group_name, binding_id, field_name])
			valid = false
	return valid


func _validate_exact_object_fields(value: Variant, expected_fields: Array, nested_name: String, group_name: String, binding_id: String) -> bool:
	if not (value is Dictionary):
		_errors.append("catalog binding %s/%s %s must be an object" % [group_name, binding_id, nested_name])
		return false
	var valid: bool = true
	var object_value: Dictionary = value as Dictionary
	for key in object_value.keys():
		if not expected_fields.has(str(key)):
			_errors.append("catalog binding %s/%s %s has unexpected field: %s" % [group_name, binding_id, nested_name, key])
			valid = false
	for field_name in expected_fields:
		if not object_value.has(field_name):
			_errors.append("catalog binding %s/%s %s is missing field: %s" % [group_name, binding_id, nested_name, field_name])
			valid = false
	if object_value.size() != expected_fields.size():
		valid = false
	return valid


func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		return false
	if str(value) == "0".repeat(64):
		return false
	for index in str(value).length():
		var code: int = str(value).unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _is_nonnegative_integer_value(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	var number: float = float(value)
	return number >= 0.0 and is_equal_approx(number, round(number))


func _is_positive_integer_value(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	var number: float = float(value)
	return number >= 1.0 and is_equal_approx(number, round(number))


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


func _is_asset_id(value: Variant) -> bool:
	if not _is_nonempty_string(value):
		return false
	var identifier: String = str(value)
	for index in identifier.length():
		var code: int = identifier.unicode_at(index)
		var is_lowercase_letter: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if index == 0 and not is_lowercase_letter and not is_digit:
			return false
		if not is_lowercase_letter and not is_digit and code != 95 and code != 45:
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
