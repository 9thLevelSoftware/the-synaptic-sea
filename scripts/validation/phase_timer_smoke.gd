extends SceneTree

## Tranche 3 (audit M finding): PhaseTimer — the ADR-0005 shared helper every
## timer hazard composes — had ZERO direct behavior tests. The bundled
## hazard_contract_smoke only asserts it carries no HAZARD_KIND; its tick /
## boundary / progress math was untested (only exercised transitively through
## ElectricalArcState).
##
## Pure-model smoke. Pass marker:
## PHASE TIMER PASS clamp=true boundary=true carry=true single_flip=true progress=true durations=true

const PhaseTimerScript := preload("res://scripts/systems/phase_timer.gd")

func _initialize() -> void:
	# --- 1. configure clamps zero/negative/non-numeric to MINIMUM (0.1) ---
	var t = PhaseTimerScript.new()
	t.configure({"A": 0.0, "B": -5.0})
	if t.current_phase() != PhaseTimerScript.Phase.A:
		_fail("configure must reset to Phase.A")
		return
	if t.current_phase_duration() != PhaseTimerScript.MINIMUM_PHASE_DURATION:
		_fail("A duration 0.0 not clamped to minimum (got %f)" % t.current_phase_duration())
		return
	# Flip to B (0.1s) and confirm the negative B duration clamped too.
	t.tick(PhaseTimerScript.MINIMUM_PHASE_DURATION)
	if t.current_phase() != PhaseTimerScript.Phase.B:
		_fail("clamp check: expected flip to B at minimum duration")
		return
	if t.current_phase_duration() != PhaseTimerScript.MINIMUM_PHASE_DURATION:
		_fail("B duration -5.0 not clamped to minimum (got %f)" % t.current_phase_duration())
		return
	var non_numeric = PhaseTimerScript.new()
	non_numeric.configure({"A": "fast", "B": null})
	if non_numeric.current_phase_duration() != PhaseTimerScript.MINIMUM_PHASE_DURATION:
		_fail("non-numeric duration not clamped to minimum")
		return

	# --- 2. Boundary: flips exactly AT the duration, not before -----------
	var b = PhaseTimerScript.new()
	b.configure({"A": 2.0, "B": 3.0})
	if b.tick(1.9):
		_fail("flipped 0.1s before the A boundary")
		return
	if b.current_phase() != PhaseTimerScript.Phase.A:
		_fail("left Phase.A before the boundary")
		return
	if not b.tick(0.1):
		_fail("did not flip exactly at the A boundary")
		return
	if b.current_phase() != PhaseTimerScript.Phase.B:
		_fail("phase not B after the boundary flip")
		return
	if absf(b.get_time_in_phase()) > 0.0001:
		_fail("exact-boundary flip should carry zero remainder (got %f)" % b.get_time_in_phase())
		return

	# --- 3. Remainder carry: overshoot rolls into the next phase ----------
	var c = PhaseTimerScript.new()
	c.configure({"A": 2.0, "B": 3.0})
	if not c.tick(2.5):
		_fail("overshoot tick did not flip")
		return
	if absf(c.get_time_in_phase() - 0.5) > 0.0001:
		_fail("remainder not carried: expected 0.5 in B, got %f" % c.get_time_in_phase())
		return

	# --- 4. At most ONE flip per tick, even for an oversized delta --------
	var s = PhaseTimerScript.new()
	s.configure({"A": 1.0, "B": 1.0})
	s.tick(10.0)  # one flip only: A -> B with 9.0 carried
	if s.current_phase() != PhaseTimerScript.Phase.B:
		_fail("oversized tick must flip exactly once (A -> B)")
		return
	if absf(s.get_time_in_phase() - 9.0) > 0.0001:
		_fail("oversized tick carry wrong: expected 9.0, got %f" % s.get_time_in_phase())
		return
	# Non-positive deltas are no-ops.
	if s.tick(0.0) or s.tick(-1.0):
		_fail("non-positive delta must be a no-op")
		return

	# --- 5. normalized_progress: 0 -> fraction -> capped at 1.0 -----------
	var p = PhaseTimerScript.new()
	p.configure({"A": 4.0, "B": 1.0})
	if p.normalized_progress() != 0.0:
		_fail("fresh timer progress should be 0.0")
		return
	p.tick(1.0)
	if absf(p.normalized_progress() - 0.25) > 0.0001:
		_fail("progress after 1/4 duration should be 0.25 (got %f)" % p.normalized_progress())
		return
	# Oversized tick leaves carried time_in_phase (2.0) > B duration (1.0);
	# progress must cap at 1.0 (the save/load mid-phase guard).
	p.tick(5.0)  # flips to B, carries 2.0
	if p.normalized_progress() != 1.0:
		_fail("carried-overshoot progress must cap at 1.0 (got %f)" % p.normalized_progress())
		return

	# --- 6. current_phase_duration tracks the active phase ----------------
	var d = PhaseTimerScript.new()
	d.configure({"A": 2.0, "B": 7.0})
	if d.current_phase_duration() != 2.0:
		_fail("A-phase duration wrong")
		return
	d.tick(2.0)
	if d.current_phase_duration() != 7.0:
		_fail("B-phase duration wrong after flip")
		return

	print("PHASE TIMER PASS clamp=true boundary=true carry=true single_flip=true progress=true durations=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PHASE TIMER FAIL reason=%s" % reason)
	quit(1)
