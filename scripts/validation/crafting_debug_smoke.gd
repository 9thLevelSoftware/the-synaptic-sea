extends SceneTree

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _initialize() -> void:
	print("DEBUG: preloads ok")
	var crafting = CraftingStateScript.new()
	print("DEBUG: crafting created recipes=%d" % crafting.recipe_count())
	quit()
