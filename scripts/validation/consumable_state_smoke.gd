extends SceneTree

const ConsumableStateScript := preload("res://scripts/systems/consumable_state.gd")
const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MedicineStateScript := preload("res://scripts/systems/medicine_state.gd")
const StimulantStateScript := preload("res://scripts/systems/stimulant_state.gd")
const AddictionStateScript := preload("res://scripts/systems/addiction_state.gd")
const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")
const UtilityItemResolverScript := preload("res://scripts/systems/utility_item_resolver.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")

func _initialize() -> void:
	var inventory := InventoryStateScript.new()
	inventory.reset()
	inventory.add_item("bandage_kit", 1)
	inventory.add_item("focus_ampoule", 1)
	inventory.add_item("flare", 1)

	var dispatcher := EffectDispatcherScript.new()
	dispatcher.configure({})
	var consumable := ConsumableStateScript.new()
	consumable.configure({})
	var medicine := MedicineStateScript.new()
	medicine.configure({})
	var stimulant := StimulantStateScript.new()
	stimulant.configure({})
	var addiction := AddictionStateScript.new()
	addiction.configure({})
	var ammo := AmmoStateScript.new()
	ammo.configure({})
	var utility := UtilityItemResolverScript.new()
	utility.configure({})
	var vitals := VitalsStateScript.new()
	vitals.configure({"health": 60.0, "stamina": 20.0})
	var sanity := SanityStateScript.new()
	sanity.configure({"sanity": 50.0})
	var radiation := RadiationStateScript.new()
	radiation.configure({})
	var temperature := BodyTemperatureStateScript.new()
	temperature.configure({})
	var statuses := StatusEffectsStateScript.new()
	statuses.configure({})
	var context := {
		"effect_dispatcher": dispatcher,
		"medicine_state": medicine,
		"stimulant_state": stimulant,
		"addiction_state": addiction,
		"ammo_state": ammo,
		"utility_state": utility,
		"vitals_state": vitals,
		"sanity_state": sanity,
		"radiation_state": radiation,
		"body_temperature_state": temperature,
		"status_effects_state": statuses,
	}

	if not consumable.assign_hotbar_slot(0, "bandage_kit"):
		_fail("assign_hotbar_slot bandage_kit failed")
		return
	if not consumable.assign_hotbar_slot(1, "focus_ampoule"):
		_fail("assign_hotbar_slot focus_ampoule failed")
		return
	var med := consumable.use_hotbar_slot(0, inventory, context)
	if not bool(med.get("ok", false)) or inventory.get_quantity("bandage_kit") != 0 or absf(vitals.health - 78.0) > 0.001:
		_fail("medicine hotbar use mismatch")
		return
	var stim := consumable.use_hotbar_slot(1, inventory, context)
	if not bool(stim.get("ok", false)) or inventory.get_quantity("focus_ampoule") != 0 or not statuses.has_effect("stim_focus"):
		_fail("stimulant hotbar use mismatch")
		return
	var utility_result := consumable.use_item("flare", inventory, context)
	if not bool(utility_result.get("ok", false)) or inventory.get_quantity("flare") != 0 or not utility.active_flags.has("flare"):
		_fail("utility use mismatch")
		return

	var summary: Dictionary = consumable.get_summary()
	var restored := ConsumableStateScript.new()
	restored.configure({})
	if not restored.apply_summary(summary):
		_fail("consumable summary did not restore")
		return
	if str(restored.hotbar_slots[1]) != "focus_ampoule":
		_fail("hotbar summary mismatch")
		return

	print("CONSUMABLE STATE PASS used=3 hotbar=true health=78 stim=true utility=flare")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CONSUMABLE STATE FAIL reason=%s" % reason)
	quit(1)
