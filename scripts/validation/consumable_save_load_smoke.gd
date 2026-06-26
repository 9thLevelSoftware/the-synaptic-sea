extends SceneTree

const ConsumableStateScript := preload("res://scripts/systems/consumable_state.gd")
const MedicineStateScript := preload("res://scripts/systems/medicine_state.gd")
const StimulantStateScript := preload("res://scripts/systems/stimulant_state.gd")
const AddictionStateScript := preload("res://scripts/systems/addiction_state.gd")
const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")
const UtilityItemResolverScript := preload("res://scripts/systems/utility_item_resolver.gd")

func _initialize() -> void:
	var consumable := ConsumableStateScript.new()
	consumable.configure({"hotbar_slots": ["bandage_kit", "focus_ampoule", "pistol_ammo_box"]})
	consumable.last_result = {"item_id": "focus_ampoule", "used": 1, "category": "stimulant"}
	var medicine := MedicineStateScript.new()
	medicine.configure({})
	medicine.last_item_id = "field_medkit"
	medicine.last_cured_statuses = ["radiation_sickness"]
	var stimulant := StimulantStateScript.new()
	stimulant.configure({
		"active_stims": [{
			"item_id": "focus_ampoule",
			"remaining": 12.5,
			"base_duration": 20.0,
			"effects": ["stim_focus"],
			"withdrawal_effects": ["withdrawal_shakes"],
		}],
	})
	stimulant.last_used_item = "focus_ampoule"
	var addiction := AddictionStateScript.new()
	addiction.configure({
		"profiles": {
			"focus_ampoule": {
				"tolerance": 0.4,
				"dependence": 0.8,
				"withdrawal_remaining": 6.0,
				"withdrawal_duration": 28.0,
				"withdrawal_effects": ["withdrawal_shakes"],
			}
		}
	})
	var ammo := AmmoStateScript.new()
	ammo.configure({"reserves": {"pistol": 12}})
	var utility := UtilityItemResolverScript.new()
	utility.configure({
		"active_flags": {
			"flare": {
				"item_id": "flare",
				"note": "Flares mark routes and steady the player in dark corridors.",
				"count": 1,
			}
		}
	})
	utility.last_item_id = "flare"
	utility.last_note = "Flares mark routes and steady the player in dark corridors."

	var restored_consumable := ConsumableStateScript.new()
	restored_consumable.configure({})
	var restored_medicine := MedicineStateScript.new()
	restored_medicine.configure({})
	var restored_stimulant := StimulantStateScript.new()
	restored_stimulant.configure({})
	var restored_addiction := AddictionStateScript.new()
	restored_addiction.configure({})
	var restored_ammo := AmmoStateScript.new()
	restored_ammo.configure({})
	var restored_utility := UtilityItemResolverScript.new()
	restored_utility.configure({})

	if not restored_consumable.apply_summary(consumable.get_summary()):
		_fail("consumable summary restore failed")
		return
	if not restored_medicine.apply_summary(medicine.get_summary()):
		_fail("medicine summary restore failed")
		return
	if not restored_stimulant.apply_summary(stimulant.get_summary()):
		_fail("stimulant summary restore failed")
		return
	if not restored_addiction.apply_summary(addiction.get_summary()):
		_fail("addiction summary restore failed")
		return
	if not restored_ammo.apply_summary(ammo.get_summary()):
		_fail("ammo summary restore failed")
		return
	if not restored_utility.apply_summary(utility.get_summary()):
		_fail("utility summary restore failed")
		return

	if str(restored_consumable.hotbar_slots[2]) != "pistol_ammo_box":
		_fail("hotbar slot summary mismatch")
		return
	if str(restored_medicine.last_item_id) != "field_medkit":
		_fail("medicine state summary mismatch")
		return
	if not restored_stimulant.has_active_stim("focus_ampoule"):
		_fail("stimulant summary missing active stim")
		return
	if restored_addiction.get_tolerance("focus_ampoule") <= 0.0 or not restored_addiction.has_withdrawal():
		_fail("addiction summary mismatch")
		return
	if restored_ammo.get_reserve("pistol") != 12:
		_fail("ammo summary mismatch")
		return
	if not restored_utility.active_flags.has("flare"):
		_fail("utility summary mismatch")
		return

	print("CONSUMABLE SAVE LOAD PASS hotbar=true stimulant=true addiction=true ammo=12 utility=flare")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CONSUMABLE SAVE LOAD FAIL reason=%s" % reason)
	quit(1)
