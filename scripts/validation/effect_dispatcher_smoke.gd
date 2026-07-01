extends SceneTree

const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")
const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")

func _initialize() -> void:
	var dispatcher := EffectDispatcherScript.new()
	dispatcher.configure({})
	var vitals := VitalsStateScript.new()
	vitals.configure({"health": 50.0, "stamina": 10.0, "hunger": 30.0, "thirst": 20.0})
	var sanity := SanityStateScript.new()
	sanity.configure({"sanity": 40.0})
	var radiation := RadiationStateScript.new()
	radiation.configure({"radiation": 60.0})
	var temp := BodyTemperatureStateScript.new()
	temp.configure({"temperature": 22.0})
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	statuses.add_effect("radiation_sickness", 10.0, 1)
	var ammo := AmmoStateScript.new()
	ammo.configure({})
	var context := {
		"vitals_state": vitals,
		"sanity_state": sanity,
		"radiation_state": radiation,
		"body_temperature_state": temp,
		"status_effects_state": statuses,
		"ammo_state": ammo,
	}

	var heal := dispatcher.dispatch_effect("heal_small", context)
	if not bool(heal.get("ok", false)) or absf(vitals.health - 68.0) > 0.001:
		_fail("heal_small did not restore health")
		return
	var stim := dispatcher.dispatch_effect("stim_focus", context)
	if not bool(stim.get("ok", false)) or not statuses.has_effect("stim_focus"):
		_fail("stim_focus did not add status")
		return
	var sane := dispatcher.dispatch_effect("restore_sanity_small", context)
	if not bool(sane.get("ok", false)) or absf(sanity.sanity - 48.0) > 0.001:
		_fail("restore_sanity_small mismatch")
		return
	var rad := dispatcher.dispatch_effect("reduce_radiation_minor", context)
	if not bool(rad.get("ok", false)) or absf(radiation.radiation - 40.0) > 0.001:
		_fail("reduce_radiation_minor mismatch")
		return
	var cure := dispatcher.dispatch_effect("cure_radiation_sickness", context)
	if not bool(cure.get("ok", false)) or statuses.has_effect("radiation_sickness"):
		_fail("cure_radiation_sickness did not clear status")
		return
	print("EFFECT DISPATCHER PASS health=68 sanity=48 radiation=40 status=stim_focus")
	quit(0)

func _fail(reason: String) -> void:
	push_error("EFFECT DISPATCHER FAIL reason=%s" % reason)
	quit(1)
