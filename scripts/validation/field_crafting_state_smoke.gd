extends SceneTree

const FieldCraftingStateScript := preload("res://scripts/systems/field_crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var field = FieldCraftingStateScript.new()
	var recipes: Array = field.get_field_recipes()
	if recipes.size() < 4: _fail("Expected >=4 field recipes, got %d" % recipes.size())

	# Verify field-only restriction
	var inv = InventoryStateScript.new()
	inv.add_item("synth_fiber", 5)
	inv.add_item("medical_gauze", 2)
	if not field.can_craft("field_bandage", inv): _fail("field_bandage should be craftable")
	if field.can_craft("craft_power_cell", inv): _fail("non-field recipe should be rejected")

	var mat = MaterialStateScript.new()
	mat.set_quality("synth_fiber", 0.6)

	# Begin and complete field craft
	if not field.begin_craft("field_bandage", inv, mat, 0): _fail("begin field craft failed")
	if not field.is_crafting(): _fail("should be crafting")
	if not field.tick(8.0): _fail("should complete")
	var result: Dictionary = field.finish_craft()
	if result.get("item_id", "") != "field_bandage": _fail("wrong field output")
	if result.get("quantity", 0) != 1: _fail("wrong field quantity")

	# Round-trip
	var summary: Dictionary = field.get_summary()
	var field2 = FieldCraftingStateScript.new()
	if not field2.apply_summary(summary): _fail("apply_summary should return true")

	print("FIELD CRAFTING STATE PASS recipes=%d restriction=true complete=true round_trip=true" % recipes.size())
	quit()
