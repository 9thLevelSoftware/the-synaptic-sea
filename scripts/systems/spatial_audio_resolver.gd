extends RefCounted
class_name SpatialAudioResolver

## SpatialAudioResolver — deterministic spatial attenuation and occlusion
## (REQ-AU-005, ADR-0029).
##
## Pure function of (emitter_pos, listener_pos, occluded, base_db).
## No RNG, no scene-tree reach-in. AudioManager calls
## resolve_volume_db(...) per SFX emission to compute the final stream
## volume.
##
## Distance model:
##   distance = (emitter_pos - listener_pos).length()
##   When distance <= ref_distance, attenuation is 0.0 dB.
##   When distance >= max_distance, attenuation is -max_attenuation_db.
##   In between, linear interpolation in dB space.
##
## Occlusion model:
##   occluded = true  -> apply occlusion_penalty_db (default -6.0)
##   occluded = false -> no penalty.
##
## Determinism:
##   resolve_volume_db returns the same float for the same inputs across
##   the process lifetime. The smoke verifies this with a tight epsilon.

const DEFAULT_REF_DISTANCE: float = 2.0
const DEFAULT_MAX_DISTANCE: float = 25.0
const DEFAULT_MAX_ATTENUATION_DB: float = -36.0
const DEFAULT_OCCLUSION_PENALTY_DB: float = -6.0

var ref_distance: float = DEFAULT_REF_DISTANCE
var max_distance: float = DEFAULT_MAX_DISTANCE
var max_attenuation_db: float = DEFAULT_MAX_ATTENUATION_DB
var occlusion_penalty_db: float = DEFAULT_OCCLUSION_PENALTY_DB

func configure(config: Dictionary) -> void:
	if config == null:
		return
	if config.has("ref_distance"):
		ref_distance = clampf(float(config["ref_distance"]), 0.01, 1000.0)
	if config.has("max_distance"):
		max_distance = clampf(float(config["max_distance"]), ref_distance + 0.01, 10000.0)
	if config.has("max_attenuation_db"):
		max_attenuation_db = clampf(float(config["max_attenuation_db"]), -120.0, 0.0)
	if config.has("occlusion_penalty_db"):
		occlusion_penalty_db = clampf(float(config["occlusion_penalty_db"]), -60.0, 0.0)

## Compute the final dB value for an emitter at `emitter_pos` heard by a
## listener at `listener_pos`. `occluded=true` applies the occlusion penalty.
##
## Edge cases:
## - Identical positions (distance == 0) returns base_db (no attenuation).
## - NaN / Inf positions are clamped to 0 before distance math.
## - max_attenuation_db == 0 short-circuits to base_db - penalty when occluded.
func resolve_volume_db(emitter_pos: Vector3, listener_pos: Vector3, occluded: bool, base_db: float) -> float:
	var ep: Vector3 = _safe_vector(emitter_pos)
	var lp: Vector3 = _safe_vector(listener_pos)
	var distance: float = (ep - lp).length()
	if not is_finite(distance):
		distance = 0.0
	var attenuation: float = _attenuation_for_distance(distance)
	var penalty: float = occlusion_penalty_db if occluded else 0.0
	var result: float = base_db + attenuation + penalty
	if not is_finite(result):
		# Clamp a non-finite result so callers never see NaN/Inf in the
		# AudioStreamPlayer volume_db property.
		result = -60.0
	return result

func _attenuation_for_distance(distance: float) -> float:
	if max_distance <= ref_distance:
		return max_attenuation_db if distance > ref_distance else 0.0
	if distance <= ref_distance:
		return 0.0
	if distance >= max_distance:
		return max_attenuation_db
	var t: float = (distance - ref_distance) / (max_distance - ref_distance)
	return max_attenuation_db * t

func _safe_vector(v: Vector3) -> Vector3:
	return Vector3(
		0.0 if not is_finite(v.x) else v.x,
		0.0 if not is_finite(v.y) else v.y,
		0.0 if not is_finite(v.z) else v.z,
	)

## Static helpers — handy for tests and for AudioManager's static catalog.
static func distance(emitter_pos: Vector3, listener_pos: Vector3) -> float:
	return (emitter_pos - listener_pos).length()

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Spatial: ref=%.2f max=%.2f max_atten=%.2f occlusion=%.2f" % [ref_distance, max_distance, max_attenuation_db, occlusion_penalty_db])
	return lines

func get_summary() -> Dictionary:
	return {
		"kind": "spatial_audio_resolver",
		"ref_distance": ref_distance,
		"max_distance": max_distance,
		"max_attenuation_db": max_attenuation_db,
		"occlusion_penalty_db": occlusion_penalty_db,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "spatial_audio_resolver":
		return false
	var changed: bool = false
	if summary.has("ref_distance"):
		var new_rd: float = clampf(float(summary["ref_distance"]), 0.01, 1000.0)
		if absf(new_rd - ref_distance) > 0.001:
			ref_distance = new_rd
			changed = true
	if summary.has("max_distance"):
		var new_md: float = clampf(float(summary["max_distance"]), ref_distance + 0.01, 10000.0)
		if absf(new_md - max_distance) > 0.001:
			max_distance = new_md
			changed = true
	if summary.has("max_attenuation_db"):
		var new_ma: float = clampf(float(summary["max_attenuation_db"]), -120.0, 0.0)
		if absf(new_ma - max_attenuation_db) > 0.001:
			max_attenuation_db = new_ma
			changed = true
	if summary.has("occlusion_penalty_db"):
		var new_op: float = clampf(float(summary["occlusion_penalty_db"]), -60.0, 0.0)
		if absf(new_op - occlusion_penalty_db) > 0.001:
			occlusion_penalty_db = new_op
			changed = true
	return changed
