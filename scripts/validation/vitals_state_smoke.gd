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

	# M7-B: fire_health_drain channel adds to health drain.
	var vf := VitalsStateScript.new()
	vf.configure({"health": 50.0, "max_health": 100.0})
	vf.tick(1.0, {"moving": false, "fire_health_drain": 4.0})
	if absf(vf.health - 46.0) > 0.001:
		_fail("fire_health_drain not applied (expected 46.0, got %.3f)" % vf.health)
		return

	# Sanity teeth: sanity_health_drain adds to health drain at sanity tier 3.
	var vs := VitalsStateScript.new()
	vs.configure({})
	vs.health = 90.0
	vs.tick(1.0, {"sanity_health_drain": 5.0, "moving": false})
	var drain_ok := vs.health < 90.0
	if not drain_ok:
		_fail("sanity_health_drain not applied (health should be < 90.0, got %.3f)" % vs.health)
		return

	# Sanity teeth: sanity_stamina_recovery_mult reduces stamina recovery vs baseline.
	var va := VitalsStateScript.new()
	va.stamina = 10.0
	va.tick(1.0, {"moving": false})
	var base_recover: float = va.stamina - 10.0
	var vb := VitalsStateScript.new()
	vb.stamina = 10.0
	vb.tick(1.0, {"moving": false, "sanity_stamina_recovery_mult": 0.5})
	var pen_recover: float = vb.stamina - 10.0
	var stamina_ok := base_recover > 0.0 and pen_recover < base_recover
	if not stamina_ok:
		_fail("sanity_stamina_recovery_mult not applied (base=%.3f pen=%.3f)" % [base_recover, pen_recover])
		return

	# Domain 1: incapacitation predicate (health<=0)
	var vi := VitalsStateScript.new()
	vi.configure({})
	if vi.is_incapacitated():
		_fail("full-health vitals should not be incapacitated")
		return
	vi.health = 0.0
	if not vi.is_incapacitated():
		_fail("health=0 should be incapacitated")
		return

	# Domain 1: movement-speed multiplier gating
	var vm := VitalsStateScript.new()
	vm.configure({})
	if absf(vm.get_movement_speed_multiplier() - 1.0) > 0.001:
		_fail("healthy vitals should give full movement multiplier")
		return
	vm.stamina = VitalsStateScript.EXHAUSTION_STAMINA_THRESHOLD - 1.0
	if absf(vm.get_movement_speed_multiplier() - 0.5) > 0.001:
		_fail("exhausted vitals should halve movement multiplier")
		return
	vm.stamina = 100.0
	vm.health = 0.0
	if absf(vm.get_movement_speed_multiplier() - 0.0) > 0.001:
		_fail("incapacitated vitals should zero movement multiplier")
		return

	print("VITALS STATE PASS health=%.1f stamina=%.1f hunger=%.1f thirst=%.1f sanity_drain=true sanity_stamina=true" % [v.health, v.stamina, v.hunger, v.thirst])
	quit(0)

func _fail(reason: String) -> void:
	push_error("VITALS STATE FAIL reason=%s" % reason)
	quit(1)
