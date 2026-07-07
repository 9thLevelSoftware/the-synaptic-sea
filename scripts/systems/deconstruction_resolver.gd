extends RefCounted
class_name DeconstructionResolver

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")

## Pure model for breaking items down into base materials.
## Reads deconstruction recipes (category == "deconstruction") from the
## recipe catalog and resolves them against inventory. Never touches the scene tree.

var _crafting_state = CraftingStateScript.new()

func _init() -> void:
	pass

## Returns all deconstruction recipes.
func get_deconstruction_recipes() -> Array:
	return _crafting_state.get_recipes_by_category("deconstruction")

## Returns true if the inventory has the target item to deconstruct.
func can_deconstruct(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("category", "")) != "deconstruction":
		return false
	return _crafting_state.can_craft(recipe_id, inventory)

## Deconstructs an item, consuming it and producing base materials.
## Returns the produces dict {item_id, quantity} or empty dict on failure.
func deconstruct(recipe_id: String, inventory, material_state) -> Dictionary:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return {}
	if str(recipe.get("category", "")) != "deconstruction":
		return {}
	if not can_deconstruct(recipe_id, inventory):
		return {}
	# For deconstruction, material quality of the source item doesn't affect output
	# (deconstruction yields base materials at standard quality).
	if _crafting_state.consume_ingredients(recipe_id, inventory):
		var produces: Dictionary = _crafting_state.get_produces(recipe_id)
		var out_id: String = str(produces.get("item_id", ""))
		var out_qty: int = int(produces.get("quantity", 0))
		if not out_id.is_empty() and out_qty > 0:
			# Set output material quality to standard (0.5) if it's a known material
			if material_state.has_definition(out_id):
				material_state.set_quality(out_id, 0.5)
			return produces.duplicate()
	return {}

## Auto-deconstruct: finds the first deconstruction recipe for a given item_id
## and executes it. Returns the produces dict or empty.
func auto_deconstruct(item_id: String, inventory, material_state) -> Dictionary:
	for recipe in get_deconstruction_recipes():
		var ingredients: Variant = recipe.get("ingredients", {})
		if ingredients is Dictionary and (ingredients as Dictionary).has(item_id):
			return deconstruct(str(recipe.get("recipe_id", "")), inventory, material_state)
	return {}

func get_summary() -> Dictionary:
	return {
		"deconstruction_recipes": get_deconstruction_recipes().size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	return false

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Deconstruction recipes: %d" % get_deconstruction_recipes().size())
	return lines
