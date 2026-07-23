extends RefCounted
class_name VitalsState

## Pure model for player core vitals: health, stamina, hunger, thirst.
## Per REQ-SV-001.  No scene-tree access.
## PKG-C3.1b: response curves (not cliffs) + cross-coupling (each stat feeds ≥2 others).

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")

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
## Soft UI warning thresholds (not hard gameplay cliffs).
const HUNGER_STAMINA_CASCADE_THRESHOLD: float = 30.0
const THIRST_VISION_WARNING_THRESHOLD: float = 20.0
const EXHAUSTION_STAMINA_THRESHOLD: float = 15.0

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

## Hermite smoothstep t in [0,1] → [0,1].
static func smoothstep01(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Hunger → stamina recovery mult. Full recovery above 50% hunger; smooth down to 0.25 at empty.
static func hunger_stamina_recovery_curve(hunger_value: float, max_h: float) -> float:
	if max_h <= 0.0:
		return 1.0
	var r: float = clampf(hunger_value / max_h, 0.0, 1.0)
	if r >= 0.5:
		return 1.0
	var t: float = r / 0.5
	return 0.25 + 0.75 * smoothstep01(t)


## Thirst → vision clarity mult (1.0 clear → 0.35 at empty). Continuous, not a cliff.
static func thirst_vision_curve(thirst_value: float, max_t: float) -> float:
	if max_t <= 0.0:
		return 1.0
	var r: float = clampf(thirst_value / max_t, 0.0, 1.0)
	if r >= 0.35:
		return 1.0
	var t: float = r / 0.35
	return 0.35 + 0.65 * smoothstep01(t)


## Thirst → stamina drain mult when dehydrated (1.0 full → 1.75 empty).
static func thirst_stamina_drain_curve(thirst_value: float, max_t: float) -> float:
	if max_t <= 0.0:
		return 1.0
	var r: float = clampf(thirst_value / max_t, 0.0, 1.0)
	if r >= 0.4:
		return 1.0
	var deficit: float = 1.0 - (r / 0.4)
	return 1.0 + 0.75 * smoothstep01(deficit)


## Hunger → passive health drain when starving (0 at 25%+, up to 2.0/s scale at 0).
static func hunger_health_drain_curve(hunger_value: float, max_h: float) -> float:
	if max_h <= 0.0:
		return 0.0
	var r: float = clampf(hunger_value / max_h, 0.0, 1.0)
	if r >= 0.25:
		return 0.0
	var deficit: float = 1.0 - (r / 0.25)
	return 2.0 * smoothstep01(deficit)


## Stamina → movement mult. Full speed above 30%; smooth down to 0.35 at empty.
static func stamina_move_curve(stamina_value: float, max_s: float) -> float:
	if max_s <= 0.0:
		return 1.0
	var r: float = clampf(stamina_value / max_s, 0.0, 1.0)
	if r >= 0.3:
		return 1.0
	var t: float = r / 0.3
	return 0.35 + 0.65 * smoothstep01(t)


## Cold (below safe) raises hunger drain. Returns mult ≥ 1.
## delta_c below safe_min; 0 inside band.
static func cold_hunger_curve(temperature: float, safe_min: float) -> float:
	if temperature >= safe_min:
		return 1.0
	var deficit: float = clampf((safe_min - temperature) / 10.0, 0.0, 1.0)
	return 1.0 + 0.8 * smoothstep01(deficit)


## tick updates all four vitals.  context keys (SimKeys / historical wire names):
##   SimKeys.RADIATION_HEALTH_DRAIN -> float
##   SimKeys.ATMOSPHERE_HEALTH_DRAIN -> float
##   SimKeys.FIRE_HEALTH_DRAIN -> float
##   SimKeys.SANITY_HEALTH_DRAIN -> float
##   SimKeys.ENCUMBRANCE_HEALTH_DRAIN -> float (inventory load_ratio > 1)
##   SimKeys.TEMPERATURE_THIRST_MULT -> float
##   SimKeys.TEMPERATURE_HUNGER_MULT -> float (PKG-C3.1b cold→hunger)
##   SimKeys.WOUND_THIRST_MULT -> float (PKG-C3.1b wounds→thirst)
##   SimKeys.WOUND_HEALTH_DRAIN -> float (PKG-C3.1b bleed)
##   SimKeys.STATUS_STAMINA_RECOVERY_MULT -> float
##   SimKeys.SANITY_STAMINA_RECOVERY_MULT -> float
##   SimKeys.MOVING -> bool (when false stamina recovers instead of draining)
func tick(delta_seconds: float, context: Dictionary = {}) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	# Hunger → stamina recovery (curve, not cliff).
	var stamina_recovery_mult: float = hunger_stamina_recovery_curve(hunger, max_hunger)
	if context.has(SimKeysScript.STATUS_STAMINA_RECOVERY_MULT):
		stamina_recovery_mult *= float(context.get(SimKeysScript.STATUS_STAMINA_RECOVERY_MULT, 1.0))
	if context.has(SimKeysScript.SANITY_STAMINA_RECOVERY_MULT):
		stamina_recovery_mult *= float(context.get(SimKeysScript.SANITY_STAMINA_RECOVERY_MULT, 1.0))
	# Thirst → stamina drain when moving
	var stamina_drain_mult: float = thirst_stamina_drain_curve(thirst, max_thirst)
	# Stamina
	var moving: bool = bool(context.get(SimKeysScript.MOVING, true))
	if moving:
		var s_drain: float = stamina_drain_rate * stamina_drain_mult * delta_seconds
		if s_drain > 0.0 and stamina > 0.0:
			stamina = maxf(0.0, stamina - s_drain)
			changed = true
	else:
		var s_recover: float = stamina_recovery_rate * stamina_recovery_mult * delta_seconds
		if s_recover > 0.0 and stamina < max_stamina:
			stamina = minf(max_stamina, stamina + s_recover)
			changed = true
	# Health (passive + hazards + wound bleed + starvation curve)
	var h_drain: float = health_drain_rate * delta_seconds
	h_drain += hunger_health_drain_curve(hunger, max_hunger) * delta_seconds
	if context.has(SimKeysScript.RADIATION_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.RADIATION_HEALTH_DRAIN, 0.0)) * delta_seconds
	if context.has(SimKeysScript.ATMOSPHERE_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.ATMOSPHERE_HEALTH_DRAIN, 0.0)) * delta_seconds
	if context.has(SimKeysScript.FIRE_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.FIRE_HEALTH_DRAIN, 0.0)) * delta_seconds
	if context.has(SimKeysScript.SANITY_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.SANITY_HEALTH_DRAIN, 0.0)) * delta_seconds
	if context.has(SimKeysScript.ENCUMBRANCE_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.ENCUMBRANCE_HEALTH_DRAIN, 0.0)) * delta_seconds
	if context.has(SimKeysScript.WOUND_HEALTH_DRAIN):
		h_drain += float(context.get(SimKeysScript.WOUND_HEALTH_DRAIN, 0.0)) * delta_seconds
	if h_drain > 0.0 and health > 0.0:
		health = maxf(0.0, health - h_drain)
		changed = true
	elif health_recovery_rate > 0.0 and health < max_health:
		var h_recover: float = health_recovery_rate * delta_seconds
		health = minf(max_health, health + h_recover)
		changed = true
	# Hunger (cold cascade via temperature_hunger_mult)
	var hgr_mult: float = float(context.get(SimKeysScript.TEMPERATURE_HUNGER_MULT, 1.0))
	var hgr_drain: float = hunger_drain_rate * maxf(0.0, hgr_mult) * delta_seconds
	if hgr_drain > 0.0 and hunger > 0.0:
		hunger = maxf(0.0, hunger - hgr_drain)
		changed = true
	# Thirst (temperature + wounds)
	var t_mult: float = float(context.get(SimKeysScript.TEMPERATURE_THIRST_MULT, 1.0))
	var wound_t: float = float(context.get(SimKeysScript.WOUND_THIRST_MULT, 1.0))
	var t_drain: float = thirst_drain_rate * maxf(0.0, t_mult) * maxf(0.0, wound_t) * delta_seconds
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

## Domain 1 (survival_vitals stakes): true when the player has bled out.
## Pure predicate; the coordinator turns this into end_run("death").
func is_incapacitated() -> bool:
	return health <= 0.0

## Domain 1: low-vitals action-gating as continuous movement-speed multiplier (PKG-C3.1b curve).
func get_movement_speed_multiplier() -> float:
	if is_incapacitated():
		return 0.0
	return stamina_move_curve(stamina, max_stamina)


## PKG-C3.1b: continuous vision clarity from thirst (for HUD / post FX later).
func get_vision_multiplier() -> float:
	return thirst_vision_curve(thirst, max_thirst)


## PKG-C3.1b: current hunger→stamina recovery mult (for smokes / HUD).
func get_hunger_stamina_recovery_mult() -> float:
	return hunger_stamina_recovery_curve(hunger, max_hunger)

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
		"hunger_stamina_recovery_mult": get_hunger_stamina_recovery_mult(),
		"vision_mult": get_vision_multiplier(),
		"move_mult": get_movement_speed_multiplier(),
		"thirst_stamina_drain_mult": thirst_stamina_drain_curve(thirst, max_thirst),
		"starvation_health_drain": hunger_health_drain_curve(hunger, max_hunger),
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
		lines.append("HUNGER LOW -> stamina recovery ×%.2f" % get_hunger_stamina_recovery_mult())
	if thirst < THIRST_VISION_WARNING_THRESHOLD:
		lines.append("THIRST LOW -> vision impaired (×%.2f)" % get_vision_multiplier())
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
