extends RefCounted
class_name StimulantState

## Timed stimulant buff tracker. Active debuffs/buffs are mirrored into
## StatusEffectsState through EffectDispatcher, but this model owns the use
## cadence, tolerance scaling, and expiry handoff into AddictionState.

var active_stims: Array = []
var last_used_item: String = ""

func configure(config: Dictionary = {}) -> void:
	active_stims = []
	last_used_item = ""
	var raw: Variant = config.get("active_stims", [])
	if raw is Array:
		active_stims = (raw as Array).duplicate(true)

func use_stimulant(item_id: String, definition: Dictionary, dispatcher, addiction_state, context: Dictionary) -> Dictionary:
	last_used_item = item_id
	var tolerance: float = addiction_state.get_tolerance(item_id) if addiction_state != null else 0.0
	var duration_scale: float = clampf(1.0 - tolerance * 0.08, 0.45, 1.0)
	var duration: float = maxf(1.0, float(definition.get("stim_duration", 20.0)) * duration_scale)
	var applied: Array[String] = []
	var effects: Variant = definition.get("effects", [])
	if effects is Array:
		for effect_id_variant in effects:
			var effect_id: String = str(effect_id_variant)
			var res: Dictionary = dispatcher.dispatch_effect(effect_id, context, {"duration": duration})
			if bool(res.get("ok", false)):
				applied.append(effect_id)
	active_stims.append({
		"item_id": item_id,
		"remaining": duration,
		"base_duration": float(definition.get("stim_duration", duration)),
		"effects": applied.duplicate(),
		"withdrawal_effects": (definition.get("withdrawal_effects", []) as Array).duplicate() if definition.get("withdrawal_effects", []) is Array else [],
	})
	if addiction_state != null:
		addiction_state.record_dose(item_id, definition)
	return {"ok": true, "item_id": item_id, "duration": duration, "effects": applied}

func tick(delta_seconds: float, addiction_state, context: Dictionary) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	var status_effects_state = context.get("status_effects_state", null)
	for i in range(active_stims.size() - 1, -1, -1):
		var entry: Dictionary = active_stims[i]
		entry["remaining"] = maxf(0.0, float(entry.get("remaining", 0.0)) - delta_seconds)
		changed = true
		if float(entry.get("remaining", 0.0)) <= 0.0:
			active_stims.remove_at(i)
			if addiction_state != null:
				addiction_state.activate_withdrawal_if_needed(str(entry.get("item_id", "")), status_effects_state)
		else:
			active_stims[i] = entry
	return changed

func has_active_stim(item_id: String = "") -> bool:
	for entry_variant in active_stims:
		var entry: Dictionary = entry_variant
		if item_id.is_empty() or str(entry.get("item_id", "")) == item_id:
			return true
	return false

func get_summary() -> Dictionary:
	return {
		"active_stims": active_stims.duplicate(true),
		"last_used_item": last_used_item,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"active_stims": summary.get("active_stims", [])})
	last_used_item = str(summary.get("last_used_item", last_used_item))
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for entry_variant in active_stims:
		var entry: Dictionary = entry_variant
		lines.append("Stim %s %.1fs" % [str(entry.get("item_id", "")), float(entry.get("remaining", 0.0))])
	return lines
