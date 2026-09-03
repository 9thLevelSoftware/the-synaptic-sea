extends RefCounted
class_name BiomassRecipe

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const SUPPORTED_LOCOMOTION: Array[String] = ["biped", "quadruped", "crawl", "drag", "slither"]
const CONNECTOR_PART_ID: String = "biomass_gunk_connector_v1"
const RECIPE_FIELDS: Array[String] = ["recipe_id", "locomotion_hint", "core", "attachments"]
const CORE_FIELDS: Array[String] = ["instance_id", "part_id"]
const EDGE_FIELDS: Array[String] = [
	"instance_id",
	"part_id",
	"parent_instance_id",
	"parent_socket",
	"child_socket",
	"connector_part_id",
]

var _valid: bool = false
var _diagnostics: PackedStringArray = PackedStringArray()
var _document: Dictionary = {}

static func from_dict(document: Dictionary, catalog: Variant) -> BiomassRecipe:
	var recipe: BiomassRecipe = load("res://scripts/systems/biomass_recipe.gd").new()
	var errors: Array[String] = []
	if not _has_exact_fields(document, RECIPE_FIELDS, "recipe", errors):
		recipe._set_invalid(errors)
		return recipe
	if not catalog is Object or catalog.get_script() != PartCatalogScript:
		errors.append("part_catalog: catalog is required")
		recipe._set_invalid(errors)
		return recipe

	var recipe_id: String = ""
	var recipe_id_value: Variant = document.get("recipe_id")
	if not _nonempty_string(recipe_id_value):
		errors.append("recipe.recipe_id: must be a non-empty string")
	else:
		recipe_id = recipe_id_value
	var hint: String = ""
	var hint_value: Variant = document.get("locomotion_hint")
	if not _nonempty_string(hint_value) or not SUPPORTED_LOCOMOTION.has(hint_value):
		errors.append("recipe.locomotion_hint: unsupported locomotion")
	else:
		hint = hint_value

	var occurrences: Array[Dictionary] = []
	var seen_instances: Dictionary = {}
	var depths: Dictionary = {}
	var parent_of: Dictionary = {}
	var occupied: Dictionary = {}

	var core_value: Variant = document.get("core")
	var core_instance_id: String = ""
	var core_part_id: String = ""
	if _has_exact_fields(core_value, CORE_FIELDS, "recipe.core", errors):
		var core: Dictionary = core_value
		var core_instance_value: Variant = core.get("instance_id")
		if not _nonempty_string(core_instance_value):
			errors.append("recipe.core.instance_id: must be a non-empty string")
		else:
			core_instance_id = core_instance_value
		var core_part_value: Variant = core.get("part_id")
		if not _nonempty_string(core_part_value):
			errors.append("recipe.core.part_id: must be a non-empty string")
		else:
			core_part_id = core_part_value
		var core_part: Dictionary = catalog.get_part(core_part_id)
		if core_part.is_empty():
			errors.append("recipe.core.part_id: unknown part_id '%s'" % core_part_id)
		else:
			if not _has_role(core_part, "core"):
				errors.append("recipe.core.part_id: core part lacks core role")
			else:
				occurrences.append(core_part)
		if not core_instance_id.is_empty():
			seen_instances[core_instance_id] = core_part_id
			depths[core_instance_id] = 0

	var attachments_value: Variant = document.get("attachments")
	if not attachments_value is Array:
		errors.append("recipe.attachments: must be an array")
	else:
		var attachments: Array = attachments_value
		var limits: Dictionary = catalog.limits()
		var max_attachments: int = int(limits.get("max_attachments", 0))
		if attachments.size() > max_attachments:
			errors.append("recipe.attachments: max attachments exceeded (%d > %d)" % [attachments.size(), max_attachments])
		for index in range(attachments.size()):
			var edge_value: Variant = attachments[index]
			var path: String = "recipe.attachments[%d]" % index
			if not _has_exact_fields(edge_value, EDGE_FIELDS, path, errors):
				continue
			var edge: Dictionary = edge_value
			var instance_value: Variant = edge.get("instance_id")
			var parent_value: Variant = edge.get("parent_instance_id")
			var child_part_value: Variant = edge.get("part_id")
			var parent_socket_value: Variant = edge.get("parent_socket")
			var child_socket_value: Variant = edge.get("child_socket")
			var connector_value: Variant = edge.get("connector_part_id")

			var instance_id: String = ""
			if not _nonempty_string(instance_value):
				errors.append("%s.instance_id: must be a non-empty string" % path)
			else:
				instance_id = instance_value
				if seen_instances.has(instance_id):
					errors.append("%s.instance_id: duplicate instance_id '%s'" % [path, instance_id])

			var parent_id: String = ""
			if not _nonempty_string(parent_value):
				errors.append("%s.parent_instance_id: must be a non-empty string" % path)
			else:
				parent_id = parent_value

			var child_part_id: String = ""
			var child_part: Dictionary = {}
			if not _nonempty_string(child_part_value):
				errors.append("%s.part_id: must be a non-empty string" % path)
			else:
				child_part_id = child_part_value
				child_part = catalog.get_part(child_part_id)
				if child_part.is_empty():
					errors.append("%s.part_id: unknown part_id '%s'" % [path, child_part_id])

			var connector_part: Dictionary = {}
			if connector_value != CONNECTOR_PART_ID:
				errors.append("%s.connector_part_id: connector must be %s" % [path, CONNECTOR_PART_ID])
			if connector_value is String:
				connector_part = catalog.get_part(connector_value)
			if connector_part.is_empty():
				errors.append("%s.connector_part_id: unknown connector part" % path)
			elif connector_part.get("category") != "biomass_connector" or not _has_role(connector_part, "connector"):
				errors.append("%s.connector_part_id: connector lacks connector role/category" % path)

			var parent_is_seen: bool = not parent_id.is_empty() and seen_instances.has(parent_id)
			if not parent_is_seen:
				errors.append("%s.parent_instance_id: parent-before-child reference required" % path)
			else:
				var parent_part_id: String = seen_instances[parent_id]
				var parent_socket: Dictionary = {}
				if not _valid_short_socket(parent_socket_value):
					errors.append("%s.parent_socket: invalid socket reference" % path)
				else:
					parent_socket = catalog.socket(parent_part_id, parent_socket_value)
					if parent_socket.is_empty():
						errors.append("%s.parent_socket: unknown parent socket" % path)
					else:
						var accepts: Variant = parent_socket.get("accepts_categories")
						var child_category: Variant = child_part.get("category", "")
						if accepts is Array and not (accepts as Array).has(child_category):
							errors.append("%s.parent_socket: child category is not accepted" % path)
						var occupancy_key: String = "%s|%s" % [parent_id, parent_socket_value]
						if occupied.has(occupancy_key):
							errors.append("%s.parent_socket: socket occupancy is already used" % path)
						occupied[occupancy_key] = true

			if child_socket_value != "root_0":
				errors.append("%s.child_socket: child socket must be root_0" % path)
			elif not child_part.is_empty() and catalog.socket(child_part_id, "root_0").is_empty():
				errors.append("%s.child_socket: child part is missing root socket" % path)

			if parent_is_seen and not instance_id.is_empty() and not seen_instances.has(instance_id):
				seen_instances[instance_id] = child_part_id
				var child_depth: int = int(depths.get(parent_id, int(limits.get("max_depth", 0)) + 1)) + 1
				depths[instance_id] = child_depth
				if not child_part.is_empty():
					occurrences.append(child_part)
				if not connector_part.is_empty():
					occurrences.append(connector_part)
				if not parent_id.is_empty():
					parent_of[instance_id] = parent_id

	var max_depth: int = int(catalog.limits().get("max_depth", 0))
	for instance_id in depths:
		if int(depths[instance_id]) > max_depth:
			errors.append("recipe: max depth exceeded at %s (%d > %d)" % [instance_id, int(depths[instance_id]), max_depth])
	for start in parent_of:
		var visited: Dictionary = {}
		var current: String = start
		while parent_of.has(current):
			if visited.has(current):
				errors.append("recipe: cycle detected at instance_id '%s'" % current)
				break
			visited[current] = true
			current = parent_of[current]

	var triangle_total: int = 0
	var runtime_nodes: int = 1
	var role_counts: Dictionary = {}
	var head_count: int = 0
	for part in occurrences:
		triangle_total += int(part.get("triangle_budget", 0))
		runtime_nodes += 2
		var sockets: Variant = part.get("sockets", [])
		var collision_shapes: Variant = part.get("collision_shapes", [])
		if sockets is Array:
			runtime_nodes += (sockets as Array).size()
		if collision_shapes is Array:
			runtime_nodes += (collision_shapes as Array).size()
		var roles: Variant = part.get("assembly_roles", [])
		if roles is Array:
			for role in roles:
				role_counts[role] = int(role_counts.get(role, 0)) + 1
		if part.get("category") == "biomass_head":
			head_count += 1
	var recipe_limits: Dictionary = catalog.limits()
	var max_triangles: int = int(recipe_limits.get("max_triangles", 0))
	if triangle_total > max_triangles:
		errors.append("recipe: triangle limit exceeded (%d > %d)" % [triangle_total, max_triangles])
	var max_nodes: int = int(recipe_limits.get("max_nodes", 0))
	if runtime_nodes > max_nodes:
		errors.append("recipe: runtime node limit exceeded (%d > %d)" % [runtime_nodes, max_nodes])
	_validate_locomotion(hint, role_counts, head_count, errors)

	if errors.is_empty():
		recipe._set_valid(document.duplicate(true))
	else:
		recipe._set_invalid(errors)
	return recipe

func is_valid() -> bool:
	return _valid

func diagnostics() -> PackedStringArray:
	return _diagnostics.duplicate()

func to_dict() -> Dictionary:
	if not _valid:
		return {}
	return _document.duplicate(true)

func _set_valid(document: Dictionary) -> void:
	_valid = true
	_diagnostics = PackedStringArray()
	_document = document.duplicate(true)

func _set_invalid(errors: Array[String]) -> void:
	_valid = false
	_document.clear()
	_diagnostics = _stable_diagnostics(errors)

static func _has_exact_fields(value: Variant, fields: Array[String], path: String, errors: Array[String]) -> bool:
	if not value is Dictionary:
		errors.append("%s: must be an object" % path)
		return false
	var record: Dictionary = value
	var valid: bool = record.size() == fields.size()
	for key in record.keys():
		if not fields.has(key):
			errors.append("%s: unknown field '%s'" % [path, String(key)])
			valid = false
	for field in fields:
		if not record.has(field):
			errors.append("%s: missing field '%s'" % [path, field])
			valid = false
	return valid

static func _nonempty_string(value: Variant) -> bool:
	return value is String and not String(value).is_empty()

static func _has_role(part: Dictionary, role: String) -> bool:
	var roles: Variant = part.get("assembly_roles", [])
	return roles is Array and (roles as Array).has(role)

static func _valid_short_socket(value: Variant) -> bool:
	if not value is String:
		return false
	var pieces: Array = String(value).split("_")
	if pieces.size() != 2 or not ["root", "head", "limb", "appendage", "jaw", "distal"].has(pieces[0]):
		return false
	return _digits_only(pieces[1])

static func _digits_only(value: String) -> bool:
	if value.is_empty():
		return false
	const digits: String = "0123456789"
	for character in value:
		if digits.find(character) < 0:
			return false
	return true

static func _validate_locomotion(hint: String, role_counts: Dictionary, head_count: int, errors: Array[String]) -> void:
	if not SUPPORTED_LOCOMOTION.has(hint):
		return
	if hint == "biped":
		if int(role_counts.get("locomotor", 0)) != 2:
			errors.append("locomotion_hint: biped requires exactly 2 locomotor parts")
		if head_count < 1:
			errors.append("locomotion_hint: biped requires a head")
	elif hint == "quadruped":
		if int(role_counts.get("locomotor", 0)) != 4:
			errors.append("locomotion_hint: quadruped requires exactly 4 locomotor parts")
		if head_count < 1:
			errors.append("locomotion_hint: quadruped requires a head")
	elif hint == "crawl" and int(role_counts.get("locomotor", 0)) < 1:
		errors.append("locomotion_hint: crawl requires a locomotor part")
	elif hint == "drag" and int(role_counts.get("puller", 0)) < 1:
		errors.append("locomotion_hint: drag requires a puller part")
	elif hint == "slither" and int(role_counts.get("slither", 0)) < 1:
		errors.append("locomotion_hint: slither requires a slither part")

static func _stable_diagnostics(errors: Array[String]) -> PackedStringArray:
	var unique: Dictionary = {}
	for error in errors:
		unique[error] = true
	var ordered: Array = unique.keys()
	ordered.sort()
	var result: PackedStringArray = PackedStringArray()
	for error in ordered:
		result.append(String(error))
	return result
