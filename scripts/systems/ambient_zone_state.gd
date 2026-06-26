extends RefCounted
class_name AmbientZoneState

## AmbientZoneState — pure model for per-room-role ambient layers (REQ-AU-003,
## ADR-0029).
##
## Owns the active room role, a configurable crossfade duration, and a
## threat-meter gain that boosts intensity when hazards are active. The model
## never reaches into the scene tree; AudioManager reads the summary and applies
## it to AudioStreamPlayer volume / bus gain.
##
## State machine:
##   - Each `set_room_role(role)` resets the crossfade target. The crossfade
##     blends from the previous layer's gain (1.0) to the new layer's gain
##     (1.0) over `crossfade_seconds` (default 1.5). At any instant, the
##     previous layer is at `(1 - t)` and the new layer is at `t`.
##   - `set_threat_level(intensity)` sets a threat gain in [0.0, 1.0] that
##     stacks on top of the per-room-role intensity.
##
## Threat meter convention (REQ-AU-003): a threat level above 0.5 adds
## intensity to the active layer; below 0.5 the ambient holds at its base
## intensity. The model itself does not poll hazards — the playable scene
## reads the hazard summaries and pushes the threat value in.

const DEFAULT_CROSSFADE_SECONDS: float = 1.5
const DEFAULT_THREAT_THRESHOLD: float = 0.5
const DEFAULT_THREAT_BOOST: float = 0.25

## Per-room-role ambient intensities and track ids. Keyed by AudioEventSeam.ROOM_ROLE_*.
const ROLE_INTENSITIES: Dictionary = {
	String(AudioEventSeam.ROOM_ROLE_CARGO): 0.55,
	String(AudioEventSeam.ROOM_ROLE_ENGINE): 0.70,
	String(AudioEventSeam.ROOM_ROLE_MED_BAY): 0.45,
	String(AudioEventSeam.ROOM_ROLE_CREW_QUARTERS): 0.40,
	String(AudioEventSeam.ROOM_ROLE_DOCKING): 0.60,
}

const ROLE_TRACK_IDS: Dictionary = {
	String(AudioEventSeam.ROOM_ROLE_CARGO): String(AudioEventSeam.AMB_CARGO),
	String(AudioEventSeam.ROOM_ROLE_ENGINE): String(AudioEventSeam.AMB_ENGINE),
	String(AudioEventSeam.ROOM_ROLE_MED_BAY): String(AudioEventSeam.AMB_MED_BAY),
	String(AudioEventSeam.ROOM_ROLE_CREW_QUARTERS): String(AudioEventSeam.AMB_CREW_QUARTERS),
	String(AudioEventSeam.ROOM_ROLE_DOCKING): String(AudioEventSeam.AMB_DOCKING),
}

var crossfade_seconds: float = DEFAULT_CROSSFADE_SECONDS
var threat_threshold: float = DEFAULT_THREAT_THRESHOLD
var threat_boost: float = DEFAULT_THREAT_BOOST

var _current_role: StringName = AudioEventSeam.ROOM_ROLE_DOCKING
var _current_intensity: float = ROLE_INTENSITIES.get(String(AudioEventSeam.ROOM_ROLE_DOCKING), 0.6)
var _current_track_id: StringName = ROLE_TRACK_IDS.get(String(AudioEventSeam.ROOM_ROLE_DOCKING), AudioEventSeam.AMB_DOCKING)

var _previous_role: StringName = &""
var _previous_intensity: float = 0.0
var _previous_track_id: StringName = &""

var _crossfade_time: float = 0.0
var _crossfade_active: bool = false

var _threat_level: float = 0.0

## Configure from a Dictionary. Recognized keys:
##   - "crossfade_seconds": float (clamped to [0.1, 10.0])
##   - "threat_threshold": float (clamped to [0.0, 1.0])
##   - "threat_boost": float (clamped to [0.0, 1.0])
##   - "initial_role": StringName (defaults to docking; must be a known role)
##   - "initial_threat": float (clamped to [0.0, 1.0])
## Unknown keys are ignored. Missing keys keep their existing values.
func configure(config: Dictionary) -> void:
	if config == null:
		return
	if config.has("crossfade_seconds"):
		crossfade_seconds = clampf(float(config["crossfade_seconds"]), 0.1, 10.0)
	if config.has("threat_threshold"):
		threat_threshold = clampf(float(config["threat_threshold"]), 0.0, 1.0)
	if config.has("threat_boost"):
		threat_boost = clampf(float(config["threat_boost"]), 0.0, 1.0)
	if config.has("initial_role"):
		var role: StringName = StringName(String(config["initial_role"]))
		_current_role = role
		_current_intensity = _intensity_for_role(_current_role)
		_current_track_id = _track_id_for_role(_current_role)
	if config.has("initial_threat"):
		_threat_level = clampf(float(config["initial_threat"]), 0.0, 1.0)
	_previous_role = &""
	_previous_intensity = 0.0
	_previous_track_id = &""
	_crossfade_time = 0.0
	_crossfade_active = false

## Set the active room role. Starts a crossfade from the previous role (or
## restarts the current role if `force_restart` is true). Unknown roles
## keep the current state and, by default, log a warning.
func set_room_role(role_id: StringName, force_restart: bool = false, emit_warning: bool = true) -> void:
	if not _is_known_role(role_id):
		if emit_warning:
			push_warning("AmbientZoneState: unknown room role '%s' (keeping '%s')" % [String(role_id), String(_current_role)])
		return
	if role_id == _current_role and not force_restart and not _crossfade_active:
		return
	_previous_role = _current_role
	_previous_intensity = _current_intensity
	_previous_track_id = _current_track_id
	_current_role = role_id
	_current_intensity = _intensity_for_role(_current_role)
	_current_track_id = _track_id_for_role(_current_role)
	_crossfade_time = 0.0
	_crossfade_active = true

## Set the threat level (0.0 = calm, 1.0 = maximum threat). Clamped to [0, 1].
func set_threat_level(level: float) -> void:
	_threat_level = clampf(level, 0.0, 1.0)

## Advance the crossfade. Returns true when the crossfade completed during
## this tick.
func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	if not _crossfade_active:
		return false
	_crossfade_time += delta_seconds
	if _crossfade_time >= crossfade_seconds:
		_crossfade_active = false
		_crossfade_time = crossfade_seconds
		_previous_role = &""
		_previous_intensity = 0.0
		_previous_track_id = &""
		return true
	return false

## Return the per-layer gains [0.0, 1.0] for the two layers in flight:
## - "current_gain" — gain of the layer that is fading in
## - "previous_gain" — gain of the layer that is fading out (or 0 if no fade)
## - "threat_multiplier" — threat boost applied to both layers
func get_layer_gains() -> Dictionary:
	var current_gain: float = 1.0
	var previous_gain: float = 0.0
	if _crossfade_active and crossfade_seconds > 0.0:
		var t: float = clampf(_crossfade_time / crossfade_seconds, 0.0, 1.0)
		current_gain = t
		previous_gain = 1.0 - t
	var threat_multiplier: float = 1.0
	if _threat_level > threat_threshold:
		threat_multiplier = 1.0 + (_threat_level - threat_threshold) * threat_boost * 2.0
	return {
		"current_gain": current_gain,
		"previous_gain": previous_gain,
		"threat_multiplier": threat_multiplier,
		"current_intensity": _current_intensity,
		"previous_intensity": _previous_intensity,
	}

func get_current_role() -> StringName:
	return _current_role

func get_current_track_id() -> StringName:
	return _current_track_id

func get_threat_level() -> float:
	return _threat_level

func is_crossfade_active() -> bool:
	return _crossfade_active

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Ambient: %s (intensity=%.2f threat=%.2f)" % [String(_current_role), _current_intensity, _threat_level])
	if _crossfade_active:
		var t: float = clampf(_crossfade_time / crossfade_seconds, 0.0, 1.0)
		lines.append("Ambient crossfade: %s -> %s t=%.2f" % [String(_previous_role), String(_current_role), t])
	return lines

## Summary dictionary for save/load (REQ-AU-010). Pure data; no live refs.
func get_summary() -> Dictionary:
	return {
		"kind": "ambient_zone_state",
		"current_role": String(_current_role),
		"current_track_id": String(_current_track_id),
		"current_intensity": _current_intensity,
		"previous_role": String(_previous_role),
		"previous_intensity": _previous_intensity,
		"previous_track_id": String(_previous_track_id),
		"crossfade_active": _crossfade_active,
		"crossfade_time": _crossfade_time,
		"crossfade_seconds": crossfade_seconds,
		"threat_level": _threat_level,
		"threat_threshold": threat_threshold,
		"threat_boost": threat_boost,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "ambient_zone_state":
		return false
	var changed: bool = false
	var new_role: StringName = StringName(String(summary.get("current_role", _current_role)))
	if new_role != _current_role:
		set_room_role(new_role, true)
		changed = true
	if summary.has("crossfade_seconds"):
		var new_cf: float = clampf(float(summary["crossfade_seconds"]), 0.1, 10.0)
		if absf(new_cf - crossfade_seconds) > 0.001:
			crossfade_seconds = new_cf
			changed = true
	if summary.has("threat_threshold"):
		var new_tt: float = clampf(float(summary["threat_threshold"]), 0.0, 1.0)
		if absf(new_tt - threat_threshold) > 0.001:
			threat_threshold = new_tt
			changed = true
	if summary.has("threat_boost"):
		var new_tb: float = clampf(float(summary["threat_boost"]), 0.0, 1.0)
		if absf(new_tb - threat_boost) > 0.001:
			threat_boost = new_tb
			changed = true
	if summary.has("threat_level"):
		var new_threat: float = clampf(float(summary["threat_level"]), 0.0, 1.0)
		if absf(new_threat - _threat_level) > 0.001:
			set_threat_level(new_threat)
			changed = true
	if summary.has("crossfade_active"):
		var new_active: bool = bool(summary["crossfade_active"])
		_crossfade_active = new_active
		changed = true
	if summary.has("crossfade_time"):
		_crossfade_time = clampf(float(summary["crossfade_time"]), 0.0, crossfade_seconds)
		changed = true
	if summary.has("previous_role"):
		_previous_role = StringName(String(summary["previous_role"]))
	if summary.has("previous_track_id"):
		_previous_track_id = StringName(String(summary["previous_track_id"]))
	if summary.has("previous_intensity"):
		_previous_intensity = float(summary["previous_intensity"])
	return changed

func _intensity_for_role(role_id: StringName) -> float:
	return float(ROLE_INTENSITIES.get(String(role_id), 0.6))

func _track_id_for_role(role_id: StringName) -> StringName:
	return StringName(String(ROLE_TRACK_IDS.get(String(role_id), AudioEventSeam.AMB_DOCKING)))

func _is_known_role(role_id: StringName) -> bool:
	for known in AudioEventSeam.ALL_ROOM_ROLES:
		if String(known) == String(role_id):
			return true
	return false
