extends RefCounted
class_name FireState

## Runtime model for the Gate 2 timed fire-zone hazard.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the fire-zone scene node and applies scene consequences from this summary.
##
## Per ADR-0005 this model:
## - Implements the HazardStateContract (configure / tick / get_summary /
##   apply_summary / is_passability_blocked / get_status_lines).
## - Owns a PhaseTimer instance shared with ElectricalArcState; the helper
##   removes timer-math duplication while this class owns the per-hazard
##   enum, passability mapping, label text, and the `hazard_kind`
##   discriminator required by the contract.
## - Remains an independent RefCounted; OxygenState does not inherit any
##   timer concepts from this class (and vice versa).
##
## The hazard cycle is long-safe (3.0s CLEARED) then long-danger
## (4.0s BURNING). The total 7.0s cycle is intentionally de-synchronized
## from the electrical-arc cycle (4.0s) so the two hazards de-correlate
## on a run.

const PhaseTimerScript := preload("res://scripts/systems/phase_timer.gd")

const DEFAULT_BURN_DURATION: float = 4.0
const DEFAULT_CLEAR_DURATION: float = 3.0
const HAZARD_KIND: String = "fire"

enum Phase { CLEARED, BURNING }

var zone_ids: Array = []
var burn_duration: float = DEFAULT_BURN_DURATION
var clear_duration: float = DEFAULT_CLEAR_DURATION

var phase: int = Phase.CLEARED
var time_in_phase: float = 0.0
var passability_blocked: bool = false
# Per ADR-0005: PhaseTimer maps its internal Phase.A -> CLEARED and
# Phase.B -> BURNING so FireState and ElectricalArcState can share the
# helper with a stable A/B vocabulary while each owns a typed Phase enum
# above. Owning the helper here removes the local MINIMUM_PHASE_DURATION,
# phase, time_in_phase, and phase-flip math that used to live in this
# class. The state fields above are kept for direct accessor compatibility
# with existing saves and consumers; they are mirrors of the helper's
# phase + time_in_phase, translated through _sync_phase_from_timer().
var _phase_timer: PhaseTimer = PhaseTimerScript.new()

# configure(config: Dictionary) -> void
# - Per ADR-0005 HazardStateContract: receives the loader's zone array
#   and tuning values as a dictionary so the model can unpack the fields
#   it needs. Recognized keys:
#     - "zone_ids": Array[String] (zone ids whose collision is toggled)
#     - "burn_duration": float (BURNING phase duration in seconds)
#     - "clear_duration": float (CLEARED phase duration in seconds)
#     - "burning_first": bool (when true, initial phase is BURNING;
#       default false to match the canonical CLEARED-first cycle)
#   Unknown keys are ignored for forward compatibility. Missing keys
#   fall back to the existing value, except for the zone array which
#   defaults to empty when not supplied.
# - Resets phase to CLEARED (or BURNING when burning_first is true) and
#   time_in_phase to 0.0 so a fresh configure behaves like a clean
#   state transition. Passability is recomputed from the new phase.
func configure(config: Dictionary) -> void:
	zone_ids.clear()
	if config != null and config.has("zone_ids"):
		var zone_ids_variant: Variant = config["zone_ids"]
		if typeof(zone_ids_variant) == TYPE_ARRAY:
			for zone_id_variant in (zone_ids_variant as Array):
				var zone_id: String = str(zone_id_variant)
				if zone_id.is_empty():
					continue
				zone_ids.append(zone_id)
	if config != null and config.has("burn_duration"):
		burn_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, float(config["burn_duration"]))
	if config != null and config.has("clear_duration"):
		clear_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, float(config["clear_duration"]))
	var burning_first: bool = false
	if config != null and config.has("burning_first"):
		burning_first = bool(config["burning_first"])
	# PhaseTimer A = CLEARED (safe), B = BURNING (blocks). Configure the
	# helper with the matching durations so it carries the timer math.
	_phase_timer.configure({"A": clear_duration, "B": burn_duration})
	if burning_first:
		_phase_timer.phase = _phase_timer.Phase.B
	else:
		_phase_timer.phase = _phase_timer.Phase.A
	_phase_timer.time_in_phase = 0.0
	_sync_phase_from_timer()
	_recompute_passability_blocked()

# tick(delta_seconds: float, _context: Dictionary = {}) -> bool
# - Per ADR-0005, the `context` dictionary is optional and unused here
#   (oxygen is the only Alpha hazard that reads per-frame player context).
#   Accepting the kwarg keeps the HazardStateContract uniform.
# - Returns true when the cycle flipped phases or the passability changed.
func tick(delta_seconds: float, _context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var before: bool = passability_blocked
	var flipped: bool = _phase_timer.tick(delta_seconds)
	_sync_phase_from_timer()
	_recompute_passability_blocked()
	if flipped:
		return true
	return passability_blocked != before

func is_passability_blocked() -> bool:
	return passability_blocked

# get_summary() -> Dictionary
# - Required by the ADR-0005 contract: must include `hazard_kind` ("fire")
#   and `passability_blocked` (bool). The remaining keys mirror
#   ElectricalArcState so SaveLoadService consumers can apply both
#   timer-hazard summaries through a uniform shape.
func get_summary() -> Dictionary:
	var current_duration: float = burn_duration if phase == Phase.BURNING else clear_duration
	return {
		"hazard_kind": HAZARD_KIND,
		"state": "BURNING" if phase == Phase.BURNING else "CLEARED",
		"phase": phase,
		"time_in_state": time_in_phase,
		"cycle_duration": burn_duration + clear_duration,
		"burning": phase == Phase.BURNING,
		"passability_blocked": passability_blocked,
		"burn_duration": burn_duration,
		"clear_duration": clear_duration,
		"remaining_in_state": maxf(0.0, current_duration - time_in_phase),
		"zone_ids": zone_ids.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if phase == Phase.BURNING:
		lines.append("Fire: BURNING — WAIT")
	else:
		lines.append("Fire: CLEARED")
	return lines

# apply_summary(summary: Dictionary) -> bool
# - Per ADR-0005 contract: returns false if the kind does not match (an
#   electrical-arc or oxygen summary cannot restore a FireState). Returns
#   false on null/empty input. Returns true if any field changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("hazard_kind", "")) != HAZARD_KIND:
		return false
	var changed: bool = false
	var new_phase_variant: Variant = summary.get("phase", phase)
	var new_phase: int = int(new_phase_variant)
	if new_phase != phase:
		phase = new_phase
		changed = true
	var new_burn: float = float(summary.get("burn_duration", burn_duration))
	if absf(new_burn - burn_duration) > 0.001:
		burn_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, new_burn)
		changed = true
	var new_clear: float = float(summary.get("clear_duration", clear_duration))
	if absf(new_clear - clear_duration) > 0.001:
		clear_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, new_clear)
		changed = true
	# Re-sync the helper so subsequent ticks advance against the restored
	# durations from whatever phase we just restored.
	_phase_timer.configure({"A": clear_duration, "B": burn_duration})
	# Manually place the helper into the matching phase and time_in_phase
	# after configure() (which resets to Phase.A / 0.0).
	if phase == Phase.BURNING:
		_phase_timer.phase = _phase_timer.Phase.B
	else:
		_phase_timer.phase = _phase_timer.Phase.A
	var new_time: float = float(summary.get("time_in_state", time_in_phase))
	if absf(new_time - time_in_phase) > 0.001:
		time_in_phase = new_time
		changed = true
	_phase_timer.time_in_phase = time_in_phase
	var new_zone_ids_variant: Variant = summary.get("zone_ids", zone_ids)
	if typeof(new_zone_ids_variant) == TYPE_ARRAY and (new_zone_ids_variant as Array) != zone_ids:
		zone_ids = []
		for zone_id in (new_zone_ids_variant as Array):
			zone_ids.append(str(zone_id))
		changed = true
	_recompute_passability_blocked()
	return changed

func _sync_phase_from_timer() -> void:
	var timer_phase: int = _phase_timer.current_phase()
	if timer_phase == _phase_timer.Phase.A:
		phase = Phase.CLEARED
	else:
		phase = Phase.BURNING
	time_in_phase = _phase_timer.get_time_in_phase()

func _recompute_passability_blocked() -> void:
	passability_blocked = (phase == Phase.BURNING)
