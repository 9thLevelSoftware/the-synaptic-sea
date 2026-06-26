extends RefCounted
class_name CraftingState

const StationStateScript := preload("res://scripts/systems/station_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

## Pure model for the crafting engine. Loads recipes, validates ingredient
## availability against an InventoryState, resolves output quality via
## QualityTierResolver, and manages active craft progress via StationState.
## Never touches the scene tree.

const RECIPE_DEFINITIONS_PATH: String = "res://data/recipes/recipe_definitions.json"

var _recipes: Dictionary = {}      # recipe_id -> recipe Dictionary
var _station_states: Dictionary = {}  # station_kind -> StationState
var _active_craft: Dictionary = {}    # recipe_id, station_kind, progress tracking

func _init() -> void:
	_load_recipes()

func _load_recipes() -> void:
	if not FileAccess.file_exists(RECIPE_DEFINITIONS_PATH):
		return
	var file := FileAccess.open(RECIPE_DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var recipes_array: Variant = (parsed as Dictionary).get("recipes", [])
		if recipes_array is Array:
			for recipe_variant in (recipes_array as Array):
				if recipe_variant is Dictionary:
					var recipe: Dictionary = recipe_variant as Dictionary
					var rid: String = str(recipe.get("recipe_id", ""))
					if not rid.is_empty():
						_recipes[rid] = recipe

func recipe_count() -> int:
	return _recipes.size()

func get_recipe(recipe_id: String) -> Dictionary:
	var r: Variant = _recipes.get(recipe_id, {})
	return r if r is Dictionary else {}

func get_recipes_for_station(station_kind: String) -> Array:
	var out: Array = []
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		if str(recipe.get("station_kind", "")) == station_kind:
			out.append(recipe.duplicate(true))
	return out

func get_recipes_by_category(category: String) -> Array:
	var out: Array = []
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		if str(recipe.get("category", "")) == category:
			out.append(recipe.duplicate(true))
	return out

func get_all_recipe_ids() -> Array:
	var ids: Array = _recipes.keys()
	ids.sort()
	return ids

func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

# --- ingredient validation ---

## Returns true if the inventory has enough of every ingredient.
func can_craft(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var ingredients: Variant = recipe.get("ingredients", {})
	if not (ingredients is Dictionary):
		return false
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		if inventory.get_quantity(str(mat_id)) < need:
			return false
	return true

## Consumes ingredients from inventory. Returns true if successful.
func consume_ingredients(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var ingredients: Variant = recipe.get("ingredients", {})
	if not (ingredients is Dictionary):
		return false
	# Verify first
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		if inventory.get_quantity(str(mat_id)) < need:
			return false
	# Consume
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		inventory.remove_item(str(mat_id), need)
	return true

## Returns the produced item_id and base quantity for a recipe.
func get_produces(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = get_recipe(recipe_id)
	var produces: Variant = recipe.get("produces", {})
	if produces is Dictionary:
		return (produces as Dictionary).duplicate()
	return {}

## Returns the required skill level for a recipe.
func get_required_skill_level(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("required_skill_level", 0))

## Returns the station kind for a recipe.
func get_station_kind(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("station_kind", ""))

## Returns the craft time in seconds for a recipe.
func get_craft_time(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("craft_time_seconds", 0.0))

## Returns the power cost for a recipe.
func get_power_cost(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("power_cost", 0.0))

# --- station management ---

func get_or_create_station(station_kind: String):
	if _station_states.has(station_kind):
		return _station_states[station_kind]
	var station = StationStateScript.new()
	station.configure({"station_kind": station_kind, "level": 0, "powered": true})
	_station_states[station_kind] = station
	return station

func get_station(station_kind: String):
	return _station_states.get(station_kind, null)

func remove_station(station_kind: String) -> void:
	_station_states.erase(station_kind)

# --- crafting execution ---

## Begins crafting a recipe at its designated station. Returns true if started.
## Pre-conditions: ingredients available, station powered (or will pause).
func begin_craft(recipe_id: String, inventory, material_state, player_skill_level: int) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if not can_craft(recipe_id, inventory):
		return false
	var station_kind: String = str(recipe.get("station_kind", ""))
	if station_kind.is_empty():
		return false
	var station = get_or_create_station(station_kind)
	var craft_time: float = float(recipe.get("craft_time_seconds", 0.0))
	if craft_time <= 0.0:
		return false
	consume_ingredients(recipe_id, inventory)
	var avg_quality: float = 0.5
	var ingredients: Variant = recipe.get("ingredients", {})
	if ingredients is Dictionary:
		avg_quality = material_state.average_ingredient_quality(ingredients as Dictionary)
	var resolver = QualityTierResolverScript.new()
	var quality_result: Dictionary = resolver.resolve(avg_quality, player_skill_level, station.level, station.powered)
	_active_craft = {
		"recipe_id": recipe_id,
		"station_kind": station_kind,
		"quality_tier": quality_result["tier"],
		"quality_multiplier": quality_result["multiplier"],
		"quality_score": quality_result["score"],
	}
	station.start_recipe(recipe_id, craft_time)
	return true

## Ticks the active station. Returns true when the craft completes.
func tick(delta_seconds: float) -> bool:
	if _active_craft.is_empty():
		return false
	var station_kind: String = str(_active_craft.get("station_kind", ""))
	var station = get_station(station_kind)
	if station == null:
		return false
	var completed: bool = station.tick(delta_seconds)
	if completed:
		return true
	return false

## Call after tick returns true to collect the finished product.
## Returns {item_id, quantity, quality_tier, quality_multiplier} or empty dict.
func finish_craft() -> Dictionary:
	if _active_craft.is_empty():
		return {}
	var station_kind: String = str(_active_craft.get("station_kind", ""))
	var station = get_station(station_kind)
	if station == null:
		return {}
	if int(station.status) != 3:
		return {}
	var recipe_id: String = str(_active_craft.get("recipe_id", ""))
	var produces: Dictionary = get_produces(recipe_id)
	var result: Dictionary = {
		"item_id": str(produces.get("item_id", "")),
		"quantity": int(produces.get("quantity", 0)),
		"quality_tier": str(_active_craft.get("quality_tier", "standard")),
		"quality_multiplier": float(_active_craft.get("quality_multiplier", 1.0)),
		"quality_score": float(_active_craft.get("quality_score", 0.5)),
	}
	var next_recipe: String = station.finish_and_advance()
	if next_recipe.is_empty():
		_active_craft.clear()
	else:
		# Auto-start next queued recipe if possible (simplified: just start it)
		var next_time: float = get_craft_time(next_recipe)
		station.start_recipe(next_recipe, next_time)
		_active_craft["recipe_id"] = next_recipe
		_active_craft["station_kind"] = station_kind
	return result

func is_crafting() -> bool:
	return not _active_craft.is_empty()

func get_active_recipe_id() -> String:
	return str(_active_craft.get("recipe_id", ""))

func get_active_station_kind() -> String:
	return str(_active_craft.get("station_kind", ""))

func cancel_craft() -> void:
	_active_craft.clear()
	for station_kind in _station_states:
		var station = _station_states[station_kind]
		if station.is_crafting():
			station.status = 0
			station.active_recipe_id = ""
			station.progress_seconds = 0.0
			station.required_seconds = 0.0

# --- save/load ---

func get_summary() -> Dictionary:
	var station_summaries: Dictionary = {}
	for sk in _station_states:
		station_summaries[str(sk)] = _station_states[sk].get_summary()
	return {
		"recipe_count": recipe_count(),
		"active_craft": _active_craft.duplicate(),
		"station_summaries": station_summaries,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var accepted: bool = false
	var changed: bool = false
	var ac: Variant = summary.get("active_craft", {})
	if ac is Dictionary:
		accepted = true
		var d: Dictionary = ac as Dictionary
		if d != _active_craft:
			_active_craft = d.duplicate()
			changed = true
	var ss: Variant = summary.get("station_summaries", {})
	if ss is Dictionary:
		accepted = true
		for sk in (ss as Dictionary):
			var station_summary: Variant = (ss as Dictionary)[sk]
			if station_summary is Dictionary:
				var station = get_or_create_station(str(sk))
				if station.apply_summary(station_summary as Dictionary):
					changed = true
	return changed or accepted

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Recipes: %d" % recipe_count())
	if is_crafting():
		lines.append("Crafting: %s @ %s" % [get_active_recipe_id(), get_active_station_kind()])
	for sk in _station_states:
		for line in _station_states[sk].get_status_lines():
			lines.append(line)
	return lines
