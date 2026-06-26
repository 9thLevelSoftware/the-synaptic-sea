extends SceneTree

const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const MedicineStateScript := preload("res://scripts/systems/medicine_state.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")

func _initialize() -> void:
	var dispatcher := EffectDispatcherScript.new()
	dispatcher.configure({})
	var medicine := MedicineStateScript.new()
	medicine.configure({})
	var vitals := VitalsStateScript.new()
	vitals.configure({"health": 52.0})
	var sanity := SanityStateScript.new()
	sanity.configure({"sanity": 40.0})
	var radiation := RadiationStateScript.new()
	radiation.configure({"radiation": 62.0})
	var temperature := BodyTemperatureStateScript.new()
	temperature.configure({})
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	statuses.add_effect("radiation_sickness", 18.0, 1)
	statuses.add_effect("food_poisoning", 18.0, 1)
	var context := {
		"vitals_state": vitals,
		"sanity_state": sanity,
		"radiation_state": radiation,
		"body_temperature_state": temperature,
		"status_effects_state": statuses,
	}

	var rad_patch_result := medicine.use_medicine("rad_patch", {
		"effects": ["reduce_radiation_minor", "cure_radiation_sickness"],
	}, dispatcher, context)
	if not bool(rad_patch_result.get("ok", false)):
		_fail("rad_patch use failed")
		return
	if absf(radiation.radiation - 42.0) > 0.001 or statuses.has_effect("radiation_sickness"):
		_fail("rad_patch did not cure radiation sickness")
		return

	var antitoxin_result := medicine.use_medicine("antitoxin", {
		"effects": ["cure_food_poisoning", "restore_sanity_small"],
	}, dispatcher, context)
	if not bool(antitoxin_result.get("ok", false)):
		_fail("antitoxin use failed")
		return
	if statuses.has_effect("food_poisoning") or absf(sanity.sanity - 48.0) > 0.001:
		_fail("antitoxin did not cure poison + restore sanity")
		return

	var medkit_result := medicine.use_medicine("field_medkit", {
		"effects": ["heal_medium", "restore_stamina_small"],
	}, dispatcher, context)
	if not bool(medkit_result.get("ok", false)) or absf(vitals.health - 87.0) > 0.001:
		_fail("field_medkit heal mismatch")
		return

	var summary := medicine.get_summary()
	var restored := MedicineStateScript.new()
	restored.configure({})
	if not restored.apply_summary(summary):
		_fail("medicine summary restore failed")
		return
	if str(restored.last_item_id) != "field_medkit":
		_fail("restored last_item_id mismatch")
		return

	print("MEDICINE STATE PASS health=87 radiation=42 sanity=48 cured=food_poisoning,radiation_sickness")
	quit(0)

func _fail(reason: String) -> void:
	push_error("MEDICINE STATE FAIL reason=%s" % reason)
	quit(1)
