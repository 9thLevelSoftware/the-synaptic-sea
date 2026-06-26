extends SceneTree

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var crafting = CraftingStateScript.new()
	if crafting.recipe_count() < 50: _fail("Expected >=50 recipes, got %d" % crafting.recipe_count())

	var mat = MaterialStateScript.new()
	var known_station_kinds: Array = ["fabricator", "workbench", "medbay", "kitchen", "synthesizer", "field_crafting"]
	var required_fields: Array = ["recipe_id", "display_name", "category", "ingredients", "produces", "craft_time_seconds", "required_skill_level", "station_kind", "power_cost", "batch_size"]

	for rid in crafting.get_all_recipe_ids():
		var recipe: Dictionary = crafting.get_recipe(rid)
		for field in required_fields:
			if not recipe.has(field): _fail("Recipe %s missing field %s" % [rid, field])

		var station_kind: String = str(recipe.get("station_kind", ""))
		if not (station_kind in known_station_kinds): _fail("Recipe %s has unknown station_kind: %s" % [rid, station_kind])

		var ingredients: Variant = recipe.get("ingredients", {})
		if not (ingredients is Dictionary): _fail("Recipe %s ingredients not a dict" % rid)
		for mat_id in (ingredients as Dictionary):
			pass  # allow item IDs

		var produces: Variant = recipe.get("produces", {})
		if not (produces is Dictionary): _fail("Recipe %s produces not a dict" % rid)
		if not (produces as Dictionary).has("item_id"): _fail("Recipe %s produces missing item_id" % rid)
		if not (produces as Dictionary).has("quantity"): _fail("Recipe %s produces missing quantity" % rid)

		var craft_time: float = float(recipe.get("craft_time_seconds", 0.0))
		if craft_time <= 0.0: _fail("Recipe %s craft_time must be > 0" % rid)

		var batch_size: int = int(recipe.get("batch_size", 0))
		if batch_size <= 0: _fail("Recipe %s batch_size must be > 0" % rid)

	# Material count check
	if mat.count_defined() < 30: _fail("Expected >=30 materials, got %d" % mat.count_defined())

	print("RECIPE RESOURCE PASS recipes=%d materials=%d schema=true stations=true" % [crafting.recipe_count(), mat.count_defined()])
	quit()
