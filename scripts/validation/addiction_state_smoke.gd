extends SceneTree

const AddictionStateScript := preload("res://scripts/systems/addiction_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")

func _initialize() -> void:
	var addiction := AddictionStateScript.new()
	addiction.configure({})
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	var definition := {
		"tolerance_gain": 0.35,
		"dependence_gain": 0.55,
		"withdrawal_duration": 8.0,
		"withdrawal_effects": ["withdrawal_shakes", "withdrawal_fatigue"],
	}
	addiction.record_dose("combat_stim", definition)
	addiction.record_dose("combat_stim", definition)
	var triggered := addiction.activate_withdrawal_if_needed("combat_stim", statuses)
	if not bool(triggered.get("ok", false)):
		_fail("withdrawal did not trigger")
		return
	if not statuses.has_effect("withdrawal_shakes") or not statuses.has_effect("withdrawal_fatigue"):
		_fail("withdrawal statuses missing")
		return
	var summary := addiction.get_summary()
	var restored := AddictionStateScript.new()
	restored.configure({})
	if not restored.apply_summary(summary):
		_fail("summary restore failed")
		return
	if restored.get_tolerance("combat_stim") <= 0.0 or not restored.has_withdrawal():
		_fail("restored addiction profile mismatch")
		return
	addiction.tick(40.0, statuses)
	statuses.tick(40.0)
	if addiction.has_withdrawal() or statuses.has_effect("withdrawal_shakes") or statuses.has_effect("withdrawal_fatigue"):
		_fail("withdrawal did not clear")
		return
	print("ADDICTION STATE PASS tolerance=0.70 dependence=1.10 withdrawal=true cleared=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("ADDICTION STATE FAIL reason=%s" % reason)
	quit(1)
