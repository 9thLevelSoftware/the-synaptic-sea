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

	# Monotonic non-increasing across a sweep.
	var prev: float = 2.0
	for i in range(0, 31):
		var r: float = float(i) * 0.1   # 0.0 .. 3.0
		var m: float = EncumbranceScript.move_speed_multiplier(r)
		assert(m <= prev + 0.0001, "monotonic non-increasing at r=%s" % str(r))
		prev = m

	print("EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25")
	quit()
