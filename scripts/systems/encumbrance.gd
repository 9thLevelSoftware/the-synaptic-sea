extends RefCounted
class_name Encumbrance

## Pure-static Heavy Load curve. Maps an inventory load-ratio (total_weight /
## capacity) to a movement-speed multiplier, modeled on Project Zomboid's Heavy
## Load tiers: no penalty at/under capacity; ~37% slower at 125%; ~75% slower at
## 175%; clamped to a 0.25 floor beyond. (PZ's endurance/health effects are
## deferred — no player-condition model yet.)

const FLOOR_MULTIPLIER: float = 0.25
const MULT_AT_125: float = 0.63

static func move_speed_multiplier(load_ratio: float) -> float:
	if load_ratio <= 1.0:
		return 1.0
	if load_ratio <= 1.25:
		return lerpf(1.0, MULT_AT_125, (load_ratio - 1.0) / 0.25)
	if load_ratio <= 1.75:
		return lerpf(MULT_AT_125, FLOOR_MULTIPLIER, (load_ratio - 1.25) / 0.50)
	return FLOOR_MULTIPLIER

## Capacity-share, best-first weight reduction. container_reductions is an Array
## of { "capacity": float, "reduction": float }. Sorts best-first (highest
## reduction), lets each container cover up to its capacity of the remaining
## weight at its reduction rate, and returns the total kg saved (>= 0). Weight
## beyond all containers is uncovered. Never exceeds total_weight.
static func weight_reduction_saved(total_weight: float, container_reductions: Array) -> float:
	var sorted: Array = container_reductions.duplicate()
	sorted.sort_custom(func(a, b): return float(a["reduction"]) > float(b["reduction"]))
	var remaining: float = maxf(0.0, total_weight)
	var saved: float = 0.0
	for c in sorted:
		if remaining <= 0.0:
			break
		var covered: float = minf(remaining, maxf(0.0, float(c["capacity"])))
		saved += covered * clampf(float(c["reduction"]), 0.0, 1.0)
		remaining -= covered
	return saved
