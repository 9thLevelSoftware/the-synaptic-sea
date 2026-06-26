extends RefCounted
class_name DetectionState

const DEFAULT_MEMORY_SECONDS: float = 5.0
const DEFAULT_DETECT_THRESHOLD: float = 0.75

var noise_level: float = 0.0
var light_level: float = 0.0
var sight_level: float = 0.0
var crouching: bool = false
var room_id: String = ""
var detect_threshold: float = DEFAULT_DETECT_THRESHOLD
var memory_seconds: float = DEFAULT_MEMORY_SECONDS
var memory_remaining: float = 0.0
var awareness_score: float = 0.0
var detected: bool = false
var heard: bool = false
var seen: bool = false
var last_reason: String = "idle"

func configure(config: Dictionary = {}) -> void:
	detect_threshold = maxf(0.0, float(config.get("detect_threshold", DEFAULT_DETECT_THRESHOLD)))
	memory_seconds = maxf(0.0, float(config.get("memory_seconds", DEFAULT_MEMORY_SECONDS)))
	noise_level = clampf(float(config.get("noise_level", 0.0)), 0.0, 2.0)
	light_level = clampf(float(config.get("light_level", 0.0)), 0.0, 2.0)
	sight_level = clampf(float(config.get("sight_level", 0.0)), 0.0, 2.0)
	crouching = bool(config.get("crouching", false))
	room_id = str(config.get("room_id", ""))
	memory_remaining = maxf(0.0, float(config.get("memory_remaining", 0.0)))
	detected = bool(config.get("detected", false))
	heard = bool(config.get("heard", false))
	seen = bool(config.get("seen", false))
	awareness_score = clampf(float(config.get("awareness_score", 0.0)), 0.0, 3.0)
	last_reason = str(config.get("last_reason", "idle"))

func update_inputs(noise: float, light: float, sight: float, is_crouching: bool, current_room_id: String = "") -> void:
	noise_level = clampf(noise, 0.0, 2.0)
	light_level = clampf(light, 0.0, 2.0)
	sight_level = clampf(sight, 0.0, 2.0)
	crouching = is_crouching
	room_id = current_room_id

func tick(delta: float, weights: Dictionary = {}) -> bool:
	if delta < 0.0:
		return false
	var noise_weight: float = maxf(0.0, float(weights.get("noise_weight", 1.0)))
	var light_weight: float = maxf(0.0, float(weights.get("light_weight", 1.0)))
	var sight_weight: float = maxf(0.0, float(weights.get("sight_weight", 1.0)))
	var crouch_mult: float = float(weights.get("crouch_multiplier", 0.65 if crouching else 1.0))
	awareness_score = clampf((noise_level * noise_weight + light_level * light_weight + sight_level * sight_weight) * crouch_mult, 0.0, 3.0)
	heard = noise_level * noise_weight * crouch_mult >= detect_threshold
	seen = (light_level * light_weight + sight_level * sight_weight) * crouch_mult >= detect_threshold
	if awareness_score >= detect_threshold:
		detected = true
		memory_remaining = memory_seconds
		last_reason = "sound" if heard and not seen else ("sight" if seen and not heard else "combined")
	elif memory_remaining > 0.0:
		memory_remaining = maxf(0.0, memory_remaining - delta)
		detected = memory_remaining > 0.0
		last_reason = "memory"
	else:
		detected = false
		last_reason = "idle"
	return true

func get_summary() -> Dictionary:
	return {
		"noise_level": noise_level,
		"light_level": light_level,
		"sight_level": sight_level,
		"crouching": crouching,
		"room_id": room_id,
		"detect_threshold": detect_threshold,
		"memory_seconds": memory_seconds,
		"memory_remaining": memory_remaining,
		"awareness_score": awareness_score,
		"detected": detected,
		"heard": heard,
		"seen": seen,
		"last_reason": last_reason,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var before: String = JSON.stringify(get_summary())
	configure(summary)
	return before != JSON.stringify(get_summary())

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Detection: score=%.2f detected=%s reason=%s" % [awareness_score, str(detected).to_lower(), last_reason])
	lines.append("Stealth: noise=%.2f light=%.2f sight=%.2f crouch=%s" % [noise_level, light_level, sight_level, str(crouching).to_lower()])
	return lines
