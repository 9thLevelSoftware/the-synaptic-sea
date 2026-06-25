extends SceneTree

## Pure-model smoke for the player-vitals HUD formatting (Phase 7 sub-project C):
## PlayerVitalsModel turns oxygen/inventory/repair state into ASCII status lines,
## including the ADR-0024 suit contribution, the Encumbrance Heavy-Load penalty,
## and the transient repair-blocked message (delta-driven clear).

const VitalsModelScript := preload("res://scripts/systems/player_vitals_model.gd")

func _initialize() -> void:
	var m = VitalsModelScript.new()

	# Oxygen open + suit worn -> Oxygen line with (BREACH) + Suit -25% line.
	m.apply_oxygen_summary({
		"oxygen": 87.0,
		"breach_open": true,
		"breach_sealed": false,
		"recovery_threshold": 30.0,
		"equipment_drain_multiplier": 0.75,
	})
	m.apply_inventory_load(0.78, 1.0)
	var lines: PackedStringArray = m.get_status_lines()
	if not _has(lines, "Oxygen: 87 (BREACH)"):
		_fail("expected 'Oxygen: 87 (BREACH)', got %s" % str(lines))
		return
	if not _has(lines, "Suit: -25% O2 drain"):
		_fail("expected suit line, got %s" % str(lines))
		return
	if not _has(lines, "Load: 78%"):
		_fail("expected 'Load: 78%%', got %s" % str(lines))
		return
	if _has_prefix(lines, "Repairing") or _has_prefix(lines, "Repair blocked"):
		_fail("no repair line expected when idle, got %s" % str(lines))
		return

	var vs: Dictionary = m.get_vitals_summary()
	if int(vs.get("oxygen", -1)) != 87:
		_fail("vitals_summary oxygen should be 87, got %s" % str(vs.get("oxygen")))
		return
	if String(vs.get("breach_state", "")) != "breach":
		_fail("vitals_summary breach_state should be 'breach', got %s" % str(vs.get("breach_state")))
		return
	if int(vs.get("suit_drain_percent", -1)) != 25:
		_fail("vitals_summary suit_drain_percent should be 25, got %s" % str(vs.get("suit_drain_percent")))
		return
	if int(vs.get("load_percent", -1)) != 78:
		_fail("vitals_summary load_percent should be 78, got %s" % str(vs.get("load_percent")))
		return
	if bool(vs.get("heavy", true)) != false:
		_fail("vitals_summary heavy should be false at load 0.78, got %s" % str(vs.get("heavy")))
		return

	# Sealed breach -> (SEALED), and no suit line when the multiplier is neutral.
	m.apply_oxygen_summary({
		"oxygen": 87.0, "breach_open": true, "breach_sealed": true,
		"recovery_threshold": 30.0, "equipment_drain_multiplier": 1.0,
	})
	lines = m.get_status_lines()
	if not _has(lines, "Oxygen: 87 (SEALED)"):
		_fail("expected '(SEALED)', got %s" % str(lines))
		return
	if _has(lines, "Suit: -25% O2 drain"):
		_fail("no suit line expected at equipment_drain_multiplier==1.0, got %s" % str(lines))
		return

	# Low oxygen -> LOW suffix at/under the recovery threshold.
	m.apply_oxygen_summary({
		"oxygen": 20.0, "breach_open": false, "breach_sealed": false,
		"recovery_threshold": 30.0, "equipment_drain_multiplier": 1.0,
	})
	if not _has(m.get_status_lines(), "Oxygen: 20 LOW"):
		_fail("expected 'Oxygen: 20 LOW', got %s" % str(m.get_status_lines()))
		return

	# Inclusive boundary: oxygen == recovery_threshold should also show LOW.
	m.apply_oxygen_summary({
		"oxygen": 30.0, "breach_open": false, "breach_sealed": false,
		"recovery_threshold": 30.0, "equipment_drain_multiplier": 1.0,
	})
	if not _has(m.get_status_lines(), "Oxygen: 30 LOW"):
		_fail("expected 'Oxygen: 30 LOW' at boundary oxygen==recovery_threshold, got %s" % str(m.get_status_lines()))
		return

	# Heavy load -> HEAVY with the move penalty.
	m.apply_inventory_load(1.12, 0.70)
	if not _has(m.get_status_lines(), "Load: 112% HEAVY (-30% move)"):
		_fail("expected Heavy-Load line, got %s" % str(m.get_status_lines()))
		return

	# Repair channeling -> Repairing N%.
	m.set_repair_progress(true, 0.47)
	if not _has(m.get_status_lines(), "Repairing 47%"):
		_fail("expected 'Repairing 47%%', got %s" % str(m.get_status_lines()))
		return

	# An active channel supersedes a stale block.
	m.notify_repair_blocked("missing_parts")
	if not _has(m.get_status_lines(), "Repairing 47%"):
		_fail("active channel should supersede a block, got %s" % str(m.get_status_lines()))
		return

	# Stop channeling -> the blocked message shows (within the display window).
	m.set_repair_progress(false, 0.0)
	if not _has(m.get_status_lines(), "Repair blocked: missing parts"):
		_fail("expected blocked line, got %s" % str(m.get_status_lines()))
		return

	# Tick past the display window -> the blocked line clears.
	m.tick(VitalsModelScript.BLOCKED_DISPLAY_SECONDS + 0.1)
	if _has_prefix(m.get_status_lines(), "Repair blocked"):
		_fail("blocked line should clear after the display window, got %s" % str(m.get_status_lines()))
		return

	# --- per-container weight reduction marker (slice D) ---
	m.apply_inventory_load(0.56, 1.0, 13.2)
	if not _has(m.get_status_lines(), "Load: 56% (bags -13kg)"):
		_fail("expected bag-reduction marker, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(1.40, 0.70, 13.2)
	if not _has(m.get_status_lines(), "Load: 140% HEAVY (-30% move) (bags -13kg)"):
		_fail("expected heavy + bag marker, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(0.56, 1.0, 0.0)
	if not _has(m.get_status_lines(), "Load: 56%"):
		_fail("expected no marker at zero reduction, got %s" % str(m.get_status_lines()))
		return
	m.apply_inventory_load(0.56, 1.0, 0.4)   # rounds to 0 -> no marker
	if not _has(m.get_status_lines(), "Load: 56%"):
		_fail("sub-1kg reduction should not show a marker, got %s" % str(m.get_status_lines()))
		return

	print("PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47")
	quit(0)

func _has(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if String(line) == needle:
			return true
	return false

func _has_prefix(lines: PackedStringArray, prefix: String) -> bool:
	for line in lines:
		if String(line).begins_with(prefix):
			return true
	return false

func _fail(reason: String) -> void:
	push_error("PLAYER VITALS MODEL SMOKE FAIL reason=%s" % reason)
	quit(1)
