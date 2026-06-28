extends SceneTree

## Data-validation proof: hull_sealant + fire_extinguisher are defined, lootable, and
## craftable at the intended mid-tier — closing the breach-seal / fire-extinguish loops.
## Marker: ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true

func _initialize() -> void:
	var items: Dictionary = _read_json("res://data/items/item_definitions.json")
	var loot: Dictionary = _read_json("res://data/items/loot_tables.json")
	var recipes_doc: Dictionary = _read_json("res://data/recipes/recipe_definitions.json")

	# --- item definitions ---
	var sealant_def: bool = _is_dict(items.get("hull_sealant")) \
		and str(items["hull_sealant"].get("category", "")) == "part" \
		and str(items["hull_sealant"].get("rarity", "")) == "uncommon"
	var ext_def: bool = _is_dict(items.get("fire_extinguisher")) \
		and str(items["fire_extinguisher"].get("category", "")) == "tool" \
		and int(items["fire_extinguisher"].get("max_stack", 99)) == 1 \
		and str(items["fire_extinguisher"].get("rarity", "")) == "uncommon"

	# --- loot presence (any table) ---
	var sealant_loot: bool = _in_any_loot(loot, "hull_sealant")
	var ext_loot: bool = _in_any_loot(loot, "fire_extinguisher")

	# --- recipes ---
	var recipes: Array = recipes_doc.get("recipes", []) if recipes_doc.get("recipes", []) is Array else []
	var r_sealant: Dictionary = _recipe_producing(recipes, "hull_sealant")
	var r_ext: Dictionary = _recipe_producing(recipes, "fire_extinguisher")
	var sealant_recipe: bool = not r_sealant.is_empty() and str(r_sealant.get("station_kind", "")) == "workbench"
	var ext_recipe: bool = not r_ext.is_empty() and str(r_ext.get("station_kind", "")) == "fabricator"
	var skill_gated: bool = int(r_sealant.get("required_skill_level", -1)) == 2 \
		and int(r_ext.get("required_skill_level", -1)) == 3

	if sealant_def and ext_def and sealant_loot and ext_loot and sealant_recipe and ext_recipe and skill_gated:
		print("ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true")
		quit(0)
	else:
		push_error("ITEM ECONOMY FAIL sealant_def=%s ext_def=%s sealant_loot=%s ext_loot=%s sealant_recipe=%s ext_recipe=%s skill_gated=%s" % [
			sealant_def, ext_def, sealant_loot, ext_loot, sealant_recipe, ext_recipe, skill_gated])
		quit(1)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _is_dict(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY

func _in_any_loot(loot: Dictionary, item_id: String) -> bool:
	for table_id in loot:
		var table: Variant = loot[table_id]
		if not _is_dict(table):
			continue
		var entries: Variant = (table as Dictionary).get("entries", [])
		if entries is Array:
			for e in entries:
				if e is Dictionary and str((e as Dictionary).get("item_id", "")) == item_id:
					return true
	return false

func _recipe_producing(recipes: Array, item_id: String) -> Dictionary:
	for r in recipes:
		if r is Dictionary:
			var produces: Variant = (r as Dictionary).get("produces", {})
			if produces is Dictionary and str((produces as Dictionary).get("item_id", "")) == item_id:
				return r as Dictionary
	return {}
