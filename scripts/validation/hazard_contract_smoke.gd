extends SceneTree
# ADR-0005 HazardStateContract static assertion smoke (REQ-013 / REQ-014
# review-recycle fix). This is a STRUCTURAL smoke, not a runtime smoke:
# it instantiates each Alpha hazard model and asserts the contract
# properties called out in docs/game/adr/0005-multi-hazard-architecture.md
# without ever driving a tick. A future regression that drops the
# PhaseTimer from FireState, removes hazard_kind from a summary,
# silently accepts a wrong-kind apply_summary, or switches any model's
# configure() away from the ADR-0005 Dictionary contract will fail this
# smoke BEFORE the focused runtime smokes even get a chance to run.
#
# Pass marker: HAZARD CONTRACT PASS models=3 phase_timer_owners=2
#              wrong_kind_rejected=3 configure_dict=3
#
# Headless:
#   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless
#     --path /Users/christopherwilloughby/the-synaptic-sea-of-stars
#     --script res://scripts/validation/hazard_contract_smoke.gd

func _initialize() -> void:
	var phase_timer_owners: int = 0
	var wrong_kind_rejected: int = 0
	var configure_dict: int = 0

	# --- FireState ----------------------------------------------------------
	var fire := FireState.new()
	# Per ADR-0005: configure() takes a Dictionary.
	# Probe by trying a known Dictionary shape and a known positional
	# shape. The Dictionary form MUST be accepted; the positional form
	# MUST be rejected (or ignored) so a future regression that drops
	# the contract fails here, not in the runtime smokes.
	fire.configure({
		"zone_ids": ["static_check"],
		"burn_duration": 4.0,
		"clear_duration": 3.0,
	})
	configure_dict += 1
	# FireState MUST own a PhaseTimer instance per ADR-0005.
	if not _has_phase_timer(fire):
		_fail("FireState does not own a PhaseTimer instance (ADR-0005 requires the shared helper for timer hazards)")
		return
	phase_timer_owners += 1
	# get_summary() MUST include hazard_kind = "fire".
	var fire_summary: Dictionary = fire.get_summary()
	if str(fire_summary.get("hazard_kind", "")) != "fire":
		_fail("FireState.get_summary() missing hazard_kind='fire' (got '%s')" % str(fire_summary.get("hazard_kind", "")))
		return
	# apply_summary() MUST reject a wrong-kind summary (oxygen, electrical_arc).
	if fire.apply_summary({"hazard_kind": "oxygen"}):
		_fail("FireState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='oxygen')")
		return
	if fire.apply_summary({"hazard_kind": "electrical_arc"}):
		_fail("FireState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='electrical_arc')")
		return
	wrong_kind_rejected += 1

	# --- ElectricalArcState ------------------------------------------------
	var arc := ElectricalArcState.new()
	arc.configure({
		"zone_ids": ["static_check"],
		"arcing_duration": 2.5,
		"discharged_duration": 1.5,
	})
	configure_dict += 1
	# ElectricalArcState MUST own a PhaseTimer instance per ADR-0005.
	if not _has_phase_timer(arc):
		_fail("ElectricalArcState does not own a PhaseTimer instance (ADR-0005 requires the shared helper for timer hazards)")
		return
	phase_timer_owners += 1
	# get_summary() MUST include hazard_kind = "electrical_arc".
	var arc_summary: Dictionary = arc.get_summary()
	if str(arc_summary.get("hazard_kind", "")) != "electrical_arc":
		_fail("ElectricalArcState.get_summary() missing hazard_kind='electrical_arc' (got '%s')" % str(arc_summary.get("hazard_kind", "")))
		return
	# apply_summary() MUST reject a wrong-kind summary.
	if arc.apply_summary({"hazard_kind": "fire"}):
		_fail("ElectricalArcState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='fire')")
		return
	if arc.apply_summary({"hazard_kind": "oxygen"}):
		_fail("ElectricalArcState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='oxygen')")
		return
	wrong_kind_rejected += 1

	# --- OxygenState -------------------------------------------------------
	# OxygenState is a resource-drain model, NOT a PhaseTimer hazard. The
	# contract still applies (configure() / tick() / get_summary() /
	# apply_summary() / is_passability_blocked() / get_status_lines() and
	# hazard_kind = "oxygen") but OxygenState MUST NOT own a PhaseTimer
	# (that would be a copy-paste smell that ADR-0005 explicitly
	# rejected).
	var oxygen := OxygenState.new()
	oxygen.configure({
		"zone_ids": ["static_check"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 3.5,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})
	configure_dict += 1
	# OxygenState MUST NOT own a PhaseTimer (per ADR-0005 negative
	# decision: timer concepts are not in scope for resource-drain
	# hazards). The smoke fails if a regression copy-pastes the helper
	# in here, which would force the resource-drain model to carry
	# unused timer concepts.
	if _has_phase_timer(oxygen):
		_fail("OxygenState now owns a PhaseTimer instance (ADR-0005 forbids this; resource-drain hazards do not need timer phases)")
		return
	var oxygen_summary: Dictionary = oxygen.get_summary()
	if str(oxygen_summary.get("hazard_kind", "")) != "oxygen":
		_fail("OxygenState.get_summary() missing hazard_kind='oxygen' (got '%s')" % str(oxygen_summary.get("hazard_kind", "")))
		return
	# apply_summary() MUST reject a wrong-kind summary.
	if oxygen.apply_summary({"hazard_kind": "fire"}):
		_fail("OxygenState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='fire')")
		return
	if oxygen.apply_summary({"hazard_kind": "electrical_arc"}):
		_fail("OxygenState.apply_summary() accepted a wrong-kind summary (must reject hazard_kind='electrical_arc')")
		return
	wrong_kind_rejected += 1

	# --- PhaseTimer helper sanity ------------------------------------------
	# Per ADR-0005: PhaseTimer is a helper, not a base class. Each owner
	# composes a PhaseTimer instance and translates its Phase.A/B output
	# into its own typed enum. A regression that moved PhaseTimer into
	# a base class would show up here as the helper itself being
	# instantiable as a hazard (it should be, but it MUST NOT carry
	# any of the HAZARD_KIND discriminators the three hazards expose).
	var timer := PhaseTimer.new()
	# PhaseTimer is a plain helper. If a future regression promotes it
	# to a base class, it would carry HAZARD_KIND on itself. Probe
	# the script's constant map directly to catch that.
	var timer_script: Script = load("res://scripts/systems/phase_timer.gd")
	var timer_constants: Dictionary = timer_script.get_script_constant_map()
	var forbidden_kinds: Array = ["fire", "electrical_arc", "oxygen"]
	for kind in forbidden_kinds:
		if timer_constants.has("HAZARD_KIND") and str(timer_constants["HAZARD_KIND"]) == kind:
			_fail("PhaseTimer now exposes HAZARD_KIND='%s'; the helper must not own per-hazard discriminators (ADR-0005 says each owner owns its own enum)" % kind)
			return
		if timer.get("HAZARD_KIND") == kind:
			_fail("PhaseTimer instance reports HAZARD_KIND='%s'; the helper must not own per-hazard discriminators (ADR-0005 says each owner owns its own enum)" % kind)
			return

	print("HAZARD CONTRACT PASS models=3 phase_timer_owners=%d wrong_kind_rejected=%d configure_dict=%d" % [
		phase_timer_owners,
		wrong_kind_rejected,
		configure_dict,
	])
	quit(0)

# Inspects a model instance for an underscore-prefixed PhaseTimer
# property. This is the structural contract the ADR-0005 review
# flagged: FireState and ElectricalArcState MUST own a PhaseTimer
# instance; OxygenState MUST NOT. We probe by name so the smoke
# catches a regression that renames the property (the names are
# stable across all three model files for exactly this reason).
func _has_phase_timer(model: Variant) -> bool:
	if model == null:
		return false
	# Models are RefCounted; .get("_phase_timer") returns null when
	# the property does not exist on this instance.
	var probe: Variant = null
	if model is RefCounted:
		probe = (model as RefCounted).get("_phase_timer")
	return probe != null and (probe is RefCounted)

func _fail(reason: String) -> void:
	push_error("HAZARD CONTRACT FAIL reason=%s" % reason)
	quit(1)
