extends RefCounted
class_name CookingState

## Pure model for cooking station state machine.
## Consumes ingredients and power, ticks a timer, produces food items.
## Never touches the scene tree.
##
## NOTE: The standalone cooking path (galley `cooking_recipes.json`) was superseded by the
## ADR-0038 kitchen crafting station (recipe_definitions.json), which is the live food
## producer. This class is retained as the internal state machine wrapped by
## `SynthesizerState._cooking` — that is now its only consumer.

enum State { IDLE, COOKING, COMPLETE }

var recipe_id: String = ""
var recipe_name: String = ""
var ingredients: Dictionary = {}     # item_id -> quantity required
var produces_item_id: String = ""
var produces_quantity: int = 1
var power_cost: float = 0.0
var cook_time_seconds: float = 0.0
var required_skill_level: int = 0
var station_kind: String = "galley"

var state: int = State.IDLE
var progress_seconds: float = 0.0

func configure(config: Dictionary) -> void:
	recipe_id = str(config.get("recipe_id", ""))
	recipe_name = str(config.get("display_name", recipe_id))
	var ing: Variant = config.get("ingredients", {})
	ingredients = ing as Dictionary if typeof(ing) == TYPE_DICTIONARY else {}
	var prod: Variant = config.get("produces", {})
	if typeof(prod) == TYPE_DICTIONARY:
		produces_item_id = str(prod.get("item_id", ""))
		produces_quantity = int(prod.get("quantity", 1))
	else:
		produces_item_id = ""
		produces_quantity = 1
	power_cost = float(config.get("power_cost", 0.0))
	cook_time_seconds = maxf(0.1, float(config.get("cook_time_seconds", 0.0)))
	required_skill_level = int(config.get("required_skill_level", 0))
	station_kind = str(config.get("station_kind", "galley"))
	state = State.IDLE
	progress_seconds = 0.0

## Start cooking. inventory_summary shape: {"items": {"item_id": qty, ...}}.
## Returns {"ok": bool, "reason": String}.
func start_cooking(inventory_summary: Dictionary, skill_level: int, available_power: float) -> Dictionary:
	if state != State.IDLE:
		return {"ok": false, "reason": "not_idle"}
	if skill_level < required_skill_level:
		return {"ok": false, "reason": "insufficient_skill"}
	if available_power < power_cost:
		return {"ok": false, "reason": "insufficient_power"}
	var inv_items: Dictionary = inventory_summary.get("items", inventory_summary)
	for item_id in ingredients:
		var needed: int = int(ingredients[item_id])
		var have: int = int(inv_items.get(item_id, 0))
		if have < needed:
			return {"ok": false, "reason": "missing_ingredient_%s" % item_id}
	state = State.COOKING
	progress_seconds = 0.0
	return {"ok": true, "reason": "", "power_consumed": power_cost}

func tick(delta_seconds: float) -> bool:
	if state != State.COOKING:
		return false
	if delta_seconds <= 0.0:
		return false
	progress_seconds += delta_seconds
	if progress_seconds >= cook_time_seconds:
		state = State.COMPLETE
		return true
	return false

func get_progress_ratio() -> float:
	if cook_time_seconds <= 0.0:
		return 0.0
	return clampf(progress_seconds / cook_time_seconds, 0.0, 1.0)

func is_complete() -> bool:
	return state == State.COMPLETE

func collect_result() -> Dictionary:
	if state != State.COMPLETE:
		return {"ok": false, "item_id": "", "quantity": 0}
	var out: Dictionary = {
		"ok": true,
		"item_id": produces_item_id,
		"quantity": produces_quantity,
	}
	state = State.IDLE
	progress_seconds = 0.0
	return out

func cancel() -> void:
	state = State.IDLE
	progress_seconds = 0.0

func get_summary() -> Dictionary:
	return {
		"recipe_id": recipe_id,
		"recipe_name": recipe_name,
		"state": state,
		"progress_seconds": progress_seconds,
		"cook_time_seconds": cook_time_seconds,
		"progress_ratio": get_progress_ratio(),
		"ingredients": ingredients.duplicate(true),
		"produces_item_id": produces_item_id,
		"produces_quantity": produces_quantity,
		"power_cost": power_cost,
		"required_skill_level": required_skill_level,
		"station_kind": station_kind,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_rid: String = str(summary.get("recipe_id", recipe_id))
	if new_rid != recipe_id:
		recipe_id = new_rid
		changed = true
	var new_name: String = str(summary.get("recipe_name", recipe_name))
	if new_name != recipe_name:
		recipe_name = new_name
		changed = true
	var new_state: int = int(summary.get("state", state))
	if new_state != state:
		state = new_state
		changed = true
	var new_progress: float = float(summary.get("progress_seconds", progress_seconds))
	if absf(new_progress - progress_seconds) > 0.001:
		progress_seconds = new_progress
		changed = true
	var new_cook_time: float = float(summary.get("cook_time_seconds", cook_time_seconds))
	if absf(new_cook_time - cook_time_seconds) > 0.001:
		cook_time_seconds = maxf(0.1, new_cook_time)
		changed = true
	var new_prod: String = str(summary.get("produces_item_id", produces_item_id))
	if new_prod != produces_item_id:
		produces_item_id = new_prod
		changed = true
	var new_qty: int = int(summary.get("produces_quantity", produces_quantity))
	if new_qty != produces_quantity:
		produces_quantity = new_qty
		changed = true
	var new_power: float = float(summary.get("power_cost", power_cost))
	if absf(new_power - power_cost) > 0.001:
		power_cost = new_power
		changed = true
	var new_skill: int = int(summary.get("required_skill_level", required_skill_level))
	if new_skill != required_skill_level:
		required_skill_level = new_skill
		changed = true
	var new_kind: String = str(summary.get("station_kind", station_kind))
	if new_kind != station_kind:
		station_kind = new_kind
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var state_name: String = "IDLE"
	if state == State.COOKING:
		state_name = "COOKING"
	elif state == State.COMPLETE:
		state_name = "COMPLETE"
	lines.append("Cooking: %s [%s]" % [recipe_name, state_name])
	if state == State.COOKING:
		lines.append("  progress=%d%%" % int(round(get_progress_ratio() * 100.0)))
	elif state == State.COMPLETE:
		lines.append("  ready: %s x%d" % [produces_item_id, produces_quantity])
	return lines
