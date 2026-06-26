extends SceneTree

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var crafting = CraftingStateScript.new()
	if crafting.recipe_count() < 50: _fail("Expected >=50 recipes, got %d" % crafting.recipe_count())

	# Recipe lookup
	var recipe: Dictionary = crafting.get_recipe("craft_power_cell")
	if recipe.is_empty(): _fail("craft_power_cell should exist")
	if crafting.get_station_kind("craft_power_cell") != "fabricator": _fail("station kind mismatch")
	if crafting.get_required_skill_level("craft_power_cell") != 2: _fail("skill level mismatch")
	if crafting.get_craft_time("craft_power_cell") != 30.0: _fail("craft time mismatch")

	# Ingredient validation
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 5)
	inv.add_item("wiring_bundle", 5)
	inv.add_item("reactive_gel", 2)
	if not crafting.can_craft("craft_power_cell", inv): _fail("should be craftable")

	var mat = MaterialStateScript.new()
	mat.set_quality("scrap_metal", 0.8)
	mat.set_quality("wiring_bundle", 0.6)
	mat.set_quality("reactive_gel", 0.7)

	# Begin craft
	if not crafting.begin_craft("craft_power_cell", inv, mat, 2): _fail("begin_craft failed")
	if not crafting.is_crafting(): _fail("should be crafting")
	if inv.get_quantity("scrap_metal") != 4: _fail("scrap not consumed")
	if inv.get_quantity("wiring_bundle") != 3: _fail("wiring not consumed")
	if inv.get_quantity("reactive_gel") != 1: _fail("gel not consumed")

	# Tick to completion
	if not crafting.tick(30.0): _fail("should complete")
	var result: Dictionary = crafting.finish_craft()
	if result.get("item_id", "") != "power_cell": _fail("wrong output item")
	if result.get("quantity", 0) != 1: _fail("wrong output quantity")
	if not result.has("quality_tier"): _fail("missing quality_tier")
	if not result.has("quality_multiplier"): _fail("missing quality_multiplier")
	if not (result["quality_multiplier"] is float and result["quality_multiplier"] > 0.0): _fail("invalid multiplier")

	# Batch recipe
	var batch_inv = InventoryStateScript.new()
	batch_inv.add_item("ration_pack", 2)
	batch_inv.add_item("synthesizer_base", 1)
	if not crafting.can_craft("synthesize_nutrient_paste", batch_inv): _fail("batch should be craftable")
	crafting.begin_craft("synthesize_nutrient_paste", batch_inv, mat, 0)
	if not crafting.tick(20.0): _fail("batch should complete")
	var batch_result: Dictionary = crafting.finish_craft()
	if batch_result.get("quantity", 0) != 3: _fail("batch output should be 3")

	# Save/load round-trip
	var summary: Dictionary = crafting.get_summary()
	var crafting2 = CraftingStateScript.new()
	if not crafting2.apply_summary(summary): _fail("apply_summary should return true")
	if crafting2.recipe_count() != crafting.recipe_count(): _fail("recipe count mismatch after round-trip")

	print("CRAFTING STATE PASS recipes=%d consume=true quality=true batch=true round_trip=true" % crafting.recipe_count())
	quit()
