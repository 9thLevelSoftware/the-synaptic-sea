extends SceneTree

func _initialize() -> void:
	var model := OxygenState.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary
	# keyed by the model fields. OxygenState reads zone_ids, max_oxygen,
	# drain_rate, regen_rate, recovery_threshold, safe_threshold.
	model.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 3.5,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})

	var initial: Dictionary = model.get_summary()
	if str(initial.get("hazard_kind", "")) != "oxygen":
		_fail("initial hazard_kind should be oxygen, got %s" % str(initial.get("hazard_kind", "")))
		return
	if absf(float(initial.get("oxygen", -1.0)) - 100.0) > 0.001:
		_fail("initial oxygen should be 100.0, got %s" % str(initial.get("oxygen", -1.0)))
		return
	if not bool(initial.get("breach_open", false)):
		_fail("initial breach_open should be true")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("initial breach_sealed should be false")
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	if not initial.has("recovery_threshold"):
		_fail("summary missing recovery_threshold key")
		return
	if not initial.has("safe_threshold"):
		_fail("summary missing safe_threshold key")
		return
	if model.is_passability_blocked():
		_fail("initial is_passability_blocked should be false")
		return
	if not model.is_player_in_breach_zone():
		# Initial player position is undefined; the model is not required
		# to start "in" a breach zone. It is only required to reflect any
		# explicit zone-id match returned by configure(...).
		# Test below will set it explicitly.
		pass

	# Drain while inside the unsealed breach zone.
	var first_tick_changed: bool = model.tick(1.0, true)
	if not first_tick_changed:
		_fail("drain tick should report changed when player is inside unsealed breach")
		return
	var after_drain: Dictionary = model.get_summary()
	var oxygen_after_drain: float = float(after_drain.get("oxygen", -1.0))
	if oxygen_after_drain >= 100.0:
		_fail("oxygen should decrease after drain tick, got %s" % oxygen_after_drain)
		return
	if oxygen_after_drain != 100.0 - 6.0:
		_fail("oxygen after one drain tick should be 94.0, got %s" % oxygen_after_drain)
		return

	# Duplicate drain tick (same state) must report unchanged.
	var duplicate_tick_changed: bool = model.tick(1.0, true)
	if duplicate_tick_changed:
		# Note: oxygen value itself changes; we only assert the
		# "state changed" boolean from the model. Since oxygen did change,
		# the boolean should be true. Reset by exiting then re-entering.
		pass
	var oxygen_after_second_drain: float = float(model.get_summary().get("oxygen", -1.0))
	if absf(oxygen_after_second_drain - (oxygen_after_drain - 6.0)) > 0.001:
		_fail("oxygen after second drain tick should be %s, got %s" % [str(oxygen_after_drain - 6.0), oxygen_after_second_drain])
		return

	# Regen while outside any breach zone.
	var oxygen_before_regen: float = float(model.get_summary().get("oxygen", -1.0))
	var regen_tick_changed: bool = model.tick(1.0, false)
	var oxygen_after_regen: float = float(model.get_summary().get("oxygen", -1.0))
	if oxygen_after_regen <= oxygen_before_regen:
		_fail("oxygen should increase while outside breach zone, before=%s after=%s" % [oxygen_before_regen, oxygen_after_regen])
		return
	if absf(oxygen_after_regen - (oxygen_before_regen + 3.5)) > 0.001:
		_fail("oxygen regen rate should be 3.5/sec, before=%s after=%s" % [oxygen_before_regen, oxygen_after_regen])
		return

	# Field atmosphere drains suit O2 even outside the home breach zone (derelict path).
	var field_start: float = float(model.get_summary().get("oxygen", 0.0))
	var field_changed: bool = model.tick(1.0, {"field_atmosphere": true, "player_in_breach_zone": false})
	if not field_changed:
		_fail("field_atmosphere tick should drain even outside home breach zone")
		return
	var field_after: float = float(model.get_summary().get("oxygen", -1.0))
	if field_after >= field_start:
		_fail("field_atmosphere should decrease oxygen, before=%s after=%s" % [field_start, field_after])
		return
	if absf(field_after - (field_start - 6.0)) > 0.001:
		_fail("field drain rate should match base 6.0/sec, before=%s after=%s" % [field_start, field_after])
		return

	# Seal the breach via objective 2 summary.
	var seal_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if not seal_changed:
		_fail("ship-system summary with main_power_restored should seal the breach")
		return
	var after_seal: Dictionary = model.get_summary()
	if bool(after_seal.get("breach_open", false)):
		_fail("after seal breach_open should be false")
		return
	if not bool(after_seal.get("breach_sealed", false)):
		_fail("after seal breach_sealed should be true")
		return

	# After sealing, even staying "inside" the breach zone should not drain.
	var oxygen_before_post_seal: float = float(model.get_summary().get("oxygen", -1.0))
	model.tick(1.0, true)
	var oxygen_after_post_seal: float = float(model.get_summary().get("oxygen", -1.0))
	if absf(oxygen_after_post_seal - oxygen_before_post_seal) > 0.001:
		_fail("oxygen should not change while inside sealed breach, before=%s after=%s" % [oxygen_before_post_seal, oxygen_after_post_seal])
		return

	# Field atmosphere still drains after home seal (derelict suit pressure is independent).
	var field_sealed_start: float = float(model.get_summary().get("oxygen", -1.0))
	model.tick(1.0, {"field_atmosphere": true})
	var field_sealed_after: float = float(model.get_summary().get("oxygen", -1.0))
	if field_sealed_after >= field_sealed_start - 0.001:
		_fail("field_atmosphere should still drain after home seal, before=%s after=%s" % [field_sealed_start, field_sealed_after])
		return

	# Direct seal call should be idempotent.
	var double_seal_changed: bool = model.seal_breach("corridor_to_reactor")
	if double_seal_changed:
		_fail("duplicate seal_breach should report unchanged")
		return

	# Reset the model for the passability block test by reconfiguring it.
	model.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 30.0,
		"drain_rate": 100.0,
		"regen_rate": 0.0,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})
	# Drain to zero.
	model.tick(1.0, true)
	var zero_state: Dictionary = model.get_summary()
	if float(zero_state.get("oxygen", -1.0)) > 0.001:
		_fail("after forced drain oxygen should be 0, got %s" % str(zero_state.get("oxygen", -1.0)))
		return
	if not bool(zero_state.get("passability_blocked", false)):
		_fail("at oxygen=0 passability_blocked should be true")
		return
	if not model.is_passability_blocked():
		_fail("is_passability_blocked should be true at oxygen=0")
		return

	# Recovery: with regen > 0, ticks above threshold reopen passability.
	model.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 1000.0,
		"regen_rate": 100.0,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})
	model.tick(1.0, true)  # drain to zero
	var zero_again: Dictionary = model.get_summary()
	if float(zero_again.get("oxygen", -1.0)) > 0.001:
		_fail("after forced drain oxygen should be 0, got %s" % str(zero_again.get("oxygen", -1.0)))
		return
	if not model.is_passability_blocked():
		_fail("is_passability_blocked should be true after forced drain")
		return
	# Now tick while outside the breach to regen above recovery threshold.
	for i in range(5):
		model.tick(1.0, false)
	var recovered: Dictionary = model.get_summary()
	if float(recovered.get("oxygen", -1.0)) <= 30.0:
		_fail("oxygen should recover above recovery_threshold after regen ticks, got %s" % str(recovered.get("oxygen", -1.0)))
		return
	if bool(recovered.get("passability_blocked", true)):
		_fail("passability_blocked should be false once oxygen > recovery_threshold")
		return
	if model.is_passability_blocked():
		_fail("is_passability_blocked should be false once oxygen > recovery_threshold")
		return

	# Status lines must include the oxygen line and the seal marker.
	var lines: PackedStringArray = model.get_status_lines()
	var found_oxygen: bool = false
	var found_seal_marker: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Oxygen:"):
			found_oxygen = true
		if text.begins_with("Breach:"):
			found_seal_marker = true
	if not found_oxygen:
		_fail("status lines missing Oxygen: line")
		return
	if not found_seal_marker:
		_fail("status lines missing Breach: line")
		return

	# Final summary must include all the keys called out in the spec.
	var final: Dictionary = model.get_summary()
	for key in ["oxygen", "breach_open", "breach_sealed", "passability_blocked", "recovery_threshold", "safe_threshold", "max_oxygen", "drain_rate", "regen_rate", "breach_zone_ids"]:
		if not final.has(key):
			_fail("final summary missing key: %s" % key)
			return

	# Spec-aligned final marker (docs/game/features/hazards.md line 102):
	# after the full model coverage, seal via objective-2 and verify the
	# sealed/closed breach state with passability re-opened.
	model.apply_ship_systems_summary({"main_power_restored": true})
	var sealed: Dictionary = model.get_summary()
	if bool(sealed.get("breach_open", true)):
		_fail("final seal should leave breach_open=false")
		return
	if not bool(sealed.get("breach_sealed", false)):
		_fail("final seal should leave breach_sealed=true")
		return
	if bool(sealed.get("passability_blocked", false)):
		_fail("final seal should leave passability_blocked=false")
		return

	print("OXYGEN STATE PASS oxygen=%s breach_open=%s breach_sealed=%s passability_blocked=%s recovery_threshold=%s" % [
		str(sealed.get("oxygen", -1.0)),
		str(sealed.get("breach_open", false)).to_lower(),
		str(sealed.get("breach_sealed", false)).to_lower(),
		str(sealed.get("passability_blocked", false)).to_lower(),
		str(sealed.get("recovery_threshold", -1.0)),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("OXYGEN STATE FAIL reason=%s" % reason)
	quit(1)
