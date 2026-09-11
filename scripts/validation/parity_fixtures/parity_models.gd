extends RefCounted

## Pure RefCounted model tick fixtures. Each model is constructed/configured
## the way its scripts/validation/<model>_smoke.gd does, then driven through a
## fixed step list, recording get_summary() after configure, after setup, and
## after every step, plus a get_summary -> apply_summary round trip.

const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const SpoilageStateScript := preload("res://scripts/systems/spoilage_state.gd")
const HydroponicsStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

## Step groups: [delta, count]. Group index is passed to the per-model context
## schedule so contexts can vary per group.
const STEP_GROUPS: Array = [[1.0 / 60.0, 10], [0.35, 5], [3.0, 3], [5.0, 2]]

var summary: Dictionary = {}


func run(writer) -> bool:
	var ok: bool = true
	for spec in _specs():
		ok = _run_spec(writer, spec) and ok
	ok = writer.copy_file_abs(ProjectSettings.globalize_path(ShipSystemsManagerScript.DEFINITIONS_PATH), "models/inputs/ship_systems_definitions.json") and ok
	return ok


func _run_spec(writer, spec: Dictionary) -> bool:
	var model_name: String = spec["name"]
	var model = (spec["script"] as GDScript).new()
	var configure: Callable = spec["configure"]
	configure.call(model)
	var summary_after_configure: Dictionary = model.get_summary()

	var setup_records: Array = []
	for setup_variant in spec.get("setup", []):
		var setup: Dictionary = setup_variant
		var setup_return: Variant = (setup["call"] as Callable).call(model)
		setup_records.append({
			"op": setup["op"],
			"args": setup.get("args", {}),
			"return": setup_return,
			"summary_after": model.get_summary(),
		})

	var steps: Array = []
	var step_index: int = 0
	for group_index in range(STEP_GROUPS.size()):
		var group: Array = STEP_GROUPS[group_index]
		var delta: float = float(group[0])
		for i in range(int(group[1])):
			var pre_records: Array = []
			var pre_ops: Array = (spec.get("pre_step", Callable()) as Callable).call(group_index, i) if spec.has("pre_step") else []
			for pre_variant in pre_ops:
				var pre: Dictionary = pre_variant
				(pre["call"] as Callable).call(model)
				pre_records.append({"op": pre["op"], "args": pre.get("args", {})})
			var tick_record: Dictionary = (spec["tick"] as Callable).call(model, delta, group_index)
			var step: Dictionary = {
				"index": step_index,
				"group": group_index,
				"delta": delta,
				"delta_str": var_to_str(delta),
				"call": tick_record.get("call", ""),
				"args": tick_record.get("args", {}),
				"return": tick_record.get("return", null),
				"summary": model.get_summary(),
			}
			if not pre_records.is_empty():
				step["pre_ops"] = pre_records
			if spec.has("extra"):
				step["extra"] = (spec["extra"] as Callable).call(model)
			steps.append(step)
			step_index += 1

	var source_summary: Dictionary = model.get_summary()
	var fresh = (spec["script"] as GDScript).new()
	var fresh_prepare: String = str(spec.get("round_trip_prepare_desc", "configure with the same config"))
	(spec.get("round_trip_prepare", configure) as Callable).call(fresh)
	var apply_result: Variant = fresh.apply_summary(source_summary.duplicate(true))
	var restored_summary: Dictionary = fresh.get_summary()
	var equal: bool = writer.deep_equal(writer.canonical(source_summary), writer.canonical(restored_summary))
	var diffs: Array = []
	if not equal:
		writer.diff_paths(writer.canonical(source_summary), writer.canonical(restored_summary), "$", diffs, 30)

	var fixture: Dictionary = {
		"schema": "parity.models.tick.v1",
		"model": model_name,
		"script": (spec["script"] as GDScript).resource_path,
		"reference_smoke": spec.get("smoke", ""),
		"notes": spec.get("notes", []),
		"construct": "%s.new()" % (spec["script"] as GDScript).resource_path,
		"configure_call": spec.get("configure_desc", ""),
		"config": spec.get("config", null),
		"summary_after_configure": summary_after_configure,
		"setup": setup_records,
		"step_groups": [[var_to_str(1.0 / 60.0), 10], ["0.35", 5], ["3.0", 3], ["5.0", 2]],
		"steps": steps,
		"round_trip": {
			"description": "source = get_summary() after the last step; fresh = %s.new(); %s; fresh.apply_summary(source); restored = fresh.get_summary()" % [(spec["script"] as GDScript).resource_path, fresh_prepare],
			"source_summary": source_summary,
			"apply_summary_return": apply_result,
			"restored_summary": restored_summary,
			"equal": equal,
			"differences_source_vs_restored": diffs,
		},
	}
	summary[model_name] = {"steps": steps.size(), "round_trip_equal": equal}
	return writer.write_json("models/%s_tick_fixture.json" % model_name, fixture, true)


func _ctx_tick(context_for_group: Callable) -> Callable:
	return func(model, delta: float, group: int) -> Dictionary:
		var context: Dictionary = context_for_group.call(group)
		var ret: Variant = model.tick(delta, context.duplicate(true))
		return {"call": "tick(delta, context)", "args": {"context": context}, "return": ret}


func _plain_tick() -> Callable:
	return func(model, delta: float, _group: int) -> Dictionary:
		var ret: Variant = model.tick(delta)
		return {"call": "tick(delta)", "args": {}, "return": ret}


func _add_food(model, item_id: String, config: Dictionary) -> Variant:
	model.add_food(item_id, config.duplicate(true))
	return null


func _web_tick(model, delta: float, group: int) -> Dictionary:
	var contact: bool = group == 2
	var ret: Variant = model.tick(delta, contact)
	return {"call": "tick(delta, contact) -> hull damage", "args": {"contact": contact}, "return": ret}


func _break_reactor(model) -> Variant:
	model.get_system("power").get_subcomponent("reactor_core").health = 0.0
	return null


func _ship_advance(model, delta: float, _group: int) -> Dictionary:
	model.advance(delta)
	return {"call": "advance(delta)", "args": {}, "return": null}


func _ship_extra(model) -> Dictionary:
	return {
		"status_summary": model.get_status_summary(),
		"life_support_oxygen": model.get_system("life_support").get_oxygen_state().oxygen,
	}


func _set_prop(prop: String, value: Variant) -> Dictionary:
	return {"op": "set %s" % prop, "args": {prop: value}, "call": func(m): m.set(prop, value)}


func _specs() -> Array:
	var specs: Array = []

	# --- oxygen_state ---
	var oxygen_config: Dictionary = {
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 3.5,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	}
	var oxygen_contexts: Array = [
		{"player_in_breach_zone": true},
		{"player_in_breach_zone": false},
		{"field_atmosphere": true, "player_in_breach_zone": false},
		{"player_in_breach_zone": true},
	]
	specs.append({
		"name": "oxygen_state",
		"script": OxygenStateScript,
		"smoke": "res://scripts/validation/oxygen_state_smoke.gd",
		"config": oxygen_config,
		"configure_desc": "configure(config)",
		"configure": func(m): m.configure(oxygen_config.duplicate(true)),
		"tick": _ctx_tick(func(g): return oxygen_contexts[g]),
		"notes": ["Context per step group: breach drain -> regen -> field_atmosphere drain -> breach drain (the smoke's three tick shapes)."],
	})

	# --- fire (FireSuppressionState is the authoritative fire model; fire_state.gd was retired) ---
	var fire_config: Dictionary = {
		"compartments": ["bridge", "engineering", "hydroponics", "cargo"],
		"suppressant_units": 100.0,
		"suppression_rate_per_second": 25.0,
		"power_threshold": 0.5,
		"adjacency": {
			"bridge": ["engineering"],
			"engineering": ["bridge", "hydroponics", "cargo"],
			"hydroponics": ["engineering"],
			"cargo": ["engineering"],
		},
		"spread_rate_per_second": 0.15,
		"ignition_rate_per_second": 0.2,
		"cascade_rate_per_second": 0.5,
		"arc_compartment": "engineering",
	}
	var fire_contexts: Array = [
		{"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false},
		{"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": ["cargo"], "damaged_compartments": [], "arc_arcing": false},
		{"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": ["hydroponics"], "arc_arcing": true},
		{"powered_ratio": 1.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false},
	]
	specs.append({
		"name": "fire_suppression_state",
		"script": FireSuppressionStateScript,
		"smoke": "res://scripts/validation/fire_suppression_state_smoke.gd",
		"config": fire_config,
		"configure_desc": "configure(config)",
		"configure": func(m): m.configure(fire_config.duplicate(true)),
		"setup": [{"op": "ignite", "args": {"compartment_id": "engineering", "intensity": 1.0}, "call": func(m): return m.ignite("engineering", 1.0)}],
		"tick": _ctx_tick(func(g): return fire_contexts[g]),
		"notes": [
			"There is no fire_state.gd any more: playable_generated_ship.gd says the timer-based FireState is retired and FireSuppressionState (ADR-0041) is the single fire model.",
			"Contexts per step group: idle/persist -> spread with cargo vented -> hydroponics damaged + arc cascade -> powered auto-suppression (all shapes from the smoke).",
		],
	})

	# --- electrical_arc_state ---
	var arc_config: Dictionary = {
		"zone_ids": ["side_corridor_arc"],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	}
	specs.append({
		"name": "electrical_arc_state",
		"script": ElectricalArcStateScript,
		"smoke": "res://scripts/validation/electrical_arc_state_smoke.gd",
		"config": arc_config,
		"configure_desc": "configure(config)",
		"configure": func(m): m.configure(arc_config.duplicate(true)),
		"tick": _plain_tick(),
		"round_trip_prepare_desc": "no configure (the smoke restores into a bare ElectricalArcState.new())",
		"round_trip_prepare": func(_m): pass,
	})

	# --- radiation_state ---
	specs.append({
		"name": "radiation_state",
		"script": RadiationStateScript,
		"smoke": "res://scripts/validation/radiation_state_smoke.gd",
		"config": {},
		"configure_desc": "configure({})",
		"configure": func(m): m.configure({}),
		"setup": [{"op": "set in_radiation_zone", "args": {"in_radiation_zone": true}, "call": func(m): m.in_radiation_zone = true}],
		"pre_step": func(group, index): return [_set_prop("in_radiation_zone", false)] if group == 3 and index == 0 else [],
		"tick": _plain_tick(),
		"notes": ["in_radiation_zone=true for groups 0-2, set false before the first 5.0s step (decay), as the smoke toggles the property."],
	})

	# --- vitals_state ---
	var vitals_contexts: Array = [
		{"moving": true},
		{"moving": false, "temperature_thirst_mult": 1.5},
		{"moving": true, "radiation_health_drain": 2.0},
		{"moving": false, "fire_health_drain": 4.0, "sanity_stamina_recovery_mult": 0.5},
	]
	specs.append({
		"name": "vitals_state",
		"script": VitalsStateScript,
		"smoke": "res://scripts/validation/vitals_state_smoke.gd",
		"config": {},
		"configure_desc": "configure({})",
		"configure": func(m): m.configure({}),
		"tick": _ctx_tick(func(g): return vitals_contexts[g]),
		"notes": ["Context keys per group are the ones the smoke exercises (moving, temperature_thirst_mult, radiation_health_drain, fire_health_drain, sanity_stamina_recovery_mult)."],
	})

	# --- sanity_state ---
	specs.append({
		"name": "sanity_state",
		"script": SanityStateScript,
		"smoke": "res://scripts/validation/sanity_state_smoke.gd",
		"config": {},
		"configure_desc": "configure({})",
		"configure": func(m): m.configure({}),
		"setup": [{"op": "set in_safe_zone", "args": {"in_safe_zone": false}, "call": func(m): m.in_safe_zone = false}],
		"pre_step": func(group, index): return [_set_prop("in_safe_zone", true)] if group == 3 and index == 0 else [],
		"tick": _plain_tick(),
		"notes": ["in_safe_zone=false (drain) for groups 0-2, true (recovery) from the first 5.0s step."],
	})

	# --- body_temperature_state ---
	specs.append({
		"name": "body_temperature_state",
		"script": BodyTemperatureStateScript,
		"smoke": "res://scripts/validation/body_temperature_state_smoke.gd",
		"config": {},
		"configure_desc": "configure({})",
		"configure": func(m): m.configure({}),
		"setup": [{"op": "set in_extreme_zone", "args": {"in_extreme_zone": true}, "call": func(m): m.in_extreme_zone = true}],
		"pre_step": func(group, index): return [_set_prop("in_extreme_zone", false)] if group == 3 and index == 0 else [],
		"tick": _plain_tick(),
		"notes": ["in_extreme_zone=true for groups 0-2, false from the first 5.0s step. tick(delta) with the default empty context, as the smoke calls it."],
	})

	# --- spoilage_state ---
	var ration: Dictionary = {
		"display_name": "Ration Pack",
		"spoilage_seconds": 100.0,
		"hunger_restore": 15.0,
		"thirst_restore": 5.0,
		"sanity_restore": 2.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.6,
		"rotten_multiplier": 0.2,
		"rotten_sickness_risk": 0.25,
	}
	var protein: Dictionary = {
		"display_name": "Scavenged Protein",
		"spoilage_seconds": 200.0,
		"hunger_restore": 20.0,
		"thirst_restore": 0.0,
		"sanity_restore": 0.0,
		"fresh_multiplier": 1.0,
		"stale_multiplier": 0.5,
		"rotten_multiplier": 0.1,
		"rotten_sickness_risk": 0.35,
	}
	specs.append({
		"name": "spoilage_state",
		"script": SpoilageStateScript,
		"smoke": "res://scripts/validation/spoilage_state_smoke.gd",
		"config": null,
		"configure_desc": "none (SpoilageState has no configure(); foods are added in setup)",
		"configure": func(_m): pass,
		"setup": [
			{"op": "add_food", "args": {"item_id": "ration_pack", "config": ration}, "call": _add_food.bind("ration_pack", ration)},
			{"op": "add_food", "args": {"item_id": "scavenged_protein", "config": protein}, "call": _add_food.bind("scavenged_protein", protein)},
		],
		"tick": _plain_tick(),
		"round_trip_prepare_desc": "no setup (the smoke restores into a bare SpoilageState.new())",
		"round_trip_prepare": func(_m): pass,
	})

	# --- hydroponics_state ---
	var crop: Dictionary = {
		"crop_id": "hydroponic_greens",
		"display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 120.0,
		"water_cost": 2.0,
		"power_cost": 3.0,
		"required_skill_level": 0,
	}
	specs.append({
		"name": "hydroponics_state",
		"script": HydroponicsStateScript,
		"smoke": "res://scripts/validation/hydroponics_state_smoke.gd",
		"config": null,
		"configure_desc": "none (the smoke notes plant() calls configure() internally; do not pre-configure)",
		"configure": func(_m): pass,
		"setup": [{"op": "plant", "args": {"crop_config": crop, "skill_level": 0, "available_water": 5.0, "available_power": 5.0}, "call": func(m): return m.plant(crop.duplicate(true), 0, 5.0, 5.0)}],
		"tick": _plain_tick(),
		"round_trip_prepare_desc": "no configure (the smoke restores into a bare HydroponicsState.new())",
		"round_trip_prepare": func(_m): pass,
		"notes": ["Total simulated time is 20.9s < growth_seconds 120, so the crop stays PLANTED (smoke config kept verbatim)."],
	})

	# --- web_infestation_state ---
	specs.append({
		"name": "web_infestation_state",
		"script": WebInfestationStateScript,
		"smoke": "res://scripts/validation/web_infestation_state_smoke.gd",
		"config": {},
		"configure_desc": "configure({})",
		"configure": func(m): m.configure({}),
		"pre_step": func(group, index): return [{"op": "cut_free", "args": {}, "call": func(m): m.cut_free()}] if group == 3 and index == 0 else [],
		"tick": _web_tick,
		"notes": ["contact=false except group 2 (3.0s steps) where contact=true; cut_free() before the first 5.0s step so coverage recedes."],
	})

	# --- ship_systems_manager ---
	var defs: Dictionary = ShipSystemsManagerScript.new().load_definitions()
	specs.append({
		"name": "ship_systems_manager",
		"script": ShipSystemsManagerScript,
		"smoke": "res://scripts/validation/ship_systems_manager_smoke.gd",
		"config": {"definitions_path": ShipSystemsManagerScript.DEFINITIONS_PATH, "condition": 1, "seed_value": 4242},
		"configure_desc": "configure(load_definitions(), 1, 4242)  # DAMAGED, seeded damage rolls",
		"configure": func(m): m.configure(defs.duplicate(true), 1, 4242),
		"setup": [{"op": "get_system(\"power\").get_subcomponent(\"reactor_core\").health = 0.0", "args": {"system": "power", "subcomponent": "reactor_core", "health": 0.0}, "call": _break_reactor}],
		"tick": _ship_advance,
		"extra": _ship_extra,
		"round_trip_prepare_desc": "configure(load_definitions(), 0, 4242) (pristine, as the smoke's dst instance)",
		"round_trip_prepare": func(m): m.configure(defs.duplicate(true), 0, 4242),
		"notes": ["Power knocked out in setup (as in the smoke's advance() case) so life support cascades offline and drains oxygen.", "definitions copied to models/inputs/ship_systems_definitions.json"],
	})
	return specs
