extends SceneTree

## Pure-model smoke for BodyTemperatureState (REQ-SV-004).

const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")

func _initialize() -> void:
	var t = BodyTemperatureStateScript.new()
	t.configure({})
	if not t.is_safe():
		_fail("default temperature should be safe")
		return

	# Extreme zone raises temperature
	t.in_extreme_zone = true
	t.tick(25.0)
	if t.temperature <= 32.0:
		_fail("temperature did not rise past safe_max")
		return

	# Unsafe triggers thirst multiplier
	var mult: float = t.get_thirst_multiplier()
	if mult <= 1.0:
		_fail("thirst multiplier should be >1.0 when unsafe")
		return

	# Status lines while unsafe
	var lines: PackedStringArray = t.get_status_lines()
	var joined: String = "\n".join(lines)
	if not joined.contains("Temp:"):
		_fail("missing Temp line")
		return
	if not joined.contains("DANGER"):
		_fail("missing DANGER suffix")
		return

	# Recovery outside extreme zone
	t.in_extreme_zone = false
	var temp_before: float = t.temperature
	t.tick(20.0)
	# Should move toward default 22.0
	if t.temperature >= temp_before:
		_fail("temperature did not recover toward safe")
		return

	# apply_summary round-trip
	var snap: Dictionary = t.get_summary()
	var t2 = BodyTemperatureStateScript.new()
	t2.configure({})
	t2.apply_summary(snap)
	if absf(t2.temperature - t.temperature) > 0.001:
		_fail("apply_summary temperature mismatch")
		return

	print("BODY TEMPERATURE STATE PASS safe=false extreme=true recovery=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("BODY TEMPERATURE STATE FAIL reason=%s" % reason)
	quit(1)
