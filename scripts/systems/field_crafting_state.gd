extends RefCounted
class_name FieldCraftingState

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const StationStateScript := preload("res://scripts/systems/station_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

## Pure model for portable/field crafting. A subset of recipes with
## station_kind == "field_crafting" can be executed without a powered station.
## Uses the same recipe catalog as CraftingState but enforces the field-only
## restriction and skips quality bonuses from station level/power.
## Never touches the scene tree.

var _crafting_state = CraftingStateScript.new()

func _init() -> void:
	pass

## Returns field-craftable recipes (station_kind == "field_crafting").
func get_field_recipes() -> Array:
	return _crafting_state.get_recipes_for_station("field_crafting")

## REQ-CS-016 field residual: listing for the portable recipe picker.
## Field crafting is intentionally skill-ungated for start (skill only affects
## quality), so entries use a high skill level for status and only report
## missing_ingredients / output_full as blockers.
func list_recipe_entries(inventory) -> Array:
	return _crafting_state.list_recipe_entries("field_crafting", inventory, 999)

func first_ready_recipe_id(inventory) -> String:
	for entry in list_recipe_entries(inventory):
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

func can_craft(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("station_kind", "")) != "field_crafting":
		return false
	return _crafting_state.can_craft(recipe_id, inventory)

## Begins a field craft. Quality is resolved with station_level=0 and powered=false.
func begin_craft(recipe_id: String, inventory, material_state, player_skill_level: int) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("station_kind", "")) != "field_crafting":
		return false
	if not can_craft(recipe_id, inventory):
		return false
	# Use the base CraftingState logic but force a synthetic field station
	var station = StationStateScript.new()
	# Field crafting is intentionally unpowered for quality resolution, but the
	# portable craft itself must still progress without entering the station's
	# PAUSED_POWER state.
	station.configure({"station_kind": "field_crafting", "level": 0, "powered": true})
	_crafting_state._station_states["field_crafting"] = station
	_crafting_state.consume_ingredients(recipe_id, inventory)
	var avg_quality: float = 0.5
	var ingredients: Variant = recipe.get("ingredients", {})
	if ingredients is Dictionary:
		avg_quality = material_state.average_ingredient_quality(ingredients as Dictionary)
	var resolver = QualityTierResolverScript.new()
	var quality_result: Dictionary = resolver.resolve(avg_quality, player_skill_level, 0, false)
	_crafting_state._active_craft = {
		"recipe_id": recipe_id,
		"station_kind": "field_crafting",
		"quality_tier": quality_result["tier"],
		"quality_multiplier": quality_result["multiplier"],
		"quality_score": quality_result["score"],
	}
	var craft_time: float = float(recipe.get("craft_time_seconds", 0.0))
	station.start_recipe(recipe_id, craft_time)
	return true

func tick(delta_seconds: float) -> bool:
	return _crafting_state.tick(delta_seconds)

func finish_craft() -> Dictionary:
	return _crafting_state.finish_craft()

func is_crafting() -> bool:
	return _crafting_state.is_crafting()

func get_active_recipe_id() -> String:
	return _crafting_state.get_active_recipe_id()

func cancel_craft() -> void:
	_crafting_state.cancel_craft()

func get_summary() -> Dictionary:
	return {
		"field_crafting": _crafting_state.get_summary(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var fc: Variant = summary.get("field_crafting", {})
	if fc is Dictionary:
		return _crafting_state.apply_summary(fc as Dictionary)
	return false

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Field Crafting")
	for line in _crafting_state.get_status_lines():
		lines.append(line)
	return lines
