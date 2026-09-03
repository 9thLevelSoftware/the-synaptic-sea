extends SceneTree

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const GeneratorScript: GDScript = preload("res://scripts/systems/biomass_recipe_generator.gd")

const PARTS_PATH: String = "res://data/combat/biomass_part_catalog.json"
const TEMP_PARTS_PATH: String = "user://biomass_recipe_generator_smoke_parts.json"
const HINTS: Array[String] = ["biped", "quadruped", "crawl", "drag", "slither"]
const CORE_IDS: Array[String] = ["biomass_animal_skull_v1", "biomass_humanoid_torso_v1"]
const PART_IDS: Array[String] = [
	"biomass_animal_skull_v1",
	"biomass_cephalopod_tentacle_v1",
	"biomass_claw_v1",
	"biomass_gunk_connector_v1",
	"biomass_human_arm_v1",
	"biomass_humanoid_torso_v1",
	"biomass_insect_leg_v1",
	"biomass_maw_v1",
]
const PLAN_COUNTS: Dictionary = {
	"biped": {"locomotor": 2, "detail": 1},
	"quadruped": {"locomotor": 4, "detail": 1},
	"crawl": {"locomotor": 3, "detail": 2},
	"drag": {"puller": 1, "detail": 3},
	"slither": {"slither": 2, "detail": 2},
}
const REQUIRED_FIELDS: Array[String] = ["recipe_id", "locomotion_hint", "core", "attachments"]
const CORE_FIELDS: Array[String] = ["instance_id", "part_id"]
const EDGE_FIELDS: Array[String] = [
	"instance_id",
	"part_id",
	"parent_instance_id",
	"parent_socket",
	"child_socket",
	"connector_part_id",
]
const BOUNDARY_SEEDS: Array[int] = [0, 1, 42, 777, -1, 2147483647]
const CAPACITY_LIMITS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 8, 9]

func _initialize() -> void:
	_cleanup_temp_files()
	var parts: Variant = PartCatalogScript.new()
	if not _need(parts.load_path(PARTS_PATH), "canonical part catalog did not load"):
		return
	if not _need(_valid_matrix(parts), "valid generator matrix failed"):
		return
	if not _need(_determinism_checks(parts), "determinism checks failed"):
		return
	if not _need(_boundary_seed_checks(parts), "boundary seed checks failed"):
		return
	if not _need(_capacity_checks(parts), "capacity checks failed"):
		return
	if not _need(_failure_checks(parts), "failure checks failed"):
		return
	if not _need(_diversity_checks(parts), "diversity checks failed"):
		return
	_cleanup_temp_files()
	print("BIOMASS GENERATOR PASS seeds=100 distinct=%d hints=5" % _global_distinct_count(parts))
	quit(0)

func _valid_matrix(parts: Variant) -> bool:
	var observed_cores: Dictionary = {}
	var global_signatures: Dictionary = {}
	var per_hint: Dictionary = {}
	for hint in HINTS:
		per_hint[hint] = {}
	for seed_value in range(1, 101):
		var hint: String = HINTS[(seed_value - 1) % HINTS.size()]
		var recipe: Variant = GeneratorScript.generate(parts, seed_value, hint, 6)
		if not _need(recipe is Object and recipe.get_script() == RecipeScript and recipe.is_valid(), "seed %d %s invalid: %s" % [seed_value, hint, recipe.diagnostics()]):
			return false
		if not _need(_check_valid_recipe(recipe, parts, hint, 6, observed_cores), "seed %d %s document checks failed" % [seed_value, hint]):
			return false
		var document: Dictionary = recipe.to_dict()
		var signature: String = _signature(document)
		global_signatures[signature] = true
		(per_hint[hint] as Dictionary)[signature] = true
	if not _need(global_signatures.size() >= 20, "global diversity was %d" % global_signatures.size()):
		return false
	for hint in HINTS:
		if not _need((per_hint[hint] as Dictionary).size() >= 2, "%s diversity was %d" % [hint, (per_hint[hint] as Dictionary).size()]):
			return false
	if not _need(observed_cores.has(CORE_IDS[0]) and observed_cores.has(CORE_IDS[1]), "both canonical cores were not observed"):
		return false
	return true

func _check_valid_recipe(recipe: Variant, parts: Variant, hint: String, max_attachments: int, observed_cores: Dictionary) -> bool:
	if not _need(recipe.diagnostics().is_empty(), "valid recipe has diagnostics %s" % recipe.diagnostics()):
		return false
	var document: Dictionary = recipe.to_dict()
	if not _need(_exact_keys(document, REQUIRED_FIELDS), "recipe fields are not exact"): return false
	if not _need(document.get("recipe_id") is String and not String(document.get("recipe_id")).is_empty(), "recipe ID is empty"): return false
	if not _need(document.get("locomotion_hint") == hint, "locomotion hint was not echoed"): return false
	var core_value: Variant = document.get("core")
	if not _need(core_value is Dictionary and _exact_keys(core_value, CORE_FIELDS), "core fields are not exact"): return false
	var core: Dictionary = core_value
	var core_id: String = String(core.get("part_id"))
	if not _need(CORE_IDS.has(core_id), "unexpected core %s" % core_id): return false
	observed_cores[core_id] = true
	if not _need(PART_IDS.has(core_id), "unknown core part %s" % core_id): return false
	var attachments_value: Variant = document.get("attachments")
	if not _need(attachments_value is Array, "attachments is not an array"): return false
	var attachments: Array = attachments_value
	var required: Dictionary = PLAN_COUNTS[hint]
	var expected_count: int = 0
	for role in required:
		expected_count += int(required[role])
	if not _need(attachments.size() == expected_count and attachments.size() <= max_attachments, "attachment count mismatch"): return false
	var seen_instances: Dictionary = {String(core.get("instance_id")): true}
	var occupied: Dictionary = {}
	var depths: Dictionary = {String(core.get("instance_id")): 0}
	var generated_max_depth: int = 0
	var role_counts: Dictionary = {}
	var triangle_total: int = 0
	var runtime_nodes: int = 1
	var core_part: Dictionary = parts.get_part(core_id)
	triangle_total += int(core_part.get("triangle_budget", 0))
	runtime_nodes += _part_runtime_nodes(core_part)
	for index in range(attachments.size()):
		var edge_value: Variant = attachments[index]
		if not _need(edge_value is Dictionary and _exact_keys(edge_value, EDGE_FIELDS), "edge %d fields are not exact" % index): return false
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id"))
		var parent_id: String = String(edge.get("parent_instance_id"))
		var child_id: String = String(edge.get("part_id"))
		var parent_socket: String = String(edge.get("parent_socket"))
		if not _need(not instance_id.is_empty() and not seen_instances.has(instance_id), "duplicate/empty instance %s" % instance_id): return false
		if not _need(seen_instances.has(parent_id), "parent-before-child failed for %s" % instance_id): return false
		if not _need(edge.get("child_socket") == "root_0", "child socket was not root_0"): return false
		if not _need(edge.get("connector_part_id") == "biomass_gunk_connector_v1", "connector was not canonical"): return false
		if not _need(PART_IDS.has(child_id) and PART_IDS.has(String(edge.get("connector_part_id"))), "unknown edge part"): return false
		var occupancy_key: String = "%s|%s" % [parent_id, parent_socket]
		if not _need(not occupied.has(occupancy_key), "parent socket reused %s" % occupancy_key): return false
		occupied[occupancy_key] = true
		seen_instances[instance_id] = true
		depths[instance_id] = int(depths[parent_id]) + 1
		if not _need(int(depths[instance_id]) <= int(parts.limits().get("max_depth", 0)), "depth exceeded"): return false
		if int(depths[instance_id]) > generated_max_depth:
			generated_max_depth = int(depths[instance_id])
		var child_part: Dictionary = parts.get_part(child_id)
		var connector_part: Dictionary = parts.get_part(String(edge.get("connector_part_id")))
		triangle_total += int(child_part.get("triangle_budget", 0)) + int(connector_part.get("triangle_budget", 0))
		runtime_nodes += _part_runtime_nodes(child_part) + _part_runtime_nodes(connector_part)
		var roles: Variant = child_part.get("assembly_roles", [])
		if roles is Array:
			for role in roles:
				role_counts[role] = int(role_counts.get(role, 0)) + 1
	var catalog_max_depth: int = int(parts.limits().get("max_depth", 0))
	if not _need(generated_max_depth <= catalog_max_depth, "generated depth exceeded catalog maximum"): return false
	if not _need(generated_max_depth <= 2, "generated depth exceeded smoke depth limit"): return false
	for role in required:
		if not _need(int(role_counts.get(role, 0)) == int(required[role]), "%s count was %d, expected %d" % [role, int(role_counts.get(role, 0)), int(required[role])]): return false
	if not _need(triangle_total <= int(parts.limits().get("max_triangles", 0)), "triangle budget exceeded %d" % triangle_total): return false
	if not _need(runtime_nodes <= int(parts.limits().get("max_nodes", 0)), "node budget exceeded %d" % runtime_nodes): return false
	var defensive: Dictionary = recipe.to_dict()
	var baseline: Dictionary = recipe.to_dict()
	defensive["recipe_id"] = "mutated"
	(defensive["core"] as Dictionary)["part_id"] = "mutated"
	var defensive_attachments_value: Variant = defensive.get("attachments")
	if not _need(defensive_attachments_value is Array and not (defensive_attachments_value as Array).is_empty(), "defensive copy attachments missing or empty"): return false
	var defensive_attachments: Array = defensive_attachments_value
	var first_edge_value: Variant = defensive_attachments[0]
	if not _need(first_edge_value is Dictionary, "defensive copy first attachment is not a dictionary"): return false
	var first_edge: Dictionary = first_edge_value
	if not _need(first_edge.get("part_id") is String and not String(first_edge.get("part_id")).is_empty(), "defensive copy first attachment part_id is invalid"): return false
	first_edge["part_id"] = "mutated"
	defensive_attachments.clear()
	if not _need(recipe.to_dict() == baseline, "valid recipe leaked mutable state"): return false
	return true

func _determinism_checks(parts: Variant) -> bool:
	for hint in HINTS:
		var first: Variant = GeneratorScript.generate(parts, 42, hint, 6)
		var second: Variant = GeneratorScript.generate(parts, 42, hint, 6)
		if not _need(_same_json(first, second), "same seed was not byte deterministic for %s" % hint): return false
		var first_bytes: String = JSON.stringify(first.to_dict(), "", true)
		GeneratorScript.generate(parts, 777, hint, 6)
		var interleaved: Variant = GeneratorScript.generate(parts, 42, hint, 6)
		if not _need(JSON.stringify(interleaved.to_dict(), "", true) == first_bytes, "interleaved seed changed %s" % hint): return false
		if not _need(_same_json(first, interleaved), "repeat after interleave changed %s" % hint): return false
	return true

func _boundary_seed_checks(parts: Variant) -> bool:
	for hint in HINTS:
		var zero: Variant = GeneratorScript.generate(parts, 0, hint, 6)
		var one: Variant = GeneratorScript.generate(parts, 1, hint, 6)
		if not _need(_same_json(zero, one), "seed zero did not equal seed one for %s" % hint): return false
		for seed_value in BOUNDARY_SEEDS:
			var first: Variant = GeneratorScript.generate(parts, seed_value, hint, 6)
			var second: Variant = GeneratorScript.generate(parts, seed_value, hint, 6)
			if not _need(_same_json(first, second), "boundary seed %d was not deterministic for %s" % [seed_value, hint]): return false
			if not _need(first is Object and first.get_script() == RecipeScript and first.is_valid(), "boundary seed %d failed for %s: %s" % [seed_value, hint, first.diagnostics()]): return false
	return true

func _capacity_checks(parts: Variant) -> bool:
	for hint in HINTS:
		var required: Dictionary = PLAN_COUNTS[hint]
		var exact_count: int = 0
		for role in required:
			exact_count += int(required[role])
		for limit in CAPACITY_LIMITS:
			var first: Variant = GeneratorScript.generate(parts, 42, hint, limit)
			var second: Variant = GeneratorScript.generate(parts, 42, hint, limit)
			var should_be_valid: bool = limit >= exact_count and limit <= 8
			if should_be_valid:
				if not _need(first.is_valid(), "capacity %d unexpectedly rejected %s: %s" % [limit, hint, first.diagnostics()]): return false
				if not _need((first.to_dict()["attachments"] as Array).size() == exact_count, "capacity %d padded %s" % [limit, hint]): return false
			else:
				if not _check_stable_failure_pair(first, second, "capacity %d %s" % [limit, hint]): return false
	return true

func _failure_checks(parts: Variant) -> bool:
	for hint in ["", "hover", "BIPED", "biped "]:
		if not _expect_stable_failure(parts, 42, hint, 6, "unsupported hint %s" % hint): return false
	var wrong_dictionary: Variant = {}
	if not _expect_stable_failure(wrong_dictionary, 42, "biped", 6, "dictionary catalog"): return false
	var wrong_null: Variant = null
	if not _expect_stable_failure(wrong_null, 42, "biped", 6, "null catalog"): return false
	var unrelated: Variant = RefCounted.new()
	if not _expect_stable_failure(unrelated, 42, "biped", 6, "unrelated catalog"): return false
	var fresh: Variant = PartCatalogScript.new()
	if not _expect_stable_failure(fresh, 42, "biped", 6, "fresh unloaded catalog"): return false
	var failed_load: Variant = PartCatalogScript.new()
	if not _need(not failed_load.load_path("res://data/combat/biomass_part_catalog_missing.json"), "missing catalog unexpectedly loaded"): return false
	if not _expect_stable_failure(failed_load, 42, "biped", 6, "failed-load catalog"): return false
	for role in ["locomotor", "puller", "slither"]:
		var starved: Variant = PartCatalogScript.new()
		if not _need(starved.load_path(_write_starved_fixture(role)), "role-starved fixture did not load for %s" % role): return false
		if not _expect_stable_failure(starved, 42, "biped" if role == "locomotor" else ("drag" if role == "puller" else "slither"), 6, "role-starved %s" % role): return false
	for mode in ["exhausted_sockets", "triangle_overflow", "node_overflow"]:
		var fixture_path: String = _write_loader_valid_failure_fixture(mode)
		if not _need(not fixture_path.is_empty(), "%s fixture write failed" % mode): return false
		var fixture_parts: Variant = PartCatalogScript.new()
		if not _need(fixture_parts.load_path(fixture_path), "%s fixture did not load" % mode): return false
		if not _expect_stable_failure(fixture_parts, 42, "biped", 6, "loader-valid %s" % mode): return false
		_cleanup_temp_files()
	_cleanup_temp_files()
	return true

func _expect_stable_failure(parts: Variant, seed_value: int, hint: String, max_attachments: int, label: String) -> bool:
	var first: Variant = GeneratorScript.generate(parts, seed_value, hint, max_attachments)
	var second: Variant = GeneratorScript.generate(parts, seed_value, hint, max_attachments)
	return _check_stable_failure_pair(first, second, label)

func _check_stable_failure_pair(first: Variant, second: Variant, label: String) -> bool:
	if not _need(first != null and second != null and first is Object and second is Object, "%s did not return non-null objects" % label): return false
	if not _need(first.get_script() == RecipeScript and second.get_script() == RecipeScript, "%s returned the wrong recipe script" % label): return false
	if not _need(not first.is_valid() and not second.is_valid(), "%s was accepted" % label): return false
	var first_diagnostics: PackedStringArray = first.diagnostics()
	var second_diagnostics: PackedStringArray = second.diagnostics()
	if not _need(not first_diagnostics.is_empty() and first_diagnostics == second_diagnostics, "%s diagnostics were unstable/empty" % label): return false
	var sorted: PackedStringArray = first_diagnostics.duplicate()
	sorted.sort()
	if not _need(first_diagnostics == sorted, "%s diagnostics were not sorted" % label): return false
	var seen: Dictionary = {}
	for diagnostic in first_diagnostics:
		if not _need(not seen.has(diagnostic), "%s diagnostics were not deduplicated" % label): return false
		seen[diagnostic] = true
	var first_document: Dictionary = first.to_dict()
	var second_document: Dictionary = second.to_dict()
	if not _need(first_document == {} and second_document == {}, "%s retained invalid data" % label): return false
	return true

func _diversity_checks(parts: Variant) -> bool:
	var global_signatures: Dictionary = {}
	var per_hint: Dictionary = {}
	for hint in HINTS:
		per_hint[hint] = {}
	for seed_value in range(1, 101):
		var hint: String = HINTS[(seed_value - 1) % HINTS.size()]
		var recipe: Variant = GeneratorScript.generate(parts, seed_value, hint, 6)
		if not _need(recipe.is_valid(), "diversity sample invalid"): return false
		var signature: String = _signature(recipe.to_dict())
		global_signatures[signature] = true
		(per_hint[hint] as Dictionary)[signature] = true
	if not _need(global_signatures.size() >= 20, "global diversity below 20: %d" % global_signatures.size()): return false
	for hint in HINTS:
		if not _need((per_hint[hint] as Dictionary).size() >= 2, "per-hint diversity below 2: %s" % hint): return false
	return true

func _global_distinct_count(parts: Variant) -> int:
	var signatures: Dictionary = {}
	for seed_value in range(1, 101):
		var hint: String = HINTS[(seed_value - 1) % HINTS.size()]
		var recipe: Variant = GeneratorScript.generate(parts, seed_value, hint, 6)
		if recipe is Object and recipe.is_valid():
			signatures[_signature(recipe.to_dict())] = true
	return signatures.size()

func _signature(document: Dictionary) -> String:
	var core: Dictionary = document.get("core", {})
	var topology: Array = []
	var attachments: Array = document.get("attachments", [])
	for edge_value in attachments:
		var edge: Dictionary = edge_value
		topology.append({
			"part_id": edge.get("part_id"),
			"parent_socket": edge.get("parent_socket"),
			"parent_kind": String(edge.get("parent_socket")).split("_")[0],
		})
	return JSON.stringify({
		"hint": document.get("locomotion_hint"),
		"core_part_id": core.get("part_id"),
		"attachments": topology,
		"count": attachments.size(),
	}, "", true)

func _same_json(first: Variant, second: Variant) -> bool:
	if not (first is Object and second is Object):
		return false
	return JSON.stringify(first.to_dict(), "", true) == JSON.stringify(second.to_dict(), "", true)

func _exact_keys(value: Variant, fields: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	var dictionary: Dictionary = value
	if dictionary.size() != fields.size():
		return false
	for field in fields:
		if not dictionary.has(field):
			return false
	for key in dictionary.keys():
		if not fields.has(String(key)):
			return false
	return true

func _part_runtime_nodes(part: Dictionary) -> int:
	var sockets: Variant = part.get("sockets", [])
	var collisions: Variant = part.get("collision_shapes", [])
	var socket_count: int = sockets.size() if sockets is Array else 0
	var collision_count: int = collisions.size() if collisions is Array else 0
	return 2 + socket_count + collision_count

func _write_starved_fixture(role: String) -> String:
	var canonical_text: String = FileAccess.get_file_as_string(PARTS_PATH)
	var parsed: Variant = JSON.parse_string(canonical_text)
	if not _need(parsed is Dictionary, "canonical catalog fixture did not parse for %s" % role): return ""
	var document: Dictionary = parsed
	var normalized_document: Variant = _normalize_integer_values(document)
	if not _need(normalized_document is Dictionary, "catalog fixture normalization failed for %s" % role): return ""
	document = normalized_document
	var parts_value: Variant = document.get("parts")
	if not _need(parts_value is Dictionary, "catalog parts fixture missing for %s" % role): return ""
	var raw_parts: Dictionary = parts_value
	for part_id in raw_parts.keys():
		var part: Dictionary = raw_parts[part_id]
		var roles: Array = (part.get("assembly_roles", []) as Array).duplicate()
		roles.erase(role)
		if roles.is_empty():
			roles.append("detail")
		part["assembly_roles"] = roles
		raw_parts[part_id] = part
	document["parts"] = raw_parts
	var path: String = TEMP_PARTS_PATH
	if not _write_text(path, JSON.stringify(document)):
		return ""
	return path

func _write_loader_valid_failure_fixture(mode: String) -> String:
	var canonical_text: String = FileAccess.get_file_as_string(PARTS_PATH)
	var parsed: Variant = JSON.parse_string(canonical_text)
	if not _need(parsed is Dictionary, "canonical catalog fixture did not parse for %s" % mode): return ""
	var normalized_document: Variant = _normalize_integer_values(parsed)
	if not _need(normalized_document is Dictionary, "catalog fixture normalization failed for %s" % mode): return ""
	var document: Dictionary = normalized_document
	var parts_value: Variant = document.get("parts")
	if not _need(parts_value is Dictionary, "catalog parts fixture missing for %s" % mode): return ""
	var raw_parts: Dictionary = parts_value
	if mode == "exhausted_sockets":
		for core_id in CORE_IDS:
			var core_part: Dictionary = raw_parts.get(core_id, {})
			var canonical_root: Dictionary = {}
			var sockets_value: Variant = core_part.get("sockets", [])
			if sockets_value is Array:
				for socket_value in sockets_value as Array:
					if socket_value is Dictionary and (socket_value as Dictionary).get("name") == "socket_root_0":
						canonical_root = (socket_value as Dictionary).duplicate(true)
						break
			if not _need(not canonical_root.is_empty(), "canonical root socket missing for %s" % core_id): return ""
			core_part["sockets"] = [canonical_root]
			raw_parts[core_id] = core_part
	elif mode == "triangle_overflow":
		for part_id in raw_parts.keys():
			var triangle_part: Dictionary = raw_parts[part_id]
			triangle_part["triangle_budget"] = 30000
			raw_parts[part_id] = triangle_part
	elif mode == "node_overflow":
		for core_id in CORE_IDS:
			var node_part: Dictionary = raw_parts.get(core_id, {})
			var node_sockets_value: Variant = node_part.get("sockets", [])
			if not _need(node_sockets_value is Array, "canonical sockets missing for %s" % core_id): return ""
			var node_sockets: Array = (node_sockets_value as Array).duplicate(true)
			for index in range(100, 260):
				node_sockets.append({
					"name": "socket_appendage_%d" % index,
					"kind": "appendage",
					"accepts_categories": ["biomass_limb", "biomass_appendage"],
					"position_m": [0, 0, 0],
					"rotation_deg": [0, 0, 0],
				})
			node_part["sockets"] = node_sockets
			raw_parts[core_id] = node_part
	else:
		_fail("unknown loader-valid fixture mode %s" % mode)
		return ""
	document["parts"] = raw_parts
	if not _write_text(TEMP_PARTS_PATH, JSON.stringify(document)):
		return ""
	return TEMP_PARTS_PATH

func _normalize_integer_values(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key in (value as Dictionary).keys():
			normalized_dictionary[key] = _normalize_integer_values((value as Dictionary)[key])
		return normalized_dictionary
	if value is Array:
		var normalized_array: Array = []
		for item in value as Array:
			normalized_array.append(_normalize_integer_values(item))
		return normalized_array
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)):
		return int(value)
	return value

func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write temporary fixture %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true

func _need(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false

func _fail(message: String) -> void:
	_cleanup_temp_files()
	print("BIOMASS GENERATOR FAIL: %s" % message)
	quit(1)

func _cleanup_temp_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PARTS_PATH))
