extends SceneTree

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const RecipeLibraryScript: GDScript = preload("res://scripts/systems/biomass_recipe_library.gd")

const PARTS_PATH: String = "res://data/combat/biomass_part_catalog.json"
const RECIPES_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const TEMP_PARTS_PATH: String = "user://biomass_catalog_smoke_parts.json"
const TEMP_RECIPES_PATH: String = "user://biomass_catalog_smoke_recipes.json"

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
const RECIPE_IDS: Array[String] = [
	"biped_puppet_v1",
	"four_legged_scrambler_v1",
	"intestinal_dragger_v1",
	"tendril_knot_v1",
	"tripod_hound_v1",
]
const ARCHETYPE_IDS: Array[String] = [
	"biomatter_swarm",
	"drone_swarm",
	"hull_tendril",
	"mimic",
	"puppet_corpse",
	"stalker",
]
const EXPECTED_POOLS: Dictionary = {
	"biomatter_swarm": ["intestinal_dragger_v1", "tripod_hound_v1"],
	"drone_swarm": ["tendril_knot_v1", "tripod_hound_v1"],
	"hull_tendril": ["intestinal_dragger_v1", "tendril_knot_v1"],
	"mimic": ["four_legged_scrambler_v1", "tripod_hound_v1"],
	"puppet_corpse": ["biped_puppet_v1", "tripod_hound_v1"],
	"stalker": ["biped_puppet_v1", "four_legged_scrambler_v1"],
}

func _initialize() -> void:
	_cleanup_temp_files()
	var parts: Variant = PartCatalogScript.new()
	if not _need(parts.load_path(PARTS_PATH), "part catalog did not load"):
		return
	if not _need(_part_catalog_checks(parts), "part catalog checks failed"):
		return
	if not _need(_loader_failure_checks(parts), "part catalog failure checks failed"):
		return
	if not _need(parts.load_path(PARTS_PATH), "part catalog did not reload"):
		return

	var recipes: Variant = RecipeLibraryScript.new()
	if not _need(recipes.load_path(RECIPES_PATH, parts), "recipe catalog did not load"):
		return
	if not _need(_recipe_library_checks(recipes, parts), "recipe library checks failed"):
		return
	if not _need(_invalid_recipe_checks(recipes, parts), "invalid recipe checks failed"):
		return
	if not _need(_recipe_loader_failure_checks(recipes, parts), "recipe catalog failure checks failed"):
		return

	_cleanup_temp_files()
	print("BIOMASS CATALOG SMOKE PASS parts=8 recipes=5 archetypes=6")
	quit(0)

func _part_catalog_checks(parts: Variant) -> bool:
	if not _need(PART_IDS.size() == 8, "smoke part fixture count changed"):
		return false
	for part_id in PART_IDS:
		if not _need(not parts.get_part(part_id).is_empty(), "missing part %s" % part_id):
			return false
	var arm: Dictionary = parts.get_part("biomass_human_arm_v1")
	if not _need(arm.get("category") == "biomass_limb", "human arm category mismatch"):
		return false
	var locomotors: PackedStringArray = parts.find_by_role("locomotor")
	if not _need(locomotors.size() == 3, "locomotor count mismatch"): return false
	if not _need(locomotors == PackedStringArray(["biomass_cephalopod_tentacle_v1", "biomass_human_arm_v1", "biomass_insect_leg_v1"]), "locomotor IDs are not sorted"): return false

	var limb_socket: Dictionary = parts.socket("biomass_humanoid_torso_v1", "limb_0")
	if not _need(limb_socket.get("name") == "socket_limb_0", "short socket normalization failed"): return false
	var root_socket: Dictionary = parts.socket("biomass_humanoid_torso_v1", "socket_root_0")
	if not _need(root_socket.get("name") == "socket_root_0", "root socket lookup failed"): return false
	if not _need(parts.socket("biomass_humanoid_torso_v1", "limb_99").is_empty(), "unknown socket was matched"): return false
	if not _need(parts.socket("biomass_humanoid_torso_v1", "socket_limb_0").get("name") == "socket_limb_0", "full socket lookup failed"): return false

	arm["category"] = "corrupted"
	limb_socket["name"] = "corrupted"
	if not _need(parts.get_part("biomass_human_arm_v1").get("category") == "biomass_limb", "get_part leaked mutable state"): return false
	if not _need(parts.socket("biomass_humanoid_torso_v1", "limb_0").get("name") == "socket_limb_0", "socket leaked mutable state"): return false
	return true

func _recipe_library_checks(recipes: Variant, parts: Variant) -> bool:
	var ids: PackedStringArray = recipes.recipe_ids()
	if not _need(ids == PackedStringArray(RECIPE_IDS), "recipe IDs are not sorted or complete"): return false
	for recipe_id in RECIPE_IDS:
		var recipe: Variant = recipes.get_recipe(recipe_id)
		if not _need(recipe != null and recipe.is_valid(), "invalid recipe %s: %s" % [recipe_id, recipe.diagnostics()]): return false
		if not _need(recipe.diagnostics().is_empty(), "valid recipe has diagnostics %s" % recipe_id): return false
		var first: Dictionary = recipe.to_dict()
		var second: Dictionary = recipe.to_dict()
		if not _need(first == second, "recipe serialization is not repeatable %s" % recipe_id): return false
		first["recipe_id"] = "mutated"
		first["attachments"].clear()
		if not _need(recipe.to_dict() == second, "recipe serialization leaked mutable state %s" % recipe_id): return false
	var source: Dictionary = recipes.get_recipe("biped_puppet_v1").to_dict()
	var independent: Variant = RecipeScript.from_dict(source, parts)
	source["core"]["part_id"] = "unknown_part"
	source["attachments"].clear()
	if not _need(independent.is_valid() and independent.to_dict().get("core").get("part_id") == "biomass_humanoid_torso_v1", "recipe retained caller-owned input"): return false
	for archetype_id in ARCHETYPE_IDS:
		var pool: PackedStringArray = recipes.pool_for(archetype_id)
		var expected_pool: PackedStringArray = PackedStringArray(EXPECTED_POOLS[archetype_id])
		expected_pool.sort()
		if not _need(pool.size() == 2 and pool == expected_pool and pool == _sorted_pool(pool), "pool is missing, unsorted, or has wrong membership %s" % archetype_id): return false
		var mutated: PackedStringArray = pool
		mutated[0] = "mutated"
		if not _need(recipes.pool_for(archetype_id)[0] != "mutated", "pool_for leaked mutable state"): return false
	if not _need(recipes.pool_for("unknown").is_empty(), "unknown pool fabricated state"): return false
	return true

func _invalid_recipe_checks(recipes: Variant, parts: Variant) -> bool:
	var base: Dictionary = recipes.get_recipe("biped_puppet_v1").to_dict()
	var unknown_part: Dictionary = base.duplicate(true)
	unknown_part["attachments"][0]["part_id"] = "unknown_part"
	if not _expect_stable_invalid(unknown_part, parts, "unknown part"): return false

	var forward_parent: Dictionary = base.duplicate(true)
	forward_parent["attachments"][0]["parent_instance_id"] = "later"
	if not _expect_invalid(forward_parent, parts, "forward parent"): return false

	var forward_chain: Dictionary = base.duplicate(true)
	forward_chain["attachments"][0]["instance_id"] = "rejected_child"
	forward_chain["attachments"][0]["parent_instance_id"] = "later"
	forward_chain["attachments"][1]["parent_instance_id"] = "rejected_child"
	var forward_chain_recipe: Variant = RecipeScript.from_dict(forward_chain, parts)
	if not _need(forward_chain_recipe != null and not forward_chain_recipe.is_valid(), "forward chain was accepted"): return false
	var forward_chain_diagnostics: PackedStringArray = forward_chain_recipe.diagnostics()
	if not _need(forward_chain_diagnostics.has("recipe.attachments[0].parent_instance_id: parent-before-child reference required"), "first forward chain edge was not diagnosed"): return false
	if not _need(forward_chain_diagnostics.has("recipe.attachments[1].parent_instance_id: parent-before-child reference required"), "second forward chain edge was not diagnosed"): return false

	var duplicate_occupancy: Dictionary = base.duplicate(true)
	duplicate_occupancy["attachments"][1]["parent_socket"] = duplicate_occupancy["attachments"][0]["parent_socket"]
	if not _expect_invalid(duplicate_occupancy, parts, "duplicate occupancy"): return false

	var bad_child_root: Dictionary = base.duplicate(true)
	bad_child_root["attachments"][0]["child_socket"] = "head_0"
	if not _expect_invalid(bad_child_root, parts, "bad child root"): return false

	var too_many: Dictionary = base.duplicate(true)
	while too_many["attachments"].size() <= 8:
		too_many["attachments"].append(too_many["attachments"][0].duplicate(true))
	if not _expect_invalid(too_many, parts, "attachment limit"): return false

	var incompatible: Dictionary = base.duplicate(true)
	incompatible["attachments"][0]["part_id"] = "biomass_animal_skull_v1"
	if not _expect_invalid(incompatible, parts, "incompatible category"): return false

	var missing_socket: Dictionary = base.duplicate(true)
	missing_socket["attachments"][0]["parent_socket"] = "missing_0"
	if not _expect_invalid(missing_socket, parts, "missing socket"): return false

	var depth_doc: Dictionary = {
		"recipe_id": "depth_probe",
		"locomotion_hint": "crawl",
		"core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
		"attachments": [],
	}
	var parent_id: String = "core"
	for index in range(4):
		depth_doc["attachments"].append(_edge("chain_%d" % index, "biomass_insect_leg_v1", parent_id, "appendage_0" if index == 0 else "distal_0"))
		parent_id = "chain_%d" % index
	if not _expect_invalid(depth_doc, parts, "depth limit"): return false
	return true

func _expect_invalid(document: Dictionary, parts: Variant, label: String) -> bool:
	var recipe: Variant = RecipeScript.from_dict(document, parts)
	if not _need(recipe != null and not recipe.is_valid(), "%s was accepted" % label): return false
	if not _need(not recipe.diagnostics().is_empty(), "%s had no diagnostics" % label): return false
	if not _need(recipe.to_dict().is_empty(), "%s retained invalid input" % label): return false
	return true

func _expect_stable_invalid(document: Dictionary, parts: Variant, label: String) -> bool:
	var first: Variant = RecipeScript.from_dict(document, parts)
	var second: Variant = RecipeScript.from_dict(document, parts)
	if not _need(first != null and second != null and not first.is_valid() and not second.is_valid(), "%s was accepted" % label): return false
	var first_diagnostics: PackedStringArray = first.diagnostics()
	var second_diagnostics: PackedStringArray = second.diagnostics()
	if not _need(not first_diagnostics.is_empty(), "%s had no diagnostics" % label): return false
	if not _need(first_diagnostics == second_diagnostics, "%s diagnostics were not stable" % label): return false
	var sorted: PackedStringArray = first_diagnostics.duplicate()
	sorted.sort()
	if not _need(first_diagnostics == sorted, "%s diagnostics were not sorted" % label): return false
	var seen: Dictionary = {}
	for diagnostic in first_diagnostics:
		if not _need(not seen.has(diagnostic), "%s diagnostics were not deduplicated" % label): return false
		seen[diagnostic] = true
	if not _need(first.to_dict().is_empty() and second.to_dict().is_empty(), "%s retained invalid input" % label): return false
	return true

func _loader_failure_checks(parts: Variant) -> bool:
	if not _need(not parts.load_path("res://data/combat/biomass_part_catalog_missing.json"), "missing part catalog was accepted"): return false
	if not _need(parts.get_part("biomass_human_arm_v1").is_empty() and parts.find_by_role("locomotor").is_empty(), "part loader retained state after missing input"): return false
	if not _write_text(TEMP_PARTS_PATH, "{}"): return false
	if not _need(not parts.load_path(TEMP_PARTS_PATH), "malformed part catalog was accepted"): return false
	if not _need(parts.get_part("biomass_human_arm_v1").is_empty(), "part loader retained state after malformed input"): return false

	var canonical_text: String = FileAccess.get_file_as_string(PARTS_PATH)
	if not _need(not canonical_text.is_empty(), "canonical part catalog fixture was empty"): return false

	var float_budget_text: String = _replace_exact_once(canonical_text, "\"triangle_budget\": 2500", "\"triangle_budget\": 2500.0", "integral float triangle budget")
	if not _expect_part_catalog_rejected(parts, float_budget_text, "integral float triangle budget"): return false

	var float_limit_text: String = _replace_exact_once(canonical_text, "\"max_attachments\": 8", "\"max_attachments\": 8.0", "integral float fixed limit")
	if not _expect_part_catalog_rejected(parts, float_limit_text, "integral float fixed limit"): return false

	var null_part_text: String = _replace_part_value_with_null(canonical_text, "biomass_human_arm_v1", "biomass_insect_leg_v1")
	if not _expect_part_catalog_rejected(parts, null_part_text, "null nested part value"): return false

	if not _need(parts.load_path(PARTS_PATH), "canonical part catalog did not reload after source mutations"): return false
	if not _need(not parts.get_part("biomass_human_arm_v1").is_empty() and not parts.find_by_role("locomotor").is_empty() and not parts.limits().is_empty(), "canonical part catalog state was not restored after source mutations"): return false
	return true

func _replace_exact_once(text: String, marker: String, replacement: String, label: String) -> String:
	var marker_index: int = text.find(marker)
	if not _need(marker_index >= 0, "%s marker was absent" % label):
		return ""
	return text.substr(0, marker_index) + replacement + text.substr(marker_index + marker.length())

func _replace_part_value_with_null(text: String, part_id: String, next_part_id: String) -> String:
	var start_marker: String = "\"%s\": {" % part_id
	var next_marker: String = "\"%s\": {" % next_part_id
	var start: int = text.find(start_marker)
	var next: int = text.find(next_marker, start + start_marker.length())
	if not _need(start >= 0 and next >= 0, "nested part replacement markers were missing"): return ""
	if not _need(text.count(start_marker) == 1 and text.count(next_marker) == 1, "nested part replacement markers were not unique"): return ""
	var next_line_start: int = text.rfind("\n", next)
	if not _need(next_line_start >= 0, "nested part replacement suffix was missing"): return ""
	var suffix: String = text.substr(next_line_start + 1)
	return text.substr(0, start) + "\"%s\": null,\n" % part_id + suffix

func _expect_part_catalog_rejected(parts: Variant, text: String, label: String) -> bool:
	if not _write_text(TEMP_PARTS_PATH, text): return false
	if not _need(not parts.load_path(TEMP_PARTS_PATH), "%s was accepted" % label): return false
	if not _need(parts.get_part("biomass_human_arm_v1").is_empty() and parts.find_by_role("locomotor").is_empty() and parts.limits().is_empty(), "%s retained part catalog state" % label): return false
	return true

func _recipe_loader_failure_checks(recipes: Variant, parts: Variant) -> bool:
	var canonical_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if not _need(canonical_variant is Dictionary, "canonical recipe catalog fixture did not parse"): return false
	var canonical: Dictionary = canonical_variant

	var missing_recipe: Dictionary = canonical.duplicate(true)
	var missing_recipe_records: Dictionary = missing_recipe["recipes"]
	missing_recipe_records.erase("biped_puppet_v1")
	var missing_recipe_pools: Dictionary = missing_recipe["archetype_pools"]
	(missing_recipe_pools["stalker"] as Array).erase("biped_puppet_v1")
	(missing_recipe_pools["puppet_corpse"] as Array).erase("biped_puppet_v1")
	if not _expect_recipe_library_rejected(recipes, missing_recipe, parts, "missing recipe key"): return false

	var extra_recipe: Dictionary = canonical.duplicate(true)
	var extra_recipe_records: Dictionary = extra_recipe["recipes"]
	var extra_recipe_value: Dictionary = extra_recipe_records["biped_puppet_v1"].duplicate(true)
	extra_recipe_value["recipe_id"] = "unexpected_recipe_v1"
	extra_recipe_records["unexpected_recipe_v1"] = extra_recipe_value
	if not _expect_recipe_library_rejected(recipes, extra_recipe, parts, "extra recipe key"): return false

	var missing_pool: Dictionary = canonical.duplicate(true)
	var missing_pool_records: Dictionary = missing_pool["archetype_pools"]
	missing_pool_records.erase("stalker")
	if not _expect_recipe_library_rejected(recipes, missing_pool, parts, "missing archetype pool key"): return false

	var extra_pool: Dictionary = canonical.duplicate(true)
	var extra_pool_records: Dictionary = extra_pool["archetype_pools"]
	extra_pool_records["unexpected_archetype"] = ["biped_puppet_v1"]
	if not _expect_recipe_library_rejected(recipes, extra_pool, parts, "extra archetype pool key"): return false

	if not _need(recipes.load_path(RECIPES_PATH, parts), "canonical recipe catalog did not reload after key mutations"): return false
	var valid_document: Dictionary = recipes.get_recipe("biped_puppet_v1").to_dict()
	if not _expect_stable_invalid(valid_document, {}, "missing runtime catalog"): return false
	var untyped_library: Variant = RecipeLibraryScript.new()
	if not _need(not untyped_library.load_path(RECIPES_PATH, {}), "recipe library accepted an untyped catalog"): return false
	if not _need(untyped_library.recipe_ids().is_empty() and untyped_library.pool_for("stalker").is_empty(), "recipe library retained state after untyped catalog"): return false

	if not _need(not recipes.load_path("res://data/combat/biomass_recipe_catalog_missing.json", parts), "missing recipe catalog was accepted"): return false
	if not _need(recipes.get_recipe("biped_puppet_v1") == null and recipes.recipe_ids().is_empty(), "recipe loader retained state after missing input"): return false
	if not _write_text(TEMP_RECIPES_PATH, "{}"): return false
	if not _need(not recipes.load_path(TEMP_RECIPES_PATH, parts), "malformed recipe catalog was accepted"): return false
	if not _need(recipes.get_recipe("biped_puppet_v1") == null and recipes.recipe_ids().is_empty(), "recipe loader retained state after malformed input"): return false
	return true

func _expect_recipe_library_rejected(recipes: Variant, document: Dictionary, parts: Variant, label: String) -> bool:
	if not _write_text(TEMP_RECIPES_PATH, JSON.stringify(document)): return false
	if not _need(not recipes.load_path(TEMP_RECIPES_PATH, parts), "%s was accepted" % label): return false
	if not _need(recipes.recipe_ids().is_empty() and recipes.get_recipe("biped_puppet_v1") == null and recipes.pool_for("stalker").is_empty(), "%s retained library state" % label): return false
	return true

func _edge(instance_id: String, part_id: String, parent_id: String, socket_name: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"part_id": part_id,
		"parent_instance_id": parent_id,
		"parent_socket": socket_name,
		"child_socket": "root_0",
		"connector_part_id": "biomass_gunk_connector_v1",
	}

func _sorted_pool(pool: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = pool.duplicate()
	result.sort()
	return result

func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write temporary catalog %s" % path)
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
	print("BIOMASS CATALOG SMOKE FAIL: %s" % message)
	quit(1)

func _cleanup_temp_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PARTS_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_RECIPES_PATH))
