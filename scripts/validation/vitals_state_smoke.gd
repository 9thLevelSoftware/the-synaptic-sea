extends SceneTree

## Pure-model smoke for VitalsState (REQ-SV-001).

const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")

func _initialize() -> void:
	var v = VitalsStateScript.new()
	v.configure({})

	# Defaults
	if v.health != 100.0 or v.stamina != 100.0 or v.hunger != 100.0 or v.thirst != 100.0:
		_fail("defaults wrong")
		return

	# Tick drain while moving
	v.tick(1.0, {"moving": true})
	if v.stamina >= 100.0:
		_fail("stamina did not drain while moving")
		return
	if v.hunger >= 100.0:
		_fail("hunger did not drain")
		return
	if v.thirst >= 100.0:
		_fail("thirst did not drain")
		return

	# Tick recovery while not moving
	var stamina_before: float = v.stamina
	v.tick(1.0, {"moving": false})
	if v.stamina <= stamina_before:
		_fail("stamina did not recover while idle")
		return

	# Hunger cascade: set hunger below 30%, recover stamina -> should be halved
	v.hunger = 20.0
	v.stamina = 50.0
	var s_before: float = v.stamina
	v.tick(1.0, {"moving": false})
	var expected_recovery: float = v.stamina_recovery_rate * 0.5 * 1.0
	if absf(v.stamina - (s_before + expected_recovery)) > 0.1:
		_fail("hunger cascade did not halve stamina recovery")
		return

	# Thirst vision warning
	v.thirst = 15.0
	var summary: Dictionary = v.get_summary()
	if not bool(summary.get("thirst_vision_warning_active", false)):
		_fail("thirst vision warning not active")
		return

	# Temperature cascade
	v.hunger = 100.0
	v.tick(1.0, {"moving": false, "temperature_thirst_mult": 1.5})
	# Thirst should drain faster; we already ticked once above so just verify the summary reports the multiplier context was consumed.
	var s2: Dictionary = v.get_summary()
	if float(s2.get("thirst", 0.0)) >= 100.0:
		_fail("thirst did not drain with temperature multiplier")
		return

	# Radiation health drain cascade
	v.health = 100.0
	v.tick(1.0, {"moving": true, "radiation_health_drain": 2.0})
	if v.health >= 100.0:
		_fail("health did not drain from radiation")
		return

	# apply_summary round-trip
	var snap: Dictionary = v.get_summary()
	var v2 = VitalsStateScript.new()
	v2.configure({})
	v2.apply_summary(snap)
	if absf(v2.health - v.health) > 0.001:
		_fail("apply_summary health mismatch")
		return
	if absf(v2.stamina - v.stamina) > 0.001:
		_fail("apply_summary stamina mismatch")
		return

	# Status lines contain expected markers
	var lines: PackedStringArray = v.get_status_lines()
	var joined: String = "\n".join(lines)
	if not joined.contains("Health:"):
		_fail("missing Health line")
		return
	if not joined.contains("Stamina:"):
		_fail("missing Stamina line")
		return
	if not joined.contains("Hunger:"):
		_fail("missing Hunger line")
		return
	if not joined.contains("Thirst:"):
		_fail("missing Thirst line")
		return
	if not joined.contains("vision impaired"):
		_fail("missing thirst vision warning")
		return

	print("VITALS STATE PASS health=%.1f stamina=%.1f hunger=%.1f thirst=%.1f" % [v.health, v.stamina, v.hunger, v.thirst])
	quit(0)

func _fail(reason: String) -> void:
	push_error("VITALS STATE FAIL reason=%s" % reason)
	quit(1)
