extends SceneTree

## Data-validation proof: hull_sealant + fire_extinguisher are defined, lootable, and
## craftable at the intended mid-tier — closing the breach-seal / fire-extinguish loops.
## Marker: ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_enforced=true

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

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
	var skill_meta: bool = int(r_sealant.get("required_skill_level", -1)) == 2 \
		and int(r_ext.get("required_skill_level", -1)) == 3

	# Behavioral proof the gate is ENFORCED (not just metadata): CraftingState.begin_craft
	# must reject an under-skilled player and accept a skilled one for craft_hull_sealant
	# (skill 2). Refutes the false validation pass where required_skill_level only affected
	# crafting quality.
	var craft = CraftingStateScript.new()
	var mat = MaterialStateScript.new()
	var inv_low = InventoryStateScript.new()
	inv_low.add_item("sealant", 2); inv_low.add_item("adhesive_paste", 1)
	var rejected_low: bool = not craft.begin_craft("craft_hull_sealant", inv_low, mat, 1)  # 1 < 2
	var inv_ok = InventoryStateScript.new()
	inv_ok.add_item("sealant", 2); inv_ok.add_item("adhesive_paste", 1)
	var accepted_ok: bool = craft.begin_craft("craft_hull_sealant", inv_ok, mat, 2)        # 2 >= 2
	var skill_enforced: bool = skill_meta and rejected_low and accepted_ok

	if sealant_def and ext_def and sealant_loot and ext_loot and sealant_recipe and ext_recipe and skill_enforced:
		print("ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_enforced=true")
		quit(0)
	else:
		push_error("ITEM ECONOMY FAIL sealant_def=%s ext_def=%s sealant_loot=%s ext_loot=%s sealant_recipe=%s ext_recipe=%s skill_meta=%s rejected_low=%s accepted_ok=%s" % [
			sealant_def, ext_def, sealant_loot, ext_loot, sealant_recipe, ext_recipe, skill_meta, rejected_low, accepted_ok])
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
