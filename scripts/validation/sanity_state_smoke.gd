extends SceneTree

## Pure-model smoke for SanityState (REQ-SV-002).

const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")

func _initialize() -> void:
	var s = SanityStateScript.new()
	s.configure({})
	if s.sanity != 100.0:
		_fail("default sanity should be 100")
		return

	# Drain in unsafe zone
	s.in_safe_zone = false
	s.tick(1.0)
	if s.sanity >= 100.0:
		_fail("sanity did not drain in unsafe zone")
		return

	# Recovery in safe zone
	s.sanity = 50.0
	s.in_safe_zone = true
	s.tick(1.0)
	if s.sanity <= 50.0:
		_fail("sanity did not recover in safe zone")
		return

	# Perception pressure below 40%
	s.sanity = 35.0
	s.in_safe_zone = false
	var summary: Dictionary = s.get_summary()
	if not bool(summary.get("perception_pressure_active", false)):
		_fail("perception pressure not active at sanity=35")
		return

	# Status lines
	var lines: PackedStringArray = s.get_status_lines()
	var joined: String = "\n".join(lines)
	if not joined.contains("Sanity:"):
		_fail("missing Sanity line")
		return
	if not joined.contains("PERCEPTION PRESSURE"):
		_fail("missing perception pressure line")
		return

	# apply_summary round-trip
	var snap: Dictionary = s.get_summary()
	var s2 = SanityStateScript.new()
	s2.configure({})
	s2.apply_summary(snap)
	if absf(s2.sanity - s.sanity) > 0.001:
		_fail("apply_summary sanity mismatch")
		return

	print("SANITY STATE PASS drain=%.1f recovery=%.1f pressure=true" % [s.sanity, s2.sanity])
	quit(0)

func _fail(reason: String) -> void:
	push_error("SANITY STATE FAIL reason=%s" % reason)
	quit(1)
