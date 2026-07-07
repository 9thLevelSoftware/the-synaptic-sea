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
