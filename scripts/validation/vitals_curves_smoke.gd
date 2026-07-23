extends SceneTree

## PKG-C3.1b: response curves (not cliffs) + cross-coupling (each survival stat feeds ≥2 others).
## Marker: VITALS CURVES PASS curves=true cross=true wounds=true cold=true

const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const WoundStateScript := preload("res://scripts/systems/wound_state.gd")
const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")


func _initialize() -> void:
	# --- Curves not cliffs: intermediate values differ from endpoints ---
	var h0: float = VitalsStateScript.hunger_stamina_recovery_curve(0.0, 100.0)
	var h20: float = VitalsStateScript.hunger_stamina_recovery_curve(20.0, 100.0)
	var h40: float = VitalsStateScript.hunger_stamina_recovery_curve(40.0, 100.0)
	var h60: float = VitalsStateScript.hunger_stamina_recovery_curve(60.0, 100.0)
	if not (h0 < h20 and h20 < h40 and h40 < h60):
		_fail("hunger→stamina curve not strictly increasing: %s %s %s %s" % [h0, h20, h40, h60])
		return
	if absf(h60 - 1.0) > 0.001:
		_fail("full hunger should fully recover stamina"); return

	var v0: float = VitalsStateScript.thirst_vision_curve(0.0, 100.0)
	var v15: float = VitalsStateScript.thirst_vision_curve(15.0, 100.0)
	var v50: float = VitalsStateScript.thirst_vision_curve(50.0, 100.0)
	if not (v0 < v15 and v15 < v50):
		_fail("thirst→vision not continuous"); return

	var m0: float = VitalsStateScript.stamina_move_curve(0.0, 100.0)
	var m10: float = VitalsStateScript.stamina_move_curve(10.0, 100.0)
	var m50: float = VitalsStateScript.stamina_move_curve(50.0, 100.0)
	if not (m0 < m10 and m10 < m50):
		_fail("stamina→move not continuous"); return
	# Old cliff was 0.5 at stamina<=15; curve must not jump-discontinuity around 15
	var m14: float = VitalsStateScript.stamina_move_curve(14.0, 100.0)
	var m16: float = VitalsStateScript.stamina_move_curve(16.0, 100.0)
	if absf(m16 - m14) > 0.35:
		_fail("move mult cliff around exhaustion threshold"); return

	# --- Cross-coupling: each stat feeds ≥2 others ---
	# hunger → stamina recovery + health drain
	var starve_h: float = VitalsStateScript.hunger_health_drain_curve(5.0, 100.0)
	if starve_h <= 0.0:
		_fail("starvation should drain health"); return
	if VitalsStateScript.hunger_health_drain_curve(50.0, 100.0) > 0.0:
		_fail("fed player should not starve-drain"); return

	# thirst → vision + stamina drain
	var tsd_low: float = VitalsStateScript.thirst_stamina_drain_curve(10.0, 100.0)
	var tsd_high: float = VitalsStateScript.thirst_stamina_drain_curve(80.0, 100.0)
	if tsd_low <= tsd_high:
		_fail("dehydration should raise stamina drain"); return

	# temperature → thirst + hunger (cold)
	var temp = BodyTemperatureStateScript.new()
	temp.configure({"temperature": 10.0, "safe_min": 18.0, "safe_max": 32.0})
	if temp.get_thirst_multiplier() <= 1.0:
		_fail("cold should raise thirst mult"); return
	if temp.get_hunger_multiplier() <= 1.0:
		_fail("cold should raise hunger mult"); return
	var temp_safe = BodyTemperatureStateScript.new()
	temp_safe.configure({"temperature": 22.0})
	if absf(temp_safe.get_hunger_multiplier() - 1.0) > 0.001:
		_fail("safe temp hunger mult 1"); return

	# wounds → thirst + health (via context into vitals tick)
	var wounds = WoundStateScript.new()
	wounds.apply_wound({"kind": "laceration", "body_part": "torso", "severity": 0.7})
	var wound_thirst: float = wounds.thirst_drain_multiplier()
	var wound_bleed: float = wounds.total_bleed_rate()
	if wound_thirst <= 1.0 or wound_bleed <= 0.0:
		_fail("wounds should raise thirst and bleed"); return

	var v = VitalsStateScript.new()
	v.configure({"hunger_drain_rate": 0.5, "thirst_drain_rate": 0.8, "stamina_drain_rate": 0.0, "health_drain_rate": 0.0})
	v.thirst = 100.0
	v.health = 100.0
	v.hunger = 100.0
	# cold + wounds cross-coupling tick
	v.tick(1.0, {
		SimKeysScript.MOVING: false,
		SimKeysScript.TEMPERATURE_THIRST_MULT: temp.get_thirst_multiplier(),
		SimKeysScript.TEMPERATURE_HUNGER_MULT: temp.get_hunger_multiplier(),
		SimKeysScript.WOUND_THIRST_MULT: wound_thirst,
		SimKeysScript.WOUND_HEALTH_DRAIN: wound_bleed,
	})
	if v.thirst >= 99.2:
		_fail("wound+temp should accelerate thirst, got %s" % str(v.thirst)); return
	if v.health >= 99.9:
		_fail("wound bleed should drain health, got %s" % str(v.health)); return
	if v.hunger >= 99.6:
		_fail("cold hunger mult should accelerate hunger, got %s" % str(v.hunger)); return

	# starvation path also hits health without external wounds
	var v2 = VitalsStateScript.new()
	v2.configure({"health_drain_rate": 0.0, "hunger_drain_rate": 0.0, "thirst_drain_rate": 0.0, "stamina_drain_rate": 0.0})
	v2.hunger = 5.0
	v2.health = 100.0
	v2.tick(1.0, {SimKeysScript.MOVING: false})
	if v2.health >= 100.0:
		_fail("starvation curve should drain health"); return

	# live getters
	v2.thirst = 10.0
	v2.stamina = 10.0
	if v2.get_vision_multiplier() >= 0.95:
		_fail("low thirst vision"); return
	if v2.get_movement_speed_multiplier() >= 0.95:
		_fail("low stamina move"); return

	print("VITALS CURVES PASS curves=true cross=true wounds=true cold=true")
	quit(0)


func _fail(msg: String) -> void:
	print("VITALS CURVES FAIL: %s" % msg)
	quit(1)
