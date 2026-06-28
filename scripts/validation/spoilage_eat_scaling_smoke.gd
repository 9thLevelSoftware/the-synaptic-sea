extends SceneTree

## Verifies that per-item spoilage stage is applied at eat time.
##
## Before this fix, _apply_food_restores() always created a FRESH FoodState, so
## stale/rotten multipliers were never applied. Now the consumable pipeline reads
## the stage from spoilage_state in the pipeline_context and threads it into the
## FoodState before calling get_effective_restores().
##
## Pass marker:
##   SPOILAGE EAT SCALING PASS stale_lt_fresh=true rotten_lt_stale=true fresh_fallback=true

const SpoilageStateScript := preload("res://scripts/systems/spoilage_state.gd")
const ConsumableStateScript := preload("res://scripts/systems/consumable_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")

## item_id that exists in data/items/item_definitions.json with category=food and
## non-zero hunger_restore/thirst_restore so we can measure the multiplier effect.
const ITEM_ID: String = "cooked_meal"

## spoilage_seconds for cooked_meal (from item_definitions.json): 1800.0
## STALE threshold = 50% elapsed = 900 s; we advance 901 s to land in STALE.
## ROTTEN threshold = 100% elapsed = 1800 s; we advance another 900 s to land in ROTTEN.
const STALE_TICK: float = 901.0
const ROTTEN_TICK: float = 900.0

func _initialize() -> void:
	# --- shared pipeline deps ---
	var effect_dispatcher = EffectDispatcherScript.new()
	effect_dispatcher.configure()

	# --- eat fresh (baseline: no spoilage_state in context) ---
	var fresh_hunger: float = _eat_item_get_hunger_delta(effect_dispatcher, null)
	if fresh_hunger <= 0.0:
		_fail("eating fresh %s should restore hunger (got %.2f)" % [ITEM_ID, fresh_hunger])
		return

	# --- eat stale ---
	var stale_spoilage = SpoilageStateScript.new()
	stale_spoilage.add_food(ITEM_ID, {
		"spoilage_seconds": 1800.0,
	})
	stale_spoilage.tick(STALE_TICK)
	var tracked_stale = stale_spoilage.get_food(ITEM_ID)
	if tracked_stale == null or tracked_stale.stage != load("res://scripts/systems/food_state.gd").Stage.STALE:
		_fail("SpoilageState should be STALE after %.1f s tick (stage=%d)" % [STALE_TICK, tracked_stale.stage if tracked_stale else -1])
		return

	var stale_hunger: float = _eat_item_get_hunger_delta(effect_dispatcher, stale_spoilage)
	if stale_hunger <= 0.0:
		_fail("eating stale %s should still restore some hunger (got %.2f)" % [ITEM_ID, stale_hunger])
		return
	if stale_hunger >= fresh_hunger:
		_fail("stale restore (%.2f) should be less than fresh restore (%.2f)" % [stale_hunger, fresh_hunger])
		return

	# --- eat rotten ---
	var rotten_spoilage = SpoilageStateScript.new()
	rotten_spoilage.add_food(ITEM_ID, {
		"spoilage_seconds": 1800.0,
	})
	rotten_spoilage.tick(STALE_TICK + ROTTEN_TICK)
	var tracked_rotten = rotten_spoilage.get_food(ITEM_ID)
	if tracked_rotten == null or tracked_rotten.stage != load("res://scripts/systems/food_state.gd").Stage.ROTTEN:
		_fail("SpoilageState should be ROTTEN after %.1f s tick (stage=%d)" % [STALE_TICK + ROTTEN_TICK, tracked_rotten.stage if tracked_rotten else -1])
		return

	var rotten_hunger: float = _eat_item_get_hunger_delta(effect_dispatcher, rotten_spoilage)
	if rotten_hunger >= stale_hunger:
		_fail("rotten restore (%.2f) should be less than stale restore (%.2f)" % [rotten_hunger, stale_hunger])
		return

	# --- fallback: spoilage_state present but item NOT registered -> should behave like fresh ---
	var empty_spoilage = SpoilageStateScript.new()
	# Deliberately do NOT add cooked_meal to empty_spoilage.
	var fallback_hunger: float = _eat_item_get_hunger_delta(effect_dispatcher, empty_spoilage)
	if absf(fallback_hunger - fresh_hunger) > 0.001:
		_fail("fresh fallback restore (%.2f) should equal fresh restore (%.2f) when item not in spoilage_state" % [fallback_hunger, fresh_hunger])
		return

	print("SPOILAGE EAT SCALING PASS stale_lt_fresh=true rotten_lt_stale=true fresh_fallback=true fresh=%.2f stale=%.2f rotten=%.2f fallback=%.2f" % [
		fresh_hunger, stale_hunger, rotten_hunger, fallback_hunger
	])
	quit(0)


## Helper: eat one ITEM_ID through ConsumableState with the given spoilage_state
## (or null for no spoilage tracking). Returns the hunger delta from VitalsState.
func _eat_item_get_hunger_delta(effect_dispatcher, spoilage_state) -> float:
	var consumable = ConsumableStateScript.new()
	consumable.configure()

	var inventory = InventoryStateScript.new()
	inventory.add_item(ITEM_ID, 1)

	var vitals = VitalsStateScript.new()
	vitals.hunger = 0.0
	vitals.thirst = 0.0

	var pipeline_context: Dictionary = {
		"effect_dispatcher": effect_dispatcher,
		"vitals_state": vitals,
	}
	if spoilage_state != null:
		pipeline_context["spoilage_state"] = spoilage_state

	var _result: Dictionary = consumable.use_item(ITEM_ID, inventory, pipeline_context, false)
	return vitals.hunger


func _fail(reason: String) -> void:
	push_error("SPOILAGE EAT SCALING FAIL reason=%s" % reason)
	quit(1)
