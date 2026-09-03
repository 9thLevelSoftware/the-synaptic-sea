extends RefCounted
class_name BiomassPartCatalog

const CANONICAL_PART_IDS: Array[String] = [
	"biomass_animal_skull_v1",
	"biomass_cephalopod_tentacle_v1",
	"biomass_claw_v1",
	"biomass_gunk_connector_v1",
	"biomass_human_arm_v1",
	"biomass_humanoid_torso_v1",
	"biomass_insect_leg_v1",
	"biomass_maw_v1",
]
const CATEGORIES: Array[String] = [
	"biomass_core",
	"biomass_limb",
	"biomass_head",
	"biomass_connector",
	"biomass_appendage",
]
const ASSEMBLY_ROLES: Array[String] = [
	"core",
	"locomotor",
	"manipulator",
	"detail",
	"puller",
	"slither",
	"connector",
]
const SOCKET_KINDS: Array[String] = ["root", "head", "limb", "appendage", "jaw", "distal"]
const SHAPE_KINDS: Array[String] = ["box", "capsule", "sphere"]
const LIMITS: Dictionary = {
	"max_attachments": 8,
	"max_depth": 3,
	"max_triangles": 30000,
	"max_nodes": 160,
}
const PART_FIELDS: Array[String] = [
	"category",
	"species_tags",
	"assembly_roles",
	"wrapper_scene_path",
	"triangle_budget",
	"sockets",
	"collision_shapes",
	"fallback",
]
const SOCKET_FIELDS: Array[String] = ["name", "kind", "accepts_categories", "position_m", "rotation_deg"]
const FALLBACK_FIELDS: Array[String] = ["primitive", "dimensions_m", "albedo"]
const COLLISION_BASE_FIELDS: Array[String] = ["shape", "position_m", "rotation_deg"]

var _parts: Dictionary = {}
var _limits: Dictionary = {}

func load_path(path: String) -> bool:
	_parts.clear()
	_limits.clear()
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return false
	var document: Dictionary = parsed
	if not _has_exact_fields(document, ["schema_version", "document_kind", "limits", "parts"]):
		return false
	if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "biomass_part_catalog":
		return false
	var limits_value: Variant = document.get("limits")
	if not limits_value is Dictionary:
		return false
	var limits: Dictionary = limits_value
	if not _has_exact_fields(limits, ["max_attachments", "max_depth", "max_triangles", "max_nodes"]):
		return false
	for limit_name in LIMITS:
		var actual_limit: Variant = limits.get(limit_name)
		if not _valid_positive_bounded_integer(actual_limit, int(LIMITS[limit_name])) or int(actual_limit) != int(LIMITS[limit_name]):
			return false
	var parts_value: Variant = document.get("parts")
	if not parts_value is Dictionary:
		return false
	var parts: Dictionary = parts_value
	if not _has_exact_keys(parts, CANONICAL_PART_IDS):
		return false
	for part_id in CANONICAL_PART_IDS:
		var part_value: Variant = parts.get(part_id)
		if not _valid_part(part_value):
			return false
	_parts = parts.duplicate(true)
	_limits = limits.duplicate(true)
	return true

func get_part(part_id: String) -> Dictionary:
	var value: Variant = _parts.get(part_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func find_by_role(role: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var ids: Array = _parts.keys()
	ids.sort()
	for part_id in ids:
		var part: Variant = _parts.get(part_id)
		if part is Dictionary and role in (part as Dictionary).get("assembly_roles", []):
			result.append(String(part_id))
	return result

func socket(part_id: String, socket_name: String) -> Dictionary:
	var part: Variant = _parts.get(part_id)
	if not part is Dictionary:
		return {}
	var catalog_name: String = socket_name if socket_name.begins_with("socket_") else "socket_" + socket_name
	var sockets: Variant = (part as Dictionary).get("sockets")
	if not sockets is Array:
		return {}
	for item in sockets:
		if item is Dictionary and (item as Dictionary).get("name") == catalog_name:
			return (item as Dictionary).duplicate(true)
	return {}

func limits() -> Dictionary:
	return _limits.duplicate(true)

func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	for key in value.keys():
		if not fields.has(key):
			return false
	return true

func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	for actual_key in value.keys():
		if not keys.has(actual_key):
			return false
	return true

func _valid_part(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var part: Dictionary = value
	if not _has_exact_fields(part, PART_FIELDS):
		return false
	var category: Variant = part.get("category")
	if not category is String or not CATEGORIES.has(category):
		return false
	if not _valid_string_array(part.get("species_tags"), true):
		return false
	if not _valid_roles(part.get("assembly_roles")):
		return false
	var budget: Variant = part.get("triangle_budget")
	if not _valid_positive_bounded_integer(budget, int(LIMITS["max_triangles"])):
		return false
	if not _valid_wrapper_path(part.get("wrapper_scene_path")):
		return false
	var fallback_value: Variant = part.get("fallback")
	if not fallback_value is Dictionary:
		return false
	var fallback: Dictionary = fallback_value
	if not _has_exact_fields(fallback, FALLBACK_FIELDS):
		return false
	if not fallback.get("primitive") is String or not SHAPE_KINDS.has(fallback.get("primitive")):
		return false
	if not _valid_vector(fallback.get("dimensions_m"), true):
		return false
	if not _valid_albedo(fallback.get("albedo")):
		return false
	var sockets_value: Variant = part.get("sockets")
	if not sockets_value is Array or (sockets_value as Array).is_empty():
		return false
	var socket_names: Dictionary = {}
	var fallback_dimensions: Array = fallback.get("dimensions_m")
	for item in sockets_value:
		if not item is Dictionary:
			return false
		var item_dict: Dictionary = item
		if not _has_exact_fields(item_dict, SOCKET_FIELDS):
			return false
		var name_value: Variant = item_dict.get("name")
		if not name_value is String or not _valid_full_socket_name(name_value):
			return false
		var name: String = name_value
		if socket_names.has(name):
			return false
		socket_names[name] = true
		var kind: Variant = item_dict.get("kind")
		if not kind is String or not SOCKET_KINDS.has(kind) or name.split("_")[1] != kind:
			return false
		var accepted: Variant = item_dict.get("accepts_categories")
		if not _valid_string_array(accepted, kind != "root"):
			return false
		for accepted_category in accepted:
			if not CATEGORIES.has(accepted_category):
				return false
		if kind == "root" and not (accepted as Array).is_empty():
			return false
		if not _valid_vector(item_dict.get("position_m"), false) or not _valid_vector(item_dict.get("rotation_deg"), false):
			return false
		var position: Array = item_dict.get("position_m")
		for index in range(3):
			if abs(float(position[index])) > float(fallback_dimensions[index]) + 0.05:
				return false
	if not socket_names.has("socket_root_0"):
		return false
	var collisions_value: Variant = part.get("collision_shapes")
	if not collisions_value is Array or (collisions_value as Array).is_empty():
		return false
	for item in collisions_value:
		if not _valid_collision(item):
			return false
	return true

func _valid_roles(value: Variant) -> bool:
	if not _valid_string_array(value, true):
		return false
	for role in value:
		if not ASSEMBLY_ROLES.has(role):
			return false
	return true

func _valid_string_array(value: Variant, require_nonempty: bool) -> bool:
	if not value is Array:
		return false
	var values: Array = value
	if require_nonempty and values.is_empty():
		return false
	var seen: Dictionary = {}
	for item in values:
		if not item is String or String(item).is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true

func _valid_wrapper_path(value: Variant) -> bool:
	if not value is String:
		return false
	var path: String = value
	if path.is_empty():
		return true
	if not path.begins_with("res://"):
		return false
	var relative: String = path.substr(6)
	if relative.is_empty():
		return false
	for segment in relative.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return FileAccess.file_exists(path)

func _valid_full_socket_name(value: String) -> bool:
	if not value.begins_with("socket_"):
		return false
	var pieces: Array = value.split("_")
	if pieces.size() != 3 or not SOCKET_KINDS.has(pieces[1]):
		return false
	return not pieces[2].is_empty() and _digits_only(pieces[2])

func _digits_only(value: String) -> bool:
	if value.is_empty():
		return false
	const digits: String = "0123456789"
	for character in value:
		if digits.find(character) < 0:
			return false
	return true

func _valid_vector(value: Variant, positive: bool) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for item in value:
		if (typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT) or not is_finite(float(item)):
			return false
		if positive and float(item) <= 0.0:
			return false
	return true

func _valid_positive_bounded_integer(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number > 0.0 and number <= float(maximum) and number == floor(number)

func _valid_albedo(value: Variant) -> bool:
	if not value is String or value.length() != 7 or not value.begins_with("#"):
		return false
	const digits: String = "0123456789abcdefABCDEF"
	for index in range(1, 7):
		if digits.find(value.substr(index, 1)) < 0:
			return false
	return true

func _valid_collision(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var shape: Dictionary = value
	var shape_kind: Variant = shape.get("shape")
	if not shape_kind is String or not SHAPE_KINDS.has(shape_kind):
		return false
	var fields: Array[String] = COLLISION_BASE_FIELDS.duplicate()
	if shape_kind == "box":
		fields.append("dimensions_m")
	elif shape_kind == "capsule":
		fields.append("radius_m")
		fields.append("height_m")
	else:
		fields.append("radius_m")
	if not _has_exact_fields(shape, fields):
		return false
	if not _valid_vector(shape.get("position_m"), false) or not _valid_vector(shape.get("rotation_deg"), false):
		return false
	if shape_kind == "box":
		return _valid_vector(shape.get("dimensions_m"), true)
	var radius: Variant = shape.get("radius_m")
	if typeof(radius) != TYPE_INT and typeof(radius) != TYPE_FLOAT:
		return false
	if not is_finite(float(radius)) or float(radius) <= 0.0:
		return false
	if shape_kind == "capsule":
		var height: Variant = shape.get("height_m")
		if (typeof(height) != TYPE_INT and typeof(height) != TYPE_FLOAT) or not is_finite(float(height)) or float(height) <= 0.0:
			return false
	return true
