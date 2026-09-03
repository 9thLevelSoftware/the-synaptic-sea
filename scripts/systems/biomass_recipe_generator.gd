extends RefCounted
class_name BiomassRecipeGenerator

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")

const PLAN_COUNTS := {
	"biped": {"locomotor": 2, "detail": 1},
	"quadruped": {"locomotor": 4, "detail": 1},
	"crawl": {"locomotor": 3, "detail": 2},
	"drag": {"puller": 1, "detail": 3},
	"slither": {"slither": 2, "detail": 2},
}
const TORSO_PART_ID: String = "biomass_humanoid_torso_v1"
const SKULL_PART_ID: String = "biomass_animal_skull_v1"
const CONNECTOR_PART_ID: String = "biomass_gunk_connector_v1"

static func generate(parts: Variant, seed_value: int, locomotion_hint: String, max_attachments: int = 6) -> Variant:
	if not parts is Object or parts.get_script() != PartCatalogScript:
		return _invalid(parts)
	if not PLAN_COUNTS.has(locomotion_hint):
		return _invalid(parts)
	var limits_value: Variant = parts.limits()
	if not limits_value is Dictionary:
		return _invalid(parts)
	var limits: Dictionary = limits_value
	var catalog_max_value: Variant = limits.get("max_attachments", 0)
	if not _is_integer_value(catalog_max_value):
		return _invalid(parts)
	var required_attachments: int = _plan_attachment_count(locomotion_hint)
	if max_attachments <= 0 or max_attachments > int(catalog_max_value) or max_attachments < required_attachments:
		return _invalid(parts)

	var effective_seed: int = seed_value if seed_value != 0 else 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = effective_seed

	var core_candidates: PackedStringArray = _role_candidates(parts, "core")
	if core_candidates.is_empty():
		return _invalid(parts)
	var core_part_id: String = _pick(core_candidates, rng)
	if core_part_id.is_empty():
		return _invalid(parts)
	var core_instance_id: String = "core_%d" % effective_seed
	var occupied: Dictionary = {}
	var attachments: Array = []
	var emitted_limbs: Array = []

	var locomotion_role: String = _locomotion_role(locomotion_hint)
	var locomotion_count: int = int((PLAN_COUNTS[locomotion_hint] as Dictionary).get(locomotion_role, 0))
	for occurrence in range(locomotion_count):
		var locomotor_candidates: PackedStringArray = _role_candidates(parts, locomotion_role)
		if locomotor_candidates.is_empty():
			return _invalid(parts)
		var locomotor_part_id: String = _pick(locomotor_candidates, rng)
		var locomotor_sockets: PackedStringArray = _compatible_core_sockets(parts, core_part_id, locomotor_part_id, occupied, [], core_instance_id)
		if locomotor_sockets.is_empty():
			return _invalid(parts)
		var locomotor_socket: String = _pick(locomotor_sockets, rng)
		if not _append_edge(attachments, emitted_limbs, occupied, "locomotor", occurrence, effective_seed, locomotor_part_id, core_instance_id, locomotor_socket, parts):
			return _invalid(parts)

	var detail_count: int = int((PLAN_COUNTS[locomotion_hint] as Dictionary).get("detail", 0))
	for occurrence in range(detail_count):
		var detail_part_id: String = ""
		var detail_parent_id: String = ""
		var detail_parent_socket: String = ""
		var forced_torso_head: bool = core_part_id == TORSO_PART_ID and (locomotion_hint == "biped" or locomotion_hint == "quadruped") and occurrence == 0
		if forced_torso_head:
			detail_part_id = SKULL_PART_ID
			var head_sockets: PackedStringArray = _compatible_core_sockets(parts, core_part_id, detail_part_id, occupied, ["head", "appendage"], core_instance_id)
			if head_sockets.is_empty():
				return _invalid(parts)
			detail_parent_socket = _pick(head_sockets, rng)
			detail_parent_id = core_instance_id
		else:
			var detail_candidates: PackedStringArray = _role_candidates(parts, "detail")
			if detail_candidates.is_empty():
				return _invalid(parts)
			var distal_candidates: PackedStringArray = _detail_candidates_with_distal(parts, detail_candidates, emitted_limbs, occupied)
			if not distal_candidates.is_empty():
				detail_part_id = _pick(distal_candidates, rng)
				var distal_options: PackedStringArray = _distal_parent_options(parts, detail_part_id, emitted_limbs, occupied)
				if distal_options.is_empty():
					return _invalid(parts)
				var distal_option: String = _pick(distal_options, rng)
				var option_parts: PackedStringArray = distal_option.split("|")
				if option_parts.size() != 2:
					return _invalid(parts)
				detail_parent_id = option_parts[0]
				detail_parent_socket = option_parts[1]
			else:
				var core_detail_candidates: PackedStringArray = _detail_candidates_with_core_socket(parts, detail_candidates, core_part_id, occupied, core_instance_id)
				if core_detail_candidates.is_empty():
					return _invalid(parts)
				detail_part_id = _pick(core_detail_candidates, rng)
				var core_detail_sockets: PackedStringArray = _compatible_core_sockets(parts, core_part_id, detail_part_id, occupied, [], core_instance_id)
				if core_detail_sockets.is_empty():
					return _invalid(parts)
				detail_parent_id = core_instance_id
				detail_parent_socket = _pick(core_detail_sockets, rng)
		if not _append_edge(attachments, emitted_limbs, occupied, "detail", occurrence, effective_seed, detail_part_id, detail_parent_id, detail_parent_socket, parts):
			return _invalid(parts)

	var document: Dictionary = {
		"recipe_id": "biomass_%s_%d_%s" % [locomotion_hint, effective_seed, core_part_id],
		"locomotion_hint": locomotion_hint,
		"core": {"instance_id": core_instance_id, "part_id": core_part_id},
		"attachments": attachments,
	}
	return RecipeScript.from_dict(document, parts)

static func _pick(sorted_ids: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if sorted_ids.is_empty():
		return ""
	return sorted_ids[rng.randi_range(0, sorted_ids.size() - 1)]

static func _invalid(parts: Variant) -> Variant:
	return RecipeScript.from_dict({}, parts)

static func _is_integer_value(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number)

static func _plan_attachment_count(locomotion_hint: String) -> int:
	var plan: Dictionary = PLAN_COUNTS[locomotion_hint]
	var total: int = 0
	for role in plan:
		total += int(plan[role])
	return total

static func _locomotion_role(locomotion_hint: String) -> String:
	if locomotion_hint == "drag":
		return "puller"
	if locomotion_hint == "slither":
		return "slither"
	return "locomotor"

static func _role_candidates(parts: Variant, role: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var role_ids: PackedStringArray = parts.find_by_role(role)
	var sorted_ids: PackedStringArray = role_ids.duplicate()
	sorted_ids.sort()
	for part_id in sorted_ids:
		var entry: Dictionary = parts.get_part(part_id)
		if entry.is_empty() or parts.socket(part_id, "root_0").is_empty():
			continue
		result.append(part_id)
	return result

static func _compatible_core_sockets(parts: Variant, core_part_id: String, child_part_id: String, occupied: Dictionary, allowed_kinds: Array = [], core_instance_id: String = "") -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var child: Dictionary = parts.get_part(child_part_id)
	var child_category: String = String(child.get("category", ""))
	var core: Dictionary = parts.get_part(core_part_id)
	var sockets_value: Variant = core.get("sockets", [])
	if not sockets_value is Array:
		return result
	for socket_value in sockets_value:
		if not socket_value is Dictionary:
			continue
		var socket: Dictionary = socket_value
		var socket_name: String = String(socket.get("name", ""))
		var kind: String = String(socket.get("kind", ""))
		if kind == "root" or (not allowed_kinds.is_empty() and not allowed_kinds.has(kind)):
			continue
		var accepts: Variant = socket.get("accepts_categories", [])
		if not accepts is Array or not (accepts as Array).has(child_category):
			continue
		var short_name: String = _short_socket(socket_name)
		if short_name.is_empty():
			continue
		if not core_instance_id.is_empty() and occupied.has("%s|%s" % [core_instance_id, short_name]):
			continue
		result.append(short_name)
	result.sort()
	return result

static func _append_edge(attachments: Array, emitted_limbs: Array, occupied: Dictionary, role: String, occurrence: int, effective_seed: int, part_id: String, parent_id: String, parent_socket: String, parts: Variant) -> bool:
	if part_id.is_empty() or parent_id.is_empty() or parent_socket.is_empty():
		return false
	var occupancy_key: String = "%s|%s" % [parent_id, parent_socket]
	if occupied.has(occupancy_key):
		return false
	if parts.socket(part_id, "root_0").is_empty():
		return false
	var instance_id: String = "%s_%d_%d" % [role, effective_seed, occurrence]
	for edge_value in attachments:
		if edge_value is Dictionary and String((edge_value as Dictionary).get("instance_id", "")) == instance_id:
			return false
	attachments.append({
		"instance_id": instance_id,
		"part_id": part_id,
		"parent_instance_id": parent_id,
		"parent_socket": parent_socket,
		"child_socket": "root_0",
		"connector_part_id": CONNECTOR_PART_ID,
	})
	occupied[occupancy_key] = true
	var part: Dictionary = parts.get_part(part_id)
	if part.get("category") == "biomass_limb":
		emitted_limbs.append({"instance_id": instance_id, "part_id": part_id})
	return true

static func _detail_candidates_with_distal(parts: Variant, detail_candidates: PackedStringArray, emitted_limbs: Array, occupied: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for detail_part_id in detail_candidates:
		if not _distal_parent_options(parts, detail_part_id, emitted_limbs, occupied).is_empty():
			result.append(detail_part_id)
	result.sort()
	return result

static func _distal_parent_options(parts: Variant, child_part_id: String, emitted_limbs: Array, occupied: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var child: Dictionary = parts.get_part(child_part_id)
	var child_category: String = String(child.get("category", ""))
	for limb_value in emitted_limbs:
		if not limb_value is Dictionary:
			continue
		var limb: Dictionary = limb_value
		var parent_id: String = String(limb.get("instance_id", ""))
		var parent_part_id: String = String(limb.get("part_id", ""))
		var socket_names: PackedStringArray = _socket_names(parts, parent_part_id, "distal")
		for socket_name in socket_names:
			var occupancy_key: String = "%s|%s" % [parent_id, socket_name]
			if occupied.has(occupancy_key):
				continue
			var socket: Dictionary = parts.socket(parent_part_id, socket_name)
			var accepts: Variant = socket.get("accepts_categories", [])
			if accepts is Array and (accepts as Array).has(child_category):
				result.append("%s|%s" % [parent_id, socket_name])
	result.sort()
	return result

static func _detail_candidates_with_core_socket(parts: Variant, detail_candidates: PackedStringArray, core_part_id: String, occupied: Dictionary, core_instance_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for detail_part_id in detail_candidates:
		if not _compatible_core_sockets(parts, core_part_id, detail_part_id, occupied, [], core_instance_id).is_empty():
			result.append(detail_part_id)
	result.sort()
	return result

static func _socket_names(parts: Variant, part_id: String, kind: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var part: Dictionary = parts.get_part(part_id)
	var sockets_value: Variant = part.get("sockets", [])
	if not sockets_value is Array:
		return result
	for socket_value in sockets_value:
		if socket_value is Dictionary and String((socket_value as Dictionary).get("kind", "")) == kind:
			result.append(_short_socket(String((socket_value as Dictionary).get("name", ""))))
	result.sort()
	return result

static func _short_socket(socket_name: String) -> String:
	if socket_name.begins_with("socket_"):
		return socket_name.substr(7)
	return socket_name
