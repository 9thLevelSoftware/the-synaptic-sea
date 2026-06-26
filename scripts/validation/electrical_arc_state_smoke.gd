extends SceneTree
# REQ-013 direct model smoke for the electrical-arc hazard.
# Mirrors fire_state_smoke.gd: advances the cycle through two full
# DISCHARGED -> ARCING -> DISCHARGED -> ARCING -> DISCHARGED rounds
# and asserts the phase counts and passability transitions called out
# in docs/game/features/hazard_type_3.md.
#
# Pass marker: ARC STATE PASS cycles=2 phases=4 passability_switches=4
#
# Headless:
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#     --path /Users/christopherwilloughby/the-synapse-sea-of-stars
#     --script res://scripts/validation/electrical_arc_state_smoke.gd

func _initialize() -> void:
	var model := ElectricalArcState.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary
	# keyed by the model fields. ElectricalArcState reads zone_ids,
	# arcing_duration, and discharged_duration. It owns a PhaseTimer
	# instance internally and translates its Phase.A/B output into
	# DISCHARGED/ARCING.
	model.configure({
		"zone_ids": ["side_corridor_arc"],
		"arcing_duration": ElectricalArcState.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcState.DEFAULT_DISCHARGED_DURATION,
	})

	var initial: Dictionary = model.get_summary()
	if str(initial.get("state", "")) != "DISCHARGED":
		_fail("initial state should be DISCHARGED, got %s" % str(initial.get("state", "")))
		return
	if str(initial.get("hazard_kind", "")) != "electrical_arc":
		_fail("initial hazard_kind should be electrical_arc, got %s" % str(initial.get("hazard_kind", "")))
		return
	if float(initial.get("time_in_state", -1.0)) != 0.0:
		_fail("initial time_in_state should be 0.0, got %s" % str(initial.get("time_in_state", -1.0)))
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	if bool(initial.get("arcing", true)):
		_fail("initial arcing should be false")
		return
	if not model.has_method("is_passability_blocked") or model.is_passability_blocked():
		_fail("initial is_passability_blocked should be false")
		return

	var cycles: int = 0
	var phases: int = 0
	var passability_switches: int = 0
	var last_blocked: bool = model.is_passability_blocked()
	var last_phase: int = int(initial.get("phase", 0))

	# Advance through two full cycles:
	# DISCHARGED -> ARCING -> DISCHARGED -> ARCING -> DISCHARGED.
	while cycles < 2:
		var before: Dictionary = model.get_summary()
		var before_phase: int = int(before.get("phase", 0))
		var remaining: float = float(before.get("remaining_in_state", 0.0))
		if remaining <= 0.0:
			remaining = float(before.get("arcing_duration" if before_phase == 1 else "discharged_duration", 0.0))
		# Tick exactly the remaining time to force a phase transition.
		model.tick(remaining)
		var after: Dictionary = model.get_summary()
		var after_phase: int = int(after.get("phase", 0))
		if after_phase != before_phase:
			phases += 1
			last_phase = after_phase
		var after_blocked: bool = bool(after.get("passability_blocked", false))
		if after_blocked != last_blocked:
			passability_switches += 1
			last_blocked = after_blocked
		# Count a completed cycle when we return to DISCHARGED from ARCING.
		if before_phase == 1 and after_phase == 0:
			cycles += 1

	var final: Dictionary = model.get_summary()
	if str(final.get("state", "")) != "DISCHARGED":
		_fail("after two cycles state should be DISCHARGED, got %s" % str(final.get("state", "")))
		return
	if cycles != 2:
		_fail("expected 2 cycles, got %d" % cycles)
		return
	if phases != 4:
		_fail("expected 4 phase transitions, got %d" % phases)
		return
	if passability_switches != 4:
		_fail("expected 4 passability switches, got %d" % passability_switches)
		return
	if bool(final.get("passability_blocked", true)):
		_fail("final passability_blocked should be false in DISCHARGED")
		return

	# Status lines must include an Arc line and reflect the current phase.
	var lines: PackedStringArray = model.get_status_lines()
	var found_arc: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Arc:"):
			found_arc = true
			break
	if not found_arc:
		_fail("status lines missing Arc: line")
		return

	# Round-trip the model summary and prove apply_summary accepts the
	# same kind and rejects a different kind (per ADR-0005 contract).
	var saved: Dictionary = final.duplicate(true)
	var restored := ElectricalArcState.new()
	if not restored.apply_summary(saved):
		_fail("apply_summary rejected a same-kind summary")
		return
	var restored_summary: Dictionary = restored.get_summary()
	if str(restored_summary.get("state", "")) != str(final.get("state", "")):
		_fail("apply_summary lost the phase across round-trip")
		return
	var wrong_kind: Dictionary = {"hazard_kind": "oxygen"}
	if restored.apply_summary(wrong_kind):
		_fail("apply_summary accepted a wrong-kind summary (must reject)")
		return

	# Final summary must include the keys called out in the spec.
	for key in ["hazard_kind", "state", "phase", "time_in_state", "cycle_duration", "arcing", "passability_blocked", "arcing_duration", "discharged_duration", "zone_ids"]:
		if not final.has(key):
			_fail("final summary missing key: %s" % key)
			return

	print("ARC STATE PASS cycles=%d phases=%d passability_switches=%d" % [cycles, phases, passability_switches])
	quit(0)

func _fail(reason: String) -> void:
	push_error("ARC STATE FAIL reason=%s" % reason)
	quit(1)
