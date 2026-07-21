extends SceneTree

## Encumbrance curve smoke: PZ-tiered move-speed multiplier. 1.0 at/under capacity,
## monotonic non-increasing above it, clamped floor 0.25.

const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")

func _approx(a: float, b: float) -> bool:
	return absf(a - b) <= 0.01

func _init() -> void:
	assert(EncumbranceScript.move_speed_multiplier(0.0) == 1.0, "empty -> full speed")
	assert(EncumbranceScript.move_speed_multiplier(0.5) == 1.0, "half load -> full speed")
	assert(EncumbranceScript.move_speed_multiplier(1.0) == 1.0, "at capacity -> full speed")
	assert(_approx(EncumbranceScript.move_speed_multiplier(1.25), 0.63), "125% -> ~0.63 (PZ)")
	assert(_approx(EncumbranceScript.move_speed_multiplier(1.75), 0.25), "175% -> ~0.25 (PZ)")
	assert(EncumbranceScript.move_speed_multiplier(3.0) == 0.25, "far over -> floor 0.25")
	assert(EncumbranceScript.move_speed_multiplier(-1.0) == 1.0, "negative ratio clamps to full")

	# Health teeth while overloaded (same tier breakpoints as move mult).
	assert(EncumbranceScript.health_drain_per_second(0.5) == 0.0, "under capacity -> no health drain")
	assert(EncumbranceScript.health_drain_per_second(1.0) == 0.0, "at capacity -> no health drain")
	assert(_approx(EncumbranceScript.health_drain_per_second(1.25), 0.5), "125% -> 0.5 HP/s")
	assert(_approx(EncumbranceScript.health_drain_per_second(1.75), 2.0), "175% -> 2.0 HP/s")
	assert(EncumbranceScript.health_drain_per_second(3.0) == 2.0, "far over -> cap 2.0 HP/s")

	# Monotonic non-increasing across a sweep.
	var prev: float = 2.0
	for i in range(0, 31):
		var r: float = float(i) * 0.1   # 0.0 .. 3.0
		var m: float = EncumbranceScript.move_speed_multiplier(r)
		assert(m <= prev + 0.0001, "monotonic non-increasing at r=%s" % str(r))
		prev = m

	# --- per-container weight reduction (slice D): capacity-share, best-first ---
	assert(_approx(EncumbranceScript.weight_reduction_saved(100.0, []), 0.0), "no containers -> 0 saved")
	# Single container, weight under its capacity -> covers all weight.
	assert(_approx(EncumbranceScript.weight_reduction_saved(30.0, [{"capacity": 40.0, "reduction": 0.30}]), 9.0), "30kg x0.30 = 9 saved")
	# Single container, weight over its capacity -> covers only its capacity.
	assert(_approx(EncumbranceScript.weight_reduction_saved(100.0, [{"capacity": 40.0, "reduction": 0.30}]), 12.0), "40kg cap x0.30 = 12 saved")
	# Best-first ordering matters when weight runs out mid-fill: 40kg across
	# caps 30(0.10) + 30(0.50). Best-first fills the 0.50 bag first:
	# 30x0.50 + 10x0.10 = 16.0  (list order would give 30x0.10 + 10x0.50 = 8.0).
	assert(_approx(EncumbranceScript.weight_reduction_saved(40.0, [{"capacity": 30.0, "reduction": 0.10}, {"capacity": 30.0, "reduction": 0.50}]), 16.0), "best-first fill saves 16, not 8")
	# Worked spec example: 70kg, EVA(40,0.30) + belt(12,0.10) = 13.2 saved.
	assert(_approx(EncumbranceScript.weight_reduction_saved(70.0, [{"capacity": 40.0, "reduction": 0.30}, {"capacity": 12.0, "reduction": 0.10}]), 13.2), "spec example saves 13.2")
	# Non-positive weight -> 0 saved.
	assert(_approx(EncumbranceScript.weight_reduction_saved(-5.0, [{"capacity": 40.0, "reduction": 0.30}]), 0.0), "negative weight saves 0")

	print("EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25 health_drain=true")
	quit()
