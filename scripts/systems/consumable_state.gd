extends RefCounted
class_name ConsumableState

## Shared consumable/effect pipeline. Owns hotbar slot assignments and routes use
## requests into MedicineState / StimulantState / AmmoState / UtilityItemResolver
## through one EffectDispatcher.

const HOTBAR_SLOT_COUNT: int = 3
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const FoodStateScript := preload("res://scripts/systems/food_state.gd")

var definitions: Dictionary = {}
var hotbar_slots: Array[String] = []
var last_result: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	definitions = ItemDefsScript.load_definitions()
	hotbar_slots = []
	for _i in range(HOTBAR_SLOT_COUNT):
		hotbar_slots.append("")
	var raw_slots: Variant = config.get("hotbar_slots", [])
	if raw_slots is Array:
		for i in range(min(HOTBAR_SLOT_COUNT, (raw_slots as Array).size())):
			hotbar_slots[i] = str((raw_slots as Array)[i])
	last_result = {}

func has_use_action(item_id: String) -> bool:
	var definition: Dictionary = ItemDefsScript.get_definition(definitions, item_id)
	var category: String = str(definition.get("category", ""))
	return category in ["medicine", "stimulant", "ammo", "utility", "food", "drink"]

func assign_hotbar_slot(slot_index: int, item_id: String) -> bool:
	if slot_index < 0 or slot_index >= HOTBAR_SLOT_COUNT:
		return false
	if not item_id.is_empty() and not has_use_action(item_id):
		return false
	hotbar_slots[slot_index] = item_id
	return true

func use_hotbar_slot(slot_index: int, inventory_state, pipeline_context: Dictionary) -> Dictionary:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return {"ok": false, "reason": "bad_slot"}
	return use_item(hotbar_slots[slot_index], inventory_state, pipeline_context, false)

func use_item(item_id: String, inventory_state, pipeline_context: Dictionary, use_all: bool = false) -> Dictionary:
	if item_id.is_empty() or inventory_state == null:
		return {"ok": false, "reason": "missing_item"}
	var quantity: int = int(inventory_state.get_quantity(item_id))
	if quantity <= 0:
		return {"ok": false, "reason": "missing_quantity", "item_id": item_id}
	var definition: Dictionary = ItemDefsScript.get_definition(definitions, item_id)
	if definition.is_empty():
		return {"ok": false, "reason": "unknown_definition", "item_id": item_id}
	var category: String = str(definition.get("category", ""))
	var iterations: int = quantity if use_all else 1
	iterations = max(1, iterations)
	var successes: int = 0
	var results: Array = []
	for _i in range(iterations):
		if int(inventory_state.get_quantity(item_id)) <= 0:
			break
		var result: Dictionary = _use_once(item_id, category, definition, inventory_state, pipeline_context)
		results.append(result)
		if not bool(result.get("ok", false)):
			break
		successes += 1
	last_result = {
		"item_id": item_id,
		"category": category,
		"use_all": use_all,
		"used": successes,
		"results": results.duplicate(true),
	}
	return {"ok": successes > 0, "item_id": item_id, "used": successes, "results": results.duplicate(true)}

func get_summary() -> Dictionary:
	return {
		"hotbar_slots": hotbar_slots.duplicate(),
		"last_result": last_result.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"hotbar_slots": summary.get("hotbar_slots", [])})
	last_result = (summary.get("last_result", {}) as Dictionary).duplicate(true) if summary.get("last_result", {}) is Dictionary else {}
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(hotbar_slots.size()):
		var item_id: String = hotbar_slots[i]
		if item_id.is_empty():
			lines.append("Hotbar %d: (empty)" % (i + 1))
		else:
			lines.append("Hotbar %d: %s" % [i + 1, ItemDefsScript.display_name(definitions, item_id)])
	return lines

func _use_once(item_id: String, category: String, definition: Dictionary, inventory_state, pipeline_context: Dictionary) -> Dictionary:
	var dispatcher = pipeline_context.get("effect_dispatcher", null)
	match category:
		"medicine":
			var med = pipeline_context.get("medicine_state", null)
			if med == null or dispatcher == null:
				return {"ok": false, "reason": "medicine_pipeline_missing"}
			var med_result: Dictionary = med.use_medicine(item_id, definition, dispatcher, pipeline_context)
			if bool(med_result.get("ok", false)):
				inventory_state.remove_item(item_id, 1)
			return med_result
		"stimulant":
			var stim = pipeline_context.get("stimulant_state", null)
			if stim == null or dispatcher == null:
				return {"ok": false, "reason": "stimulant_pipeline_missing"}
			var stim_result: Dictionary = stim.use_stimulant(item_id, definition, dispatcher, pipeline_context.get("addiction_state", null), pipeline_context)
			if bool(stim_result.get("ok", false)):
				inventory_state.remove_item(item_id, 1)
			return stim_result
		"ammo":
			if dispatcher == null:
				return {"ok": false, "reason": "effect_dispatcher_missing"}
			var ammo = pipeline_context.get("ammo_state", null)
			if ammo == null:
				return {"ok": false, "reason": "ammo_pipeline_missing"}
			var ammo_kind: String = str(definition.get("ammo_kind", ""))
			var before: int = ammo.get_reserve(ammo_kind)
			var ammo_results: Array = []
			var effects: Variant = definition.get("effects", [])
			if effects is Array:
				for effect_id_variant in effects:
					ammo_results.append(dispatcher.dispatch_effect(str(effect_id_variant), pipeline_context))
			var added: int = ammo.get_reserve(ammo_kind) - before
			if added > 0:
				inventory_state.remove_item(item_id, 1)
				return {"ok": true, "item_id": item_id, "ammo_kind": ammo_kind, "added": added, "results": ammo_results}
			return {"ok": false, "reason": "no_ammo_added"}
		"utility":
			var utility = pipeline_context.get("utility_state", null)
			if utility == null or dispatcher == null:
				return {"ok": false, "reason": "utility_pipeline_missing"}
			var utility_result: Dictionary = utility.use_item(item_id, definition, dispatcher, pipeline_context)
			if bool(utility_result.get("ok", false)):
				inventory_state.remove_item(item_id, 1)
			return utility_result
		"food", "drink":
			if dispatcher == null:
				return {"ok": false, "reason": "effect_dispatcher_missing"}
			# Legacy/explicit effects path — kept for any food that declares an effects array.
			var effects: Variant = definition.get("effects", [])
			if effects is Array:
				for effect_id_variant in effects:
					dispatcher.dispatch_effect(str(effect_id_variant), pipeline_context)
			# REQ-FC: apply the food/drink's hunger/thirst/sanity restores to live vitals.
			# Food items carry hunger_restore/thirst_restore/sanity_restore (not an effects
			# array), so without this, eating food was a no-op. Routed through FoodState so the
			# spoilage multiplier is honoured (FRESH baseline until per-stack stage is threaded).
			var restored: Dictionary = _apply_food_restores(definition, pipeline_context)
			inventory_state.remove_item(item_id, 1)
			return {
				"ok": true, "item_id": item_id, "category": category,
				"hunger_restored": float(restored.get("hunger", 0.0)),
				"thirst_restored": float(restored.get("thirst", 0.0)),
				"sanity_restored": float(restored.get("sanity", 0.0)),
			}
	return {"ok": false, "reason": "unsupported_category", "category": category}

## REQ-FC: applies a food/drink definition's spoilage-scaled restores to the live
## vitals_state / sanity_state in the pipeline context. Reuses FoodState so the food
## pillar runs through one model. Returns the applied {hunger, thirst, sanity} amounts.
func _apply_food_restores(definition: Dictionary, pipeline_context: Dictionary) -> Dictionary:
	var food = FoodStateScript.new()
	food.configure(definition)
	var r: Dictionary = food.get_effective_restores()
	var hunger: float = float(r.get("hunger", 0.0))
	var thirst: float = float(r.get("thirst", 0.0))
	var sanity: float = float(r.get("sanity", 0.0))
	var vitals = pipeline_context.get("vitals_state", null)
	if vitals != null and vitals.has_method("apply_delta") and (hunger != 0.0 or thirst != 0.0):
		vitals.apply_delta({"hunger": hunger, "thirst": thirst})
	var sanity_state = pipeline_context.get("sanity_state", null)
	if sanity != 0.0 and sanity_state != null and sanity_state.has_method("adjust_sanity"):
		sanity_state.adjust_sanity(sanity)
	return {"hunger": hunger, "thirst": thirst, "sanity": sanity}
