extends RefCounted
class_name DeconstructionResolver

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const JunkYieldResolverScript := preload("res://scripts/systems/junk_yield_resolver.gd")

## Pure model for breaking items down into base materials.
## Reads deconstruction recipes (category == "deconstruction") from the
## recipe catalog and resolves them against inventory. Also runs the
## JunkYieldResolver catalog for raw junk salvage (Stream E residual MVP).
## Never touches the scene tree.

var _crafting_state = CraftingStateScript.new()
var _junk_defs: Dictionary = {}

func _init() -> void:
	_junk_defs = JunkYieldResolverScript.load_definitions()

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

## Stream E: salvage the first inventory junk item that has a JunkYieldResolver
## catalog entry. Deterministic (sorted item ids). Returns produces-shaped dict
## for the primary material plus multi-yield metadata, or empty on no match.
##
## Shape on success:
##   {item_id, quantity, source_junk, materials: {mid: qty}, multi_yield: true}
func salvage_junk(inventory, material_state) -> Dictionary:
	if inventory == null:
		return {}
	if _junk_defs.is_empty():
		_junk_defs = JunkYieldResolverScript.load_definitions()
	var ids: Array = inventory.items.keys() if inventory.items is Dictionary else []
	ids.sort()
	for item_id_variant in ids:
		var item_id: String = str(item_id_variant)
		if inventory.get_quantity(item_id) <= 0:
			continue
		var yields: Array = JunkYieldResolverScript.yields_for_item(item_id, _junk_defs)
		if yields.is_empty():
			continue
		# Pre-check stack room for every yield so we never consume junk without
		# depositing its materials (mirrors craft can_accept guards).
		var can_all: bool = true
		for entry_variant in yields:
			if not (entry_variant is Dictionary):
				continue
			var entry: Dictionary = entry_variant
			var mid: String = str(entry.get("material_id", ""))
			var qty: int = int(entry.get("quantity", 0))
			if mid.is_empty() or qty <= 0:
				continue
			if not inventory.can_accept(mid, qty):
				can_all = false
				break
		if not can_all:
			continue
		if inventory.remove_item(item_id, 1) != 1:
			continue
		var materials: Dictionary = {}
		var first_id: String = ""
		var first_qty: int = 0
		for entry_variant2 in yields:
			if not (entry_variant2 is Dictionary):
				continue
			var y: Dictionary = entry_variant2
			var mid2: String = str(y.get("material_id", ""))
			var qty2: int = int(y.get("quantity", 0))
			if mid2.is_empty() or qty2 <= 0:
				continue
			inventory.add_item(mid2, qty2)
			if material_state != null and material_state.has_method("has_definition") \
					and material_state.has_definition(mid2) \
					and material_state.has_method("set_quality"):
				material_state.set_quality(mid2, 0.5)
			materials[mid2] = int(materials.get(mid2, 0)) + qty2
			if first_id.is_empty():
				first_id = mid2
				first_qty = qty2
		if first_id.is_empty():
			# No depositable yields — restore junk (should not happen after pre-check).
			inventory.add_item(item_id, 1)
			return {}
		return {
			"item_id": first_id,
			"quantity": first_qty,
			"source_junk": item_id,
			"materials": materials,
			"multi_yield": materials.size() > 1,
		}
	return {}

func get_summary() -> Dictionary:
	return {
		"deconstruction_recipes": get_deconstruction_recipes().size(),
		"junk_catalog_items": _junk_defs.size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	return false

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Deconstruction recipes: %d" % get_deconstruction_recipes().size())
	return lines
