extends RefCounted
class_name SpoilageState

## Aggregated spoilage tracker for all food items in inventory or cargo.
## Owns a Dictionary of item_id -> FoodState. Ticks every food item,
## reports stage transitions, and exposes batch queries for UI/HUD.
## Pure model; never touches the scene tree.

var foods: Dictionary = {}   # item_id -> FoodState
var _last_transition_count: int = 0

func _food_state_script():
	return load("res://scripts/systems/food_state.gd")

func add_food(item_id: String, config: Dictionary):
	var fs = _food_state_script().new()
	var cfg: Dictionary = config.duplicate(true)
	cfg["item_id"] = item_id
	fs.configure(cfg)
	foods[item_id] = fs
	return fs

func remove_food(item_id: String) -> void:
	foods.erase(item_id)

func has_food(item_id: String) -> bool:
	return foods.has(item_id)

func get_food(item_id: String):  # -> FoodState (untyped for headless reliability)
	return foods.get(item_id, null)

func tick(delta_seconds: float) -> int:
	var transitions: int = 0
	if delta_seconds <= 0.0:
		return 0
	for item_id in foods:
		var fs = foods[item_id]
		if fs.tick(delta_seconds):
			transitions += 1
	_last_transition_count = transitions
	return transitions

func get_food_count_by_stage(stage: int) -> int:
	var count: int = 0
	for item_id in foods:
		if foods[item_id].stage == stage:
			count += 1
	return count

func get_any_rotten() -> bool:
	for item_id in foods:
		if foods[item_id].stage == load("res://scripts/systems/food_state.gd").Stage.ROTTEN:
			return true
	return false


## PKG-C3.2: eat path — apply spoilage-scaled restores, then drop tracking.
## inventory is optional object with remove_item(id, qty); vitals optional with apply_delta.
func eat(item_id: String, inventory = null, vitals = null, sanity_state = null) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"hunger": 0.0,
		"thirst": 0.0,
		"sanity": 0.0,
		"sickness_risk": 0.0,
		"stage": -1,
	}
	if item_id.is_empty() or not foods.has(item_id):
		out["reason"] = "not_tracked"
		return out
	if inventory != null and inventory.has_method("get_quantity"):
		if int(inventory.get_quantity(item_id)) < 1:
			out["reason"] = "missing_inventory"
			return out
	var fs = foods[item_id]
	var effect: Dictionary = fs.consume()
	out["hunger"] = float(effect.get("hunger", 0.0))
	out["thirst"] = float(effect.get("thirst", 0.0))
	out["sanity"] = float(effect.get("sanity", 0.0))
	out["sickness_risk"] = float(effect.get("sickness_risk", 0.0))
	out["stage"] = int(fs.stage)
	if vitals != null and vitals.has_method("apply_delta"):
		vitals.apply_delta({"hunger": out["hunger"], "thirst": out["thirst"]})
	if sanity_state != null and sanity_state.has_method("adjust_sanity") and absf(out["sanity"]) > 0.0:
		sanity_state.adjust_sanity(out["sanity"])
	if inventory != null and inventory.has_method("remove_item"):
		inventory.remove_item(item_id, 1)
	# If inventory still has stacks, keep spoilage tracking; else remove.
	if inventory != null and inventory.has_method("get_quantity") and int(inventory.get_quantity(item_id)) > 0:
		pass
	else:
		remove_food(item_id)
	out["ok"] = true
	return out


## PKG-C3.2: sum effective hunger restore across tracked foods (travel planning).
func total_effective_hunger() -> float:
	var total: float = 0.0
	for item_id in foods:
		var eff: Dictionary = foods[item_id].get_effective_restores()
		total += float(eff.get("hunger", 0.0))
	return total


## Estimated travel-days of food at a fixed hunger drain per day (default 24*0.5 from VitalsState).
func travel_range_days(hunger_drain_per_day: float = 12.0) -> float:
	if hunger_drain_per_day <= 0.0:
		return 0.0
	return total_effective_hunger() / hunger_drain_per_day

func get_summary() -> Dictionary:
	var entries: Dictionary = {}
	for item_id in foods:
		entries[item_id] = foods[item_id].get_summary()
	return {
		"foods": entries,
		"transition_count": _last_transition_count,
		"rotten_present": get_any_rotten(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var foods_variant: Variant = summary.get("foods", {})
	if typeof(foods_variant) == TYPE_DICTIONARY:
		var foods_dict: Dictionary = foods_variant as Dictionary
		# Add / update existing
		for item_id in foods_dict:
			var food_summary: Variant = foods_dict[item_id]
			if typeof(food_summary) != TYPE_DICTIONARY:
				continue
			if foods.has(item_id):
				if foods[item_id].apply_summary(food_summary as Dictionary):
					changed = true
			else:
				var fs = _food_state_script().new()
				fs.apply_summary(food_summary as Dictionary)
				foods[item_id] = fs
				changed = true
		# Remove foods no longer in summary
		var to_remove: Array = []
		for item_id in foods:
			if not foods_dict.has(item_id):
				to_remove.append(item_id)
		for item_id in to_remove:
			foods.erase(item_id)
			changed = true
	var restored_transition_count: int = int(summary.get("transition_count", 0))
	if _last_transition_count != restored_transition_count:
		changed = true
	_last_transition_count = restored_transition_count
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var fresh: int = get_food_count_by_stage(_food_state_script().Stage.FRESH)
	var stale: int = get_food_count_by_stage(_food_state_script().Stage.STALE)
	var rotten: int = get_food_count_by_stage(_food_state_script().Stage.ROTTEN)
	lines.append("Food stocks: Fresh=%d Stale=%d Rotten=%d" % [fresh, stale, rotten])
	if rotten > 0:
		lines.append("WARNING: %d rotten item(s) present" % rotten)
	return lines

func clear() -> void:
	foods.clear()
	_last_transition_count = 0
