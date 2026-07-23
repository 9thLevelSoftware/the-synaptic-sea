extends RefCounted
class_name HydroponicsWorkResolver

## PKG-C3.2: resolve plant/harvest WorkActions against HydroponicsState + inventory/spoilage.

const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const FoodTravelPlannerScript := preload("res://scripts/systems/food_travel_planner.gd")


## Complete plant WorkAction: crop_config must be provided (from crop catalog).
static func resolve_plant(
		work: RefCounted,
		hydro: RefCounted,
		crop_config: Dictionary,
		skill_level: int,
		available_water: float,
		available_power: float) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "water_consumed": 0.0, "power_consumed": 0.0}
	if work == null or hydro == null:
		out["reason"] = "no_work_or_hydro"
		return out
	if str(work.get("status")) != WorkActionStateScript.STATUS_COMPLETED:
		out["reason"] = "not_completed"
		return out
	if not hydro.has_method("plant"):
		out["reason"] = "no_plant"
		return out
	var res: Dictionary = hydro.call("plant", crop_config, skill_level, available_water, available_power)
	if not bool(res.get("ok", false)):
		out["reason"] = str(res.get("reason", "plant_failed"))
		return out
	out["ok"] = true
	out["water_consumed"] = float(res.get("water_consumed", 0.0))
	out["power_consumed"] = float(res.get("power_consumed", 0.0))
	return out


## Complete harvest WorkAction: yields into inventory dict and registers spoilage.
static func resolve_harvest(
		work: RefCounted,
		hydro: RefCounted,
		inventory: Dictionary,
		spoilage: RefCounted = null) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "item_id": "", "quantity": 0}
	if work == null or hydro == null:
		out["reason"] = "no_work_or_hydro"
		return out
	if str(work.get("status")) != WorkActionStateScript.STATUS_COMPLETED:
		out["reason"] = "not_completed"
		return out
	if not hydro.has_method("harvest"):
		out["reason"] = "no_harvest"
		return out
	var res: Dictionary = hydro.call("harvest")
	if not bool(res.get("ok", false)):
		out["reason"] = "not_harvestable"
		return out
	var item_id: String = str(res.get("item_id", ""))
	var qty: int = maxi(0, int(res.get("quantity", 0)))
	if item_id.is_empty() or qty <= 0:
		out["reason"] = "empty_yield"
		return out
	inventory[item_id] = int(inventory.get(item_id, 0)) + qty
	if spoilage != null:
		FoodTravelPlannerScript.register_harvest(spoilage, item_id, qty, {
			"hunger_restore": 15.0,
			"thirst_restore": 5.0,
			"spoilage_seconds": 1800.0,
		})
	out["ok"] = true
	out["item_id"] = item_id
	out["quantity"] = qty
	return out
