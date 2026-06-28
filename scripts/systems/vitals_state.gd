extends RefCounted
class_name VitalsState

## Pure model for player core vitals: health, stamina, hunger, thirst.
## Per REQ-SV-001.  No scene-tree access.

const DEFAULT_MAX_HEALTH: float = 100.0
const DEFAULT_MAX_STAMINA: float = 100.0
const DEFAULT_MAX_HUNGER: float = 100.0
const DEFAULT_MAX_THIRST: float = 100.0
const DEFAULT_HEALTH_DRAIN: float = 0.0
const DEFAULT_STAMINA_DRAIN: float = 2.0
const DEFAULT_HUNGER_DRAIN: float = 0.5
const DEFAULT_THIRST_DRAIN: float = 0.8
const DEFAULT_STAMINA_RECOVERY: float = 5.0
const DEFAULT_HEALTH_RECOVERY: float = 0.0
const HUNGER_STAMINA_CASCADE_THRESHOLD: float = 30.0
const THIRST_VISION_WARNING_THRESHOLD: float = 20.0

var max_health: float = DEFAULT_MAX_HEALTH
var max_stamina: float = DEFAULT_MAX_STAMINA
var max_hunger: float = DEFAULT_MAX_HUNGER
var max_thirst: float = DEFAULT_MAX_THIRST
var health_drain_rate: float = DEFAULT_HEALTH_DRAIN
var stamina_drain_rate: float = DEFAULT_STAMINA_DRAIN
var hunger_drain_rate: float = DEFAULT_HUNGER_DRAIN
var thirst_drain_rate: float = DEFAULT_THIRST_DRAIN
var stamina_recovery_rate: float = DEFAULT_STAMINA_RECOVERY
var health_recovery_rate: float = DEFAULT_HEALTH_RECOVERY

var health: float = DEFAULT_MAX_HEALTH
var stamina: float = DEFAULT_MAX_STAMINA
var hunger: float = DEFAULT_MAX_HUNGER
var thirst: float = DEFAULT_MAX_THIRST

func configure(config: Dictionary) -> void:
	max_health = _f(config, "max_health", DEFAULT_MAX_HEALTH)
	max_stamina = _f(config, "max_stamina", DEFAULT_MAX_STAMINA)
	max_hunger = _f(config, "max_hunger", DEFAULT_MAX_HUNGER)
	max_thirst = _f(config, "max_thirst", DEFAULT_MAX_THIRST)
	health_drain_rate = _f(config, "health_drain_rate", DEFAULT_HEALTH_DRAIN)
	stamina_drain_rate = _f(config, "stamina_drain_rate", DEFAULT_STAMINA_DRAIN)
	hunger_drain_rate = _f(config, "hunger_drain_rate", DEFAULT_HUNGER_DRAIN)
	thirst_drain_rate = _f(config, "thirst_drain_rate", DEFAULT_THIRST_DRAIN)
	stamina_recovery_rate = _f(config, "stamina_recovery_rate", DEFAULT_STAMINA_RECOVERY)
	health_recovery_rate = _f(config, "health_recovery_rate", DEFAULT_HEALTH_RECOVERY)
	health = clampf(_f(config, "health", health), 0.0, max_health)
	stamina = clampf(_f(config, "stamina", stamina), 0.0, max_stamina)
	hunger = clampf(_f(config, "hunger", hunger), 0.0, max_hunger)
	thirst = clampf(_f(config, "thirst", thirst), 0.0, max_thirst)

## tick updates all four vitals.  context keys used by downstream systems:
##   "radiation_health_drain" -> float (added to health drain when radiation high)
##   "atmosphere_health_drain" -> float (added to health drain when the hub atmosphere is fouled)
##   "fire_health_drain" -> float (added to health drain while standing in a burning compartment)
##   "temperature_thirst_mult" -> float (multiplies thirst drain when temp unsafe)
##   "status_stamina_recovery_mult" -> float (multiplier from active effects)
##   "moving" -> bool (when false stamina recovers instead of draining)
func tick(delta_seconds: float, context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	# Hunger cascade: below threshold stamina recovery is halved.
	var stamina_recovery_mult: float = 1.0
	if hunger < HUNGER_STAMINA_CASCADE_THRESHOLD:
		stamina_recovery_mult = 0.5
	if context.has("status_stamina_recovery_mult"):
		stamina_recovery_mult *= float(context.get("status_stamina_recovery_mult", 1.0))
	# Stamina
	var moving: bool = bool(context.get("moving", true))
	if moving:
		var s_drain: float = stamina_drain_rate * delta_seconds
		if s_drain > 0.0 and stamina > 0.0:
			stamina = maxf(0.0, stamina - s_drain)
			changed = true
	else:
		var s_recover: float = stamina_recovery_rate * stamina_recovery_mult * delta_seconds
		if s_recover > 0.0 and stamina < max_stamina:
			stamina = minf(max_stamina, stamina + s_recover)
			changed = true
	# Health (passive drain + optional radiation drain + optional atmosphere drain)
	var h_drain: float = health_drain_rate * delta_seconds
	if context.has("radiation_health_drain"):
		h_drain += float(context.get("radiation_health_drain", 0.0)) * delta_seconds
	if context.has("atmosphere_health_drain"):
		h_drain += float(context.get("atmosphere_health_drain", 0.0)) * delta_seconds
	if context.has("fire_health_drain"):
		h_drain += float(context.get("fire_health_drain", 0.0)) * delta_seconds
	if h_drain > 0.0 and health > 0.0:
		health = maxf(0.0, health - h_drain)
		changed = true
	elif health_recovery_rate > 0.0 and health < max_health:
		var h_recover: float = health_recovery_rate * delta_seconds
		health = minf(max_health, health + h_recover)
		changed = true
	# Hunger
	var hgr_drain: float = hunger_drain_rate * delta_seconds
	if hgr_drain > 0.0 and hunger > 0.0:
		hunger = maxf(0.0, hunger - hgr_drain)
		changed = true
	# Thirst (temperature cascade)
	var t_mult: float = float(context.get("temperature_thirst_mult", 1.0))
	var t_drain: float = thirst_drain_rate * t_mult * delta_seconds
	if t_drain > 0.0 and thirst > 0.0:
		thirst = maxf(0.0, thirst - t_drain)
		changed = true
	return changed

func apply_delta(delta: Dictionary) -> Dictionary:
	health = clampf(health + float(delta.get("health", 0.0)), 0.0, max_health)
	stamina = clampf(stamina + float(delta.get("stamina", 0.0)), 0.0, max_stamina)
	hunger = clampf(hunger + float(delta.get("hunger", 0.0)), 0.0, max_hunger)
	thirst = clampf(thirst + float(delta.get("thirst", 0.0)), 0.0, max_thirst)
	return get_summary()

func get_summary() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"hunger": hunger,
		"max_hunger": max_hunger,
		"thirst": thirst,
		"max_thirst": max_thirst,
		"health_drain_rate": health_drain_rate,
		"stamina_drain_rate": stamina_drain_rate,
		"hunger_drain_rate": hunger_drain_rate,
		"thirst_drain_rate": thirst_drain_rate,
		"stamina_recovery_rate": stamina_recovery_rate,
		"health_recovery_rate": health_recovery_rate,
		"hunger_stamina_cascade_active": hunger < HUNGER_STAMINA_CASCADE_THRESHOLD,
		"thirst_vision_warning_active": thirst < THIRST_VISION_WARNING_THRESHOLD,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var field_map: Dictionary = {
		"health": "health", "max_health": "max_health",
		"stamina": "stamina", "max_stamina": "max_stamina",
		"hunger": "hunger", "max_hunger": "max_hunger",
		"thirst": "thirst", "max_thirst": "max_thirst",
		"health_drain_rate": "health_drain_rate", "stamina_drain_rate": "stamina_drain_rate",
		"hunger_drain_rate": "hunger_drain_rate", "thirst_drain_rate": "thirst_drain_rate",
		"stamina_recovery_rate": "stamina_recovery_rate", "health_recovery_rate": "health_recovery_rate",
	}
	for key in field_map:
		if summary.has(key):
			var new_val: float = float(summary.get(key, 0.0))
			var current: float = get(field_map[key])
			if absf(new_val - current) > 0.001:
				set(field_map[key], new_val)
				changed = true
	# Re-clamp
	health = clampf(health, 0.0, max_health)
	stamina = clampf(stamina, 0.0, max_stamina)
	hunger = clampf(hunger, 0.0, max_hunger)
	thirst = clampf(thirst, 0.0, max_thirst)
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_vital_line("Health", health, max_health, 25.0))
	lines.append(_vital_line("Stamina", stamina, max_stamina, 20.0))
	lines.append(_vital_line("Hunger", hunger, max_hunger, 15.0))
	lines.append(_vital_line("Thirst", thirst, max_thirst, 15.0))
	if hunger < HUNGER_STAMINA_CASCADE_THRESHOLD:
		lines.append("HUNGER LOW -> stamina recovery halved")
	if thirst < THIRST_VISION_WARNING_THRESHOLD:
		lines.append("THIRST LOW -> vision impaired")
	return lines

func _vital_line(name: String, value: float, maxv: float, critical: float) -> String:
	var pct: int = int(round((value / maxv) * 100.0)) if maxv > 0.0 else 0
	var suffix: String = ""
	if value <= critical:
		suffix = " CRITICAL"
	return "%s: %d%%%s" % [name, pct, suffix]

func _f(config: Dictionary, key: String, fallback: float) -> float:
	if config.has(key):
		return maxf(0.0, float(config.get(key, fallback)))
	return fallback
