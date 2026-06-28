extends RefCounted
class_name ElectricalArcState

## Runtime model for the Alpha electrical-arc hazard (REQ-013, ADR-0005).
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the arc-zone scene node and applies scene consequences from this summary.
##
## Per ADR-0005 this model:
## - Implements the HazardStateContract (configure / tick / get_summary /
##   apply_summary / is_passability_blocked / get_status_lines).
## - Owns a PhaseTimer instance (it is now the only timer-based hazard; the
##   old FireState was retired in M7-B). The helper removes timer-math
##   duplication while this class owns the per-hazard enum, passability
##   mapping, label text, and the `hazard_kind` discriminator required by
##   the contract.
## - Remains an independent RefCounted; OxygenState does not inherit any
##   timer concepts from this class (and vice versa).
##
## The hazard cycle is short-safe (1.5s DISCHARGED) then short-danger
## (2.5s ARCING) on a 4.0s loop.

const PhaseTimerScript := preload("res://scripts/systems/phase_timer.gd")

const DEFAULT_ARCING_DURATION: float = 2.5
const DEFAULT_DISCHARGED_DURATION: float = 1.5
const HAZARD_KIND: String = "electrical_arc"

enum Phase { DISCHARGED, ARCING }

var zone_ids: Array = []
var arcing_duration: float = DEFAULT_ARCING_DURATION
var discharged_duration: float = DEFAULT_DISCHARGED_DURATION

var phase: int = Phase.DISCHARGED
var time_in_phase: float = 0.0
var passability_blocked: bool = false
# PhaseTimer maps its internal Phase.A -> DISCHARGED and Phase.B -> ARCING
# so this hazard uses the helper with a stable A/B vocabulary while owning
# the typed Phase enum above.
var _phase_timer: PhaseTimer = PhaseTimerScript.new()

# configure(config: Dictionary) -> void
# - Per ADR-0005 HazardStateContract: receives the loader's zone array
#   and tuning values as a dictionary so the model can unpack the fields
#   it needs. Recognized keys:
#     - "zone_ids": Array[String] (zone ids whose collision is toggled)
#     - "arcing_duration": float (ARCING phase duration in seconds)
#     - "discharged_duration": float (DISCHARGED phase duration in seconds)
#     - "arcing_first": bool (when true, initial phase is ARCING; default
#       false to match the canonical DISCHARGED-first cycle)
#   Unknown keys are ignored for forward compatibility. Missing keys
#   fall back to the existing value, except for the zone array which
#   defaults to empty when not supplied.
# - Resets phase to DISCHARGED (or ARCING when arcing_first is true) and
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
	if config != null and config.has("arcing_duration"):
		arcing_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, float(config["arcing_duration"]))
	if config != null and config.has("discharged_duration"):
		discharged_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, float(config["discharged_duration"]))
	var arcing_first: bool = false
	if config != null and config.has("arcing_first"):
		arcing_first = bool(config["arcing_first"])
	# PhaseTimer A = DISCHARGED (safe/passable), B = ARCING (blocks).
	_phase_timer.configure({"A": discharged_duration, "B": arcing_duration})
	if arcing_first:
		_phase_timer.phase = _phase_timer.Phase.B
	else:
		_phase_timer.phase = _phase_timer.Phase.A
	_phase_timer.time_in_phase = 0.0
	_sync_phase_from_timer()
	_recompute_passability_blocked()

# tick(delta_seconds: float, context: Dictionary = {}) -> bool
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
# - Required by the ADR-0005 contract: must include `hazard_kind`
#   ("electrical_arc") and `passability_blocked` (bool). The remaining
#   keys follow the uniform timer-hazard shape SaveLoadService consumers
#   expect.
func get_summary() -> Dictionary:
	var current_duration: float = arcing_duration if phase == Phase.ARCING else discharged_duration
	return {
		"hazard_kind": HAZARD_KIND,
		"state": "ARCING" if phase == Phase.ARCING else "DISCHARGED",
		"phase": phase,
		"time_in_state": time_in_phase,
		"cycle_duration": arcing_duration + discharged_duration,
		"arcing": phase == Phase.ARCING,
		"passability_blocked": passability_blocked,
		"arcing_duration": arcing_duration,
		"discharged_duration": discharged_duration,
		"remaining_in_state": maxf(0.0, current_duration - time_in_phase),
		"zone_ids": zone_ids.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if phase == Phase.ARCING:
		lines.append("Arc: ARCING — WAIT")
	else:
		lines.append("Arc: DISCHARGED — CROSS")
	return lines

# apply_summary(summary: Dictionary) -> bool
# - Per ADR-0005 contract: returns false if the kind does not match (a
#   fire or oxygen summary cannot restore an ElectricalArcState).
#   Returns false on null/empty input. Returns true if any field changed.
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
	var new_arcing: float = float(summary.get("arcing_duration", arcing_duration))
	if absf(new_arcing - arcing_duration) > 0.001:
		arcing_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, new_arcing)
		changed = true
	var new_discharged: float = float(summary.get("discharged_duration", discharged_duration))
	if absf(new_discharged - discharged_duration) > 0.001:
		discharged_duration = maxf(_phase_timer.MINIMUM_PHASE_DURATION, new_discharged)
		changed = true
	# Re-sync the helper so subsequent ticks advance against the restored
	# durations from whatever phase we just restored.
	_phase_timer.configure({"A": discharged_duration, "B": arcing_duration})
	# Manually place the helper into the matching phase and time_in_phase
	# after configure() (which resets to Phase.A / 0.0).
	if phase == Phase.ARCING:
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
		phase = Phase.DISCHARGED
	else:
		phase = Phase.ARCING
	time_in_phase = _phase_timer.get_time_in_phase()

func _recompute_passability_blocked() -> void:
	passability_blocked = (phase == Phase.ARCING)
