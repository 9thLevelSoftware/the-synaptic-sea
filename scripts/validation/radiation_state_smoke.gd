extends SceneTree

## Pure-model smoke for RadiationState (REQ-SV-003).

const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")

func _initialize() -> void:
	var r = RadiationStateScript.new()
	r.configure({})
	if r.radiation != 0.0:
		_fail("default radiation should be 0")
		return

	# Accumulate in zone
	r.in_radiation_zone = true
	r.tick(1.0)
	if r.radiation <= 0.0:
		_fail("radiation did not accumulate")
		return

	# Health drain above 50%
	r.radiation = 60.0
	var drain: float = r.get_health_drain_per_second()
	if drain <= 0.0:
		_fail("health drain not active above 50%")
		return

	# Decay outside zone
	r.in_radiation_zone = false
	var rad_before: float = r.radiation
	r.tick(1.0)
	if r.radiation >= rad_before:
		_fail("radiation did not decay")
		return

	# Status lines critical
	var lines: PackedStringArray = r.get_status_lines()
	var joined: String = "\n".join(lines)
	if not joined.contains("Radiation:"):
		_fail("missing Radiation line")
		return
	if not joined.contains("RADIATION SICKNESS"):
		_fail("missing radiation sickness line")
		return

	# apply_summary round-trip
	var snap: Dictionary = r.get_summary()
	var r2 = RadiationStateScript.new()
	r2.configure({})
	r2.apply_summary(snap)
	if absf(r2.radiation - r.radiation) > 0.001:
		_fail("apply_summary radiation mismatch")
		return

	print("RADIATION STATE PASS accumulation=true drain=true decay=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("RADIATION STATE FAIL reason=%s" % reason)
	quit(1)
