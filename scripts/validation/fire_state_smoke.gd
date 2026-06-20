extends SceneTree

func _initialize() -> void:
	var model := FireState.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary
	# keyed by the model fields. FireState reads zone_ids, burn_duration,
	# and clear_duration. It owns a PhaseTimer instance internally and
	# translates its Phase.A/B output into CLEARED/BURNING.
	model.configure({
		"zone_ids": ["side_corridor_fire"],
		"burn_duration": 4.0,
		"clear_duration": 3.0,
	})

	var initial: Dictionary = model.get_summary()
	if str(initial.get("hazard_kind", "")) != "fire":
		_fail("initial hazard_kind should be fire, got %s" % str(initial.get("hazard_kind", "")))
		return
	if str(initial.get("state", "")) != "CLEARED":
		_fail("initial state should be CLEARED, got %s" % str(initial.get("state", "")))
		return
	if float(initial.get("time_in_state", -1.0)) != 0.0:
		_fail("initial time_in_state should be 0.0, got %s" % str(initial.get("time_in_state", -1.0)))
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	if bool(initial.get("burning", true)):
		_fail("initial burning should be false")
		return
	if not model.has_method("is_passability_blocked") or model.is_passability_blocked():
		_fail("initial is_passability_blocked should be false")
		return

	var cycles: int = 0
	var phases: int = 0
	var passability_switches: int = 0
	var last_blocked: bool = model.is_passability_blocked()
	var last_phase: int = int(initial.get("phase", 0))

	# Advance through two full cycles: CLEARED -> BURNING -> CLEARED -> BURNING -> CLEARED.
	while cycles < 2:
		var before: Dictionary = model.get_summary()
		var before_phase: int = int(before.get("phase", 0))
		var remaining: float = float(before.get("remaining_in_state", 0.0))
		if remaining <= 0.0:
			remaining = float(before.get("burn_duration" if before_phase == 1 else "clear_duration", 0.0))
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
		# Count a completed cycle when we return to CLEARED from BURNING.
		if before_phase == 1 and after_phase == 0:
			cycles += 1

	var final: Dictionary = model.get_summary()
	if str(final.get("state", "")) != "CLEARED":
		_fail("after two cycles state should be CLEARED, got %s" % str(final.get("state", "")))
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
		_fail("final passability_blocked should be false in CLEARED")
		return

	# Status lines must include a Fire line.
	var lines: PackedStringArray = model.get_status_lines()
	var found_fire: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Fire:"):
			found_fire = true
			break
	if not found_fire:
		_fail("status lines missing Fire: line")
		return

	# Final summary must include the keys called out in the spec.
	for key in ["hazard_kind", "state", "phase", "time_in_state", "cycle_duration", "burning", "passability_blocked", "burn_duration", "clear_duration", "zone_ids"]:
		if not final.has(key):
			_fail("final summary missing key: %s" % key)
			return

	print("FIRE STATE PASS cycles=%d phases=%d passability_switches=%d" % [cycles, phases, passability_switches])
	quit(0)

func _fail(reason: String) -> void:
	push_error("FIRE STATE FAIL reason=%s" % reason)
	quit(1)
