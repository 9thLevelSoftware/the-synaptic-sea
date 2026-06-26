extends SceneTree

const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const StimulantStateScript := preload("res://scripts/systems/stimulant_state.gd")
const AddictionStateScript := preload("res://scripts/systems/addiction_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")

func _initialize() -> void:
	var dispatcher := EffectDispatcherScript.new()
	dispatcher.configure({})
	var stimulant := StimulantStateScript.new()
	stimulant.configure({})
	var addiction := AddictionStateScript.new()
	addiction.configure({})
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	var vitals := VitalsStateScript.new()
	vitals.configure({"stamina": 10.0})
	var context := {
		"status_effects_state": statuses,
		"vitals_state": vitals,
	}
	var definition := {
		"effects": ["stim_haste", "restore_stamina_large"],
		"withdrawal_effects": ["withdrawal_shakes", "withdrawal_fatigue"],
		"stim_duration": 2.0,
		"withdrawal_duration": 3.0,
		"tolerance_gain": 0.5,
		"dependence_gain": 2.0,
	}
	var used := stimulant.use_stimulant("combat_stim", definition, dispatcher, addiction, context)
	if not bool(used.get("ok", false)) or not stimulant.has_active_stim("combat_stim") or not statuses.has_effect("stim_haste"):
		_fail("stim use did not create active buff")
		return
	if absf(vitals.stamina - 50.0) > 0.001:
		_fail("stamina restore mismatch")
		return
	stimulant.tick(2.1, addiction, context)
	if stimulant.has_active_stim("combat_stim"):
		_fail("stim should have expired")
		return
	if not addiction.has_withdrawal() or not statuses.has_effect("withdrawal_shakes"):
		_fail("withdrawal did not activate")
		return
	addiction.tick(40.1, statuses)
	statuses.tick(40.1)
	if addiction.has_withdrawal() or statuses.has_effect("withdrawal_shakes") or statuses.has_effect("withdrawal_fatigue"):
		_fail("withdrawal did not clear after duration")
		return
	var summary: Dictionary = addiction.get_summary()
	var restored := AddictionStateScript.new()
	restored.configure({})
	if not restored.apply_summary(summary):
		_fail("addiction summary restore failed")
		return
	if restored.get_tolerance("combat_stim") <= 0.0:
		_fail("restored tolerance missing")
		return

	print("STIMULANT STATE PASS active=true withdrawal=true cleared=true tolerance=%.2f" % restored.get_tolerance("combat_stim"))
	quit(0)

func _fail(reason: String) -> void:
	push_error("STIMULANT STATE FAIL reason=%s" % reason)
	quit(1)
