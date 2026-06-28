extends RefCounted
class_name PhaseTimer

## ADR-0005 shared phase-timer helper for Alpha timer hazards.
## PhaseTimer is intentionally a helper, not a base class: each owner
## (currently only ElectricalArcState) composes a PhaseTimer instance and
## translates its Phase.A / Phase.B output into its own typed enum,
## passability mapping, and labels. The helper removes the timer math
## but keeps each hazard model responsible for its own semantics, so
## OxygenState (a resource-drain model with no timer phases) does not
## inherit any timer concepts it does not need.
##
## Per ADR-0005 the contract is intentionally small:
## - Tracks `phase` enum, `time_in_phase`, and phase durations.
## - `tick(delta)` flips phase ONCE when duration is reached and carries
##   the remainder into the next phase (no multi-flip in one tick).
## - `configure(phase_durations)` clamps each duration to a minimum of
##   0.1s to prevent infinite rapid toggling.
## - Exposes `current_phase()`, `time_in_phase()`, and
##   `normalized_progress()`.
##
## PhaseTimer is strictly a helper. It owns no scene nodes, no hazard
## labels, and no scene-tree reach. Owners compose it with their own
## enum, passability mapping, and status text.

const MINIMUM_PHASE_DURATION: float = 0.1

# Generic two-phase enum used by every timer hazard owner. Owners map
# these into their own typed enum (ElectricalArcState.Phase)
# via `current_phase()`. The helper does not own per-hazard enums so a
# single PhaseTimer instance can serve multiple owners without leaking
# the helper's enum into a model that wants to keep its own types.
enum Phase { A, B }

var phase: int = Phase.A
var time_in_phase: float = 0.0
var _phase_a_duration: float = MINIMUM_PHASE_DURATION
var _phase_b_duration: float = MINIMUM_PHASE_DURATION

# configure(phase_durations): Dictionary
# - Keys "A" and "B" with float durations in seconds.
# - Missing keys fall back to the existing duration (callers can leave
#   one side untouched while adjusting the other).
# - Negative or zero durations are clamped to MINIMUM_PHASE_DURATION.
# - Always resets phase to A and time_in_phase to 0.0 so a fresh
#   configure behaves like a clean state transition.
func configure(phase_durations: Dictionary) -> void:
	if phase_durations == null:
		phase_durations = {}
	var a_variant: Variant = phase_durations.get("A", _phase_a_duration)
	var b_variant: Variant = phase_durations.get("B", _phase_b_duration)
	_phase_a_duration = _clamp_duration(a_variant)
	_phase_b_duration = _clamp_duration(b_variant)
	phase = Phase.A
	time_in_phase = 0.0

# tick(delta_seconds) -> bool
# - Advances the phase clock by delta_seconds. Returns true when a
#   phase transition occurred (callers can use this to flag a refresh).
# - When delta_seconds exceeds the current phase duration, the helper
#   flips phase once and carries the remainder into the next phase; it
#   does NOT loop multiple times in a single tick, which keeps
#   determinism simple for save/load mid-phase.
# - Non-positive delta_seconds is a no-op (returns false).
func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	time_in_phase += delta_seconds
	var duration: float = _phase_a_duration if phase == Phase.A else _phase_b_duration
	if time_in_phase >= duration:
		time_in_phase -= duration
		phase = Phase.B if phase == Phase.A else Phase.A
		return true
	return false

func current_phase() -> int:
	return phase

func get_time_in_phase() -> float:
	return time_in_phase

# normalized_progress() -> float
# - 0.0 at the start of a phase, 1.0 at the phase boundary (exclusive).
# - Useful for UI fades and label tinting; capped at 1.0 to guard
#   against the carry-remainder case where time_in_phase could
#   briefly exceed the duration in the same tick.
func normalized_progress() -> float:
	var duration: float = _phase_a_duration if phase == Phase.A else _phase_b_duration
	if duration <= 0.0:
		return 0.0
	return clampf(time_in_phase / duration, 0.0, 1.0)

func current_phase_duration() -> float:
	return _phase_a_duration if phase == Phase.A else _phase_b_duration

func _clamp_duration(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return MINIMUM_PHASE_DURATION
	return maxf(MINIMUM_PHASE_DURATION, float(value))
