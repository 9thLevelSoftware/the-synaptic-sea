extends RefCounted
class_name BiomassRecipeLibrary

const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const CATALOG_FIELDS: Array[String] = ["schema_version", "document_kind", "recipes", "archetype_pools"]
const CANONICAL_RECIPE_IDS: Array[String] = [
	"biped_puppet_v1",
	"four_legged_scrambler_v1",
	"intestinal_dragger_v1",
	"tendril_knot_v1",
	"tripod_hound_v1",
]
const CANONICAL_ARCHETYPE_IDS: Array[String] = [
	"biomatter_swarm",
	"drone_swarm",
	"hull_tendril",
	"mimic",
	"puppet_corpse",
	"stalker",
]

var _recipes: Dictionary = {}
var _pools: Dictionary = {}

func load_path(path: String, parts: Variant) -> bool:
	_recipes.clear()
	_pools.clear()
	if not parts is Object or parts.get_script() != PartCatalogScript:
		return false
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return false
	var document: Dictionary = parsed
	if not _has_exact_fields(document, CATALOG_FIELDS):
		return false
	if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "biomass_recipe_catalog":
		return false
	var recipes_value: Variant = document.get("recipes")
	var pools_value: Variant = document.get("archetype_pools")
	if not recipes_value is Dictionary or not pools_value is Dictionary:
		return false
	var recipe_records: Dictionary = recipes_value
	var pool_records: Dictionary = pools_value
	if not _has_exact_keys(recipe_records, CANONICAL_RECIPE_IDS) or not _has_exact_keys(pool_records, CANONICAL_ARCHETYPE_IDS):
		return false
	if recipe_records.is_empty() or pool_records.is_empty():
		return false

	var loaded_recipes: Dictionary = {}
	var recipe_keys: Array = recipe_records.keys()
	for key in recipe_keys:
		if not key is String or String(key).is_empty():
			return false
	recipe_keys.sort()
	for key in recipe_keys:
		var recipe_value: Variant = recipe_records.get(key)
		if not recipe_value is Dictionary:
			return false
		var recipe: Variant = RecipeScript.from_dict(recipe_value, parts)
		if recipe == null or not recipe.is_valid():
			return false
		var canonical: Dictionary = recipe.to_dict()
		if canonical.get("recipe_id") != key:
			return false
		loaded_recipes[key] = recipe

	var loaded_pools: Dictionary = {}
	var pool_keys: Array = pool_records.keys()
	for key in pool_keys:
		if not key is String or String(key).is_empty():
			return false
	pool_keys.sort()
	for key in pool_keys:
		var value: Variant = pool_records.get(key)
		if not value is Array or (value as Array).is_empty():
			return false
		var pool: PackedStringArray = PackedStringArray()
		var seen: Dictionary = {}
		for recipe_id_value in value:
			if not recipe_id_value is String or String(recipe_id_value).is_empty():
				return false
			var recipe_id: String = recipe_id_value
			if not loaded_recipes.has(recipe_id) or seen.has(recipe_id):
				return false
			seen[recipe_id] = true
			pool.append(recipe_id)
		pool.sort()
		loaded_pools[key] = pool

	_recipes = loaded_recipes
	_pools = loaded_pools
	return true

func get_recipe(recipe_id: String) -> Variant:
	return _recipes.get(recipe_id, null)

func recipe_ids() -> PackedStringArray:
	var ids: Array = _recipes.keys()
	ids.sort()
	var result: PackedStringArray = PackedStringArray()
	for recipe_id in ids:
		result.append(String(recipe_id))
	return result

func pool_for(archetype_id: String) -> PackedStringArray:
	var value: Variant = _pools.get(archetype_id)
	if value is PackedStringArray:
		return (value as PackedStringArray).duplicate()
	return PackedStringArray()

func _has_exact_keys(value: Dictionary, keys: Array[String]) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	for actual_key in value.keys():
		if not actual_key is String or not keys.has(actual_key):
			return false
	return true

func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	for key in value.keys():
		if not fields.has(key):
			return false
	return true
