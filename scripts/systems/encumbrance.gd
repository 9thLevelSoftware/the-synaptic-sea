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
