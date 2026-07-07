extends RefCounted
class_name DynamicMusicState

const AudioEventSeam := preload("res://scripts/audio/audio_event_seam.gd")

## DynamicMusicState — pure model for the four-state music layer machine
## (REQ-AU-004, ADR-0029).
##
## States: EXPLORATION (default) -> TENSION (hazard non-safe) -> COMBAT
## (engagement flag) -> CRITICAL (vitals unsafe). CRITICAL takes priority
## over COMBAT and TENSION; COMBAT over TENSION.
##
## Each state declares a per-layer target gain. The model owns per-layer
## crossfades (default 2.0s) so layer gains smoothly approach their targets
## while the player moves between gameplay states.
##
## Determinism: no RNG. Per-tick math is closed-form (clamped linear lerp).

const DEFAULT_CROSSFADE_SECONDS: float = 2.0

## Per-state target gains (0.0 .. 1.0). The four music layers are mutually
## compatible: more than one can play at once (e.g. EXPLORATION holds BASE
## at 1.0 and TENSION stacks TENSION_DRONE on top).
const STATE_TARGET_GAINS: Dictionary = {
	String(AudioEventSeam.MUSIC_STATE_EXPLORATION): {
		AudioEventSeam.MUSIC_LAYER_BASE: 1.0,
		AudioEventSeam.MUSIC_LAYER_TENSION_DRONE: 0.0,
		AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION: 0.0,
		AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD: 0.0,
	},
	String(AudioEventSeam.MUSIC_STATE_TENSION): {
		AudioEventSeam.MUSIC_LAYER_BASE: 0.6,
		AudioEventSeam.MUSIC_LAYER_TENSION_DRONE: 0.7,
		AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION: 0.0,
		AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD: 0.0,
	},
	String(AudioEventSeam.MUSIC_STATE_COMBAT): {
		AudioEventSeam.MUSIC_LAYER_BASE: 0.5,
		AudioEventSeam.MUSIC_LAYER_TENSION_DRONE: 0.4,
		AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION: 0.9,
		AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD: 0.0,
	},
	String(AudioEventSeam.MUSIC_STATE_CRITICAL): {
		AudioEventSeam.MUSIC_LAYER_BASE: 0.3,
		AudioEventSeam.MUSIC_LAYER_TENSION_DRONE: 0.4,
		AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION: 0.7,
		AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD: 0.9,
	},
}

var crossfade_seconds: float = DEFAULT_CROSSFADE_SECONDS

var _state: StringName = AudioEventSeam.MUSIC_STATE_EXPLORATION
var _engagement_flag: bool = false
var _hazard_active: bool = false
var _vitals_critical: bool = false

## Layer gains (0.0 .. 1.0). Layer id -> current gain. Always present for
## the four canonical layers (other layers can be added via configure()).
var _layer_gains: Dictionary = {
	AudioEventSeam.MUSIC_LAYER_BASE: 1.0,
	AudioEventSeam.MUSIC_LAYER_TENSION_DRONE: 0.0,
	AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION: 0.0,
	AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD: 0.0,
}

var _target_gains: Dictionary = _layer_gains.duplicate(true)

func configure(config: Dictionary) -> void:
	if config == null:
		return
	if config.has("crossfade_seconds"):
		crossfade_seconds = clampf(float(config["crossfade_seconds"]), 0.1, 30.0)
	if config.has("initial_state"):
		var new_state: StringName = StringName(String(config["initial_state"]))
		if _is_known_state(new_state):
			_state = new_state
			_target_gains = _target_gains_for_state(_state)
	# Snap current gains to target gains so a fresh configure behaves like a
	# clean state transition.
	_layer_gains = _target_gains.duplicate(true)
	if config.has("engagement_flag"):
		_engagement_flag = bool(config["engagement_flag"])
	if config.has("hazard_active"):
		_hazard_active = bool(config["hazard_active"])
	if config.has("vitals_critical"):
		_vitals_critical = bool(config["vitals_critical"])

## Update the per-frame gameplay flags and (optionally) snap the state to a
## new value. The state is computed from the flags via resolve_state().
func set_flags(engagement: bool, hazard_active: bool, vitals_critical: bool) -> void:
	_engagement_flag = engagement
	_hazard_active = hazard_active
	_vitals_critical = vitals_critical
	var new_state: StringName = resolve_state()
	if new_state != _state:
		_state = new_state
		_target_gains = _target_gains_for_state(_state)

## Pure resolution: returns the priority-ordered state for the current flags.
func resolve_state() -> StringName:
	if _vitals_critical:
		return AudioEventSeam.MUSIC_STATE_CRITICAL
	if _engagement_flag:
		return AudioEventSeam.MUSIC_STATE_COMBAT
	if _hazard_active:
		return AudioEventSeam.MUSIC_STATE_TENSION
	return AudioEventSeam.MUSIC_STATE_EXPLORATION

## Force a state override (used by meta-events and scripted music cues).
## Set `emit_warning=false` when callers intentionally probe an invalid
## state id and only care about the boolean rejection path.
func override_state(new_state: StringName, emit_warning: bool = true) -> bool:
	if not _is_known_state(new_state):
		if emit_warning:
			push_warning("DynamicMusicState: unknown state '%s'" % String(new_state))
		return false
	_state = new_state
	_target_gains = _target_gains_for_state(_state)
	return true

## Advance the per-layer crossfades. Returns true when any layer's gain
## changed (caller can use this to know when to push values to AudioServer).
func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	if crossfade_seconds <= 0.0:
		_layer_gains = _target_gains.duplicate(true)
		return false
	var step: float = delta_seconds / crossfade_seconds
	var changed: bool = false
	for layer_id in _target_gains.keys():
		var target: float = float(_target_gains[layer_id])
		var current: float = float(_layer_gains.get(layer_id, target))
		if absf(current - target) < 0.0001:
			if current != target:
				_layer_gains[layer_id] = target
				changed = true
			continue
		var new_gain: float = current + (target - current) * step
		if (target > current and new_gain > target) or (target < current and new_gain < target):
			new_gain = target
		_layer_gains[layer_id] = clampf(new_gain, 0.0, 1.0)
		changed = true
	return changed

## Snapshot of the current layer gains (layer id -> gain).
func get_layer_gains() -> Dictionary:
	return _layer_gains.duplicate(true)

func get_state() -> StringName:
	return _state

func get_target_gains() -> Dictionary:
	return _target_gains.duplicate(true)

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Music: state=%s base=%.2f tension_drone=%.2f combat_perc=%.2f critical_pad=%.2f" % [
		String(_state),
		float(_layer_gains.get(AudioEventSeam.MUSIC_LAYER_BASE, 0.0)),
		float(_layer_gains.get(AudioEventSeam.MUSIC_LAYER_TENSION_DRONE, 0.0)),
		float(_layer_gains.get(AudioEventSeam.MUSIC_LAYER_COMBAT_PERCUSSION, 0.0)),
		float(_layer_gains.get(AudioEventSeam.MUSIC_LAYER_CRITICAL_PAD, 0.0)),
	])
	return lines

func get_summary() -> Dictionary:
	return {
		"kind": "dynamic_music_state",
		"state": String(_state),
		"crossfade_seconds": crossfade_seconds,
		"engagement_flag": _engagement_flag,
		"hazard_active": _hazard_active,
		"vitals_critical": _vitals_critical,
		"layer_gains": _layer_gains_as_str_keys(),
		"target_gains": _target_gains_as_str_keys(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "dynamic_music_state":
		return false
	var changed: bool = false
	if summary.has("crossfade_seconds"):
		var new_cf: float = clampf(float(summary["crossfade_seconds"]), 0.1, 30.0)
		if absf(new_cf - crossfade_seconds) > 0.001:
			crossfade_seconds = new_cf
			changed = true
	if summary.has("state"):
		var new_state: StringName = StringName(String(summary["state"]))
		if _is_known_state(new_state) and new_state != _state:
			override_state(new_state)
			changed = true
	if summary.has("engagement_flag"):
		_engagement_flag = bool(summary["engagement_flag"])
	if summary.has("hazard_active"):
		_hazard_active = bool(summary["hazard_active"])
	if summary.has("vitals_critical"):
		_vitals_critical = bool(summary["vitals_critical"])
	if summary.has("layer_gains"):
		var lg: Variant = summary["layer_gains"]
		if typeof(lg) == TYPE_DICTIONARY:
			_layer_gains.clear()
			for k in (lg as Dictionary).keys():
				_layer_gains[StringName(String(k))] = clampf(float((lg as Dictionary)[k]), 0.0, 1.0)
			changed = true
	if summary.has("target_gains"):
		var tg: Variant = summary["target_gains"]
		if typeof(tg) == TYPE_DICTIONARY:
			_target_gains.clear()
			for k in (tg as Dictionary).keys():
				_target_gains[StringName(String(k))] = clampf(float((tg as Dictionary)[k]), 0.0, 1.0)
			changed = true
	return changed

func _is_known_state(state_id: StringName) -> bool:
	for known in AudioEventSeam.ALL_MUSIC_STATES:
		if String(known) == String(state_id):
			return true
	return false

func _target_gains_for_state(state_id: StringName) -> Dictionary:
	var entry: Variant = STATE_TARGET_GAINS.get(String(state_id), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return _layer_gains.duplicate(true)
	var result: Dictionary = {}
	for layer_id in AudioEventSeam.ALL_MUSIC_LAYERS:
		result[layer_id] = float((entry as Dictionary).get(layer_id, 0.0))
	return result

func _layer_gains_as_str_keys() -> Dictionary:
	var result: Dictionary = {}
	for k in _layer_gains.keys():
		result[String(k)] = float(_layer_gains[k])
	return result

func _target_gains_as_str_keys() -> Dictionary:
	var result: Dictionary = {}
	for k in _target_gains.keys():
		result[String(k)] = float(_target_gains[k])
	return result
