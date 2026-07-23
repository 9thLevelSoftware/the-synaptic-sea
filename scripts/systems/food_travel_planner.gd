extends RefCounted
class_name FoodTravelPlanner

## PKG-C3.2: pure travel-range constraint from food stores + optional SeaGraph route.
## Does not mutate scene; SeaGraph.apply_travel_cost still owns fuel/food resource dicts.

const DEFAULT_HUNGER_PER_DAY: float = 12.0
const DEFAULT_FOOD_UNITS_PER_DAY: float = 1.0


## spoilage: SpoilageState-like with total_effective_hunger / travel_range_days
## route: SeaGraph find_route result with food cost
## resources: { food: float } inventory units for route food_cost
static func can_attempt_route(
		spoilage: RefCounted,
		route: Dictionary,
		resources: Dictionary = {},
		hunger_per_day: float = DEFAULT_HUNGER_PER_DAY) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"travel_days": 0.0,
		"food_range_days": 0.0,
		"route_food_cost": 0.0,
		"food_units": 0.0,
	}
	if not bool(route.get("ok", false)):
		out["reason"] = "bad_route"
		return out
	var range_days: float = 0.0
	if spoilage != null and spoilage.has_method("travel_range_days"):
		range_days = float(spoilage.call("travel_range_days", hunger_per_day))
	out["food_range_days"] = range_days
	# Convert route distance to days: assume 50 distance units per day of travel
	var distance: float = float(route.get("distance", 0.0))
	var travel_days: float = distance / 50.0 if distance > 0.0 else 0.0
	out["travel_days"] = travel_days
	var route_food: float = float(route.get("food", 0.0))
	out["route_food_cost"] = route_food
	var food_units: float = float(resources.get("food", 0.0))
	out["food_units"] = food_units
	if food_units < route_food:
		out["reason"] = "insufficient_food_units"
		return out
	if range_days + 0.001 < travel_days:
		out["reason"] = "insufficient_spoilage_stores"
		return out
	out["ok"] = true
	return out


## Register harvested produce into spoilage tracking with default food config.
static func register_harvest(spoilage: RefCounted, item_id: String, qty: int = 1, config: Dictionary = {}) -> bool:
	if spoilage == null or item_id.is_empty() or qty <= 0:
		return false
	if not spoilage.has_method("add_food"):
		return false
	var cfg: Dictionary = {
		"item_id": item_id,
		"display_name": str(config.get("display_name", item_id)),
		"hunger_restore": float(config.get("hunger_restore", 15.0)),
		"thirst_restore": float(config.get("thirst_restore", 5.0)),
		"sanity_restore": float(config.get("sanity_restore", 0.0)),
		"spoilage_seconds": float(config.get("spoilage_seconds", 1800.0)),
	}
	# Track one FoodState per item_id; harvest stacks share stage (MVP).
	if spoilage.has_method("has_food") and bool(spoilage.call("has_food", item_id)):
		return true
	spoilage.call("add_food", item_id, cfg)
	return true
