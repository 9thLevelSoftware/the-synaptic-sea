extends SceneTree

# item_data_integrity_smoke — closes the audit's data-integrity criticals.
#
# The audit found the item data layer split-brained:
#   - 36 of 60 recipe outputs and 24 ingredients had no definition in any
#     file ItemDefs.load_definitions() actually merges;
#   - data/materials/material_definitions.json (33 crafting material defs)
#     was never merged, so every material weighed 0 with no category;
#   - data/items/food_definitions.json was never loaded and contradicted the
#     canonical item_definitions.json in 33 fields.
#
# Asserts, against the REAL merged registry (ItemDefs.load_definitions):
#   1. recipes_resolve — every recipe's produced item AND every ingredient
#      resolves with weight > 0 and a non-empty category.
#   2. loot_resolves — every loot-table entry item resolves likewise.
#   3. materials_merged — every id in material_definitions.json resolves.
#   4. no_shadow_defs — the dead food_definitions.json shadow file stays
#      deleted (its one unique def, synthesized_paste, lives in
#      item_definitions.json; its 33 conflicting fields lost to canon).
#
# Pass marker: ITEM DATA INTEGRITY PASS recipes=<n> loot_ids=<n> materials=<n> no_shadow_defs=true

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const RECIPES_PATH: String = "res://data/recipes/recipe_definitions.json"
const LOOT_TABLES_PATH: String = "res://data/items/loot_tables.json"
const MATERIALS_PATH: String = "res://data/materials/material_definitions.json"
const FOOD_SHADOW_PATH: String = "res://data/items/food_definitions.json"

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _resolves(defs: Dictionary, item_id: String, context: String) -> bool:
	if not defs.has(item_id):
		_fail("'%s' (%s) has no definition in the merged ItemDefs registry" % [item_id, context])
		return false
	if ItemDefsScript.weight_each(defs, item_id) <= 0.0:
		_fail("'%s' (%s) resolves with weight <= 0" % [item_id, context])
		return false
	if ItemDefsScript.category(defs, item_id).is_empty():
		_fail("'%s' (%s) resolves with an empty category" % [item_id, context])
		return false
	return true

func _initialize() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()
	if defs.size() < 50:
		_fail("merged registry suspiciously small (%d defs)" % defs.size())
		return

	# --- Criterion 1: recipes -----------------------------------------------
	var recipes_root: Dictionary = _load_json(RECIPES_PATH)
	var recipes: Variant = recipes_root.get("recipes", [])
	if not (recipes is Array) or (recipes as Array).is_empty():
		_fail("no recipes loaded from %s" % RECIPES_PATH)
		return
	var recipe_count: int = 0
	for recipe_variant in (recipes as Array):
		if not (recipe_variant is Dictionary):
			continue
		var recipe: Dictionary = recipe_variant
		var rid: String = str(recipe.get("recipe_id", "?"))
		recipe_count += 1
		var out_id: String = str((recipe.get("produces", {}) as Dictionary).get("item_id", ""))
		if out_id.is_empty():
			_fail("recipe %s produces no item_id" % rid)
			return
		if not _resolves(defs, out_id, "output of recipe %s" % rid):
			return
		var ingredients: Variant = recipe.get("ingredients", {})
		if ingredients is Dictionary:
			for ing_id in (ingredients as Dictionary):
				if not _resolves(defs, str(ing_id), "ingredient of recipe %s" % rid):
					return

	# --- Criterion 2: loot tables -------------------------------------------
	var tables: Dictionary = _load_json(LOOT_TABLES_PATH)
	var loot_ids: Dictionary = {}
	for table_id in tables:
		if String(table_id).begins_with("_"):
			continue
		var table: Variant = tables[table_id]
		if not (table is Dictionary):
			continue
		for entry in (table as Dictionary).get("entries", []):
			if entry is Dictionary:
				loot_ids[str((entry as Dictionary).get("item_id", ""))] = String(table_id)
	if loot_ids.is_empty():
		_fail("no loot table entries loaded")
		return
	for item_id in loot_ids:
		if not _resolves(defs, String(item_id), "loot table %s" % String(loot_ids[item_id])):
			return

	# --- Criterion 3: materials merged --------------------------------------
	var materials_root: Dictionary = _load_json(MATERIALS_PATH)
	var materials: Variant = materials_root.get("materials", {})
	if not (materials is Dictionary) or (materials as Dictionary).is_empty():
		_fail("material_definitions.json has no materials map")
		return
	for mat_id in (materials as Dictionary):
		if not _resolves(defs, str(mat_id), "material_definitions.json"):
			return

	# --- Criterion 4: no unloaded shadow definition files --------------------
	if FileAccess.file_exists(FOOD_SHADOW_PATH):
		_fail("food_definitions.json exists but is not merged by ItemDefs — delete it or wire it (single source of truth)")
		return
	if not defs.has("synthesized_paste"):
		_fail("synthesized_paste (recipe output, formerly only in food_definitions.json) missing from canon")
		return

	print("ITEM DATA INTEGRITY PASS recipes=%d loot_ids=%d materials=%d no_shadow_defs=true" % [
		recipe_count, loot_ids.size(), (materials as Dictionary).size()])
	quit(0)

func _fail(reason: String) -> void:
	push_error("ITEM DATA INTEGRITY FAIL reason=%s" % reason)
	quit(1)
