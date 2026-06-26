extends RefCounted
class_name EffectDispatcher

## Shared effect executor for consumables, medicine, stimulants, ammo, and
## utility items. Pure-model only: mutates the supplied state objects, never the
## scene tree.

const DEFINITIONS_PATH: String = "res://data/items/effect_definitions.json"

var effect_definitions: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	effect_definitions = _load_definitions()
	if config.has("effect_definitions") and config["effect_definitions"] is Dictionary:
		effect_definitions = (config["effect_definitions"] as Dictionary).duplicate(true)

func dispatch_effect(effect_id: String, context: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	if effect_definitions.is_empty():
		effect_definitions = _load_definitions()
	var raw: Variant = effect_definitions.get(effect_id, {})
	if not (raw is Dictionary):
		return {"ok": false, "effect_id": effect_id, "reason": "unknown_effect"}
	var definition: Dictionary = (raw as Dictionary).duplicate(true)
	for key in overrides:
		definition[key] = overrides[key]
	return dispatch_inline(effect_id, definition, context)

func dispatch_inline(effect_id: String, definition: Dictionary, context: Dictionary) -> Dictionary:
	var kind: String = str(definition.get("kind", ""))
	var result: Dictionary = {"ok": true, "effect_id": effect_id, "kind": kind}
	match kind:
		"vitals_delta":
			var vitals = context.get("vitals_state", null)
			if vitals == null or not vitals.has_method("apply_delta"):
				return _missing_target(effect_id, "vitals_state")
			vitals.apply_delta({
				"health": float(definition.get("health", 0.0)),
				"stamina": float(definition.get("stamina", 0.0)),
				"hunger": float(definition.get("hunger", 0.0)),
				"thirst": float(definition.get("thirst", 0.0)),
			})
			result["summary"] = vitals.get_summary()
		"sanity_delta":
			var sanity = context.get("sanity_state", null)
			if sanity == null or not sanity.has_method("adjust_sanity"):
				return _missing_target(effect_id, "sanity_state")
			sanity.adjust_sanity(float(definition.get("amount", 0.0)))
			result["summary"] = sanity.get_summary()
		"radiation_delta":
			var radiation = context.get("radiation_state", null)
			if radiation == null or not radiation.has_method("adjust_radiation"):
				return _missing_target(effect_id, "radiation_state")
			radiation.adjust_radiation(float(definition.get("amount", 0.0)))
			result["summary"] = radiation.get_summary()
		"temperature_delta":
			var temp = context.get("body_temperature_state", null)
			if temp == null or not temp.has_method("adjust_temperature"):
				return _missing_target(effect_id, "body_temperature_state")
			temp.adjust_temperature(float(definition.get("amount", 0.0)))
			result["summary"] = temp.get_summary()
		"add_status":
			var statuses = context.get("status_effects_state", null)
			if statuses == null or not statuses.has_method("add_effect"):
				return _missing_target(effect_id, "status_effects_state")
			var status_id: String = str(definition.get("status_id", effect_id))
			var duration: float = maxf(0.1, float(definition.get("duration", 1.0)))
			var stacks: int = max(1, int(definition.get("stacks", 1)))
			statuses.add_effect(status_id, duration, stacks)
			result["status_id"] = status_id
			result["summary"] = statuses.get_summary()
		"cure_status":
			var statuses = context.get("status_effects_state", null)
			if statuses == null or not statuses.has_method("remove_effect"):
				return _missing_target(effect_id, "status_effects_state")
			var cured: Array = []
			var ids: Variant = definition.get("status_ids", [])
			if ids is Array:
				for status_id_variant in ids:
					var status_id: String = str(status_id_variant)
					if statuses.remove_effect(status_id, 9999):
						cured.append(status_id)
			result["cured"] = cured
			result["summary"] = statuses.get_summary()
		"ammo_reserve":
			var ammo = context.get("ammo_state", null)
			if ammo == null or not ammo.has_method("add_ammo"):
				return _missing_target(effect_id, "ammo_state")
			var ammo_kind: String = str(definition.get("ammo_kind", ""))
			var amount: int = max(0, int(definition.get("amount", 0)))
			result["added"] = ammo.add_ammo(ammo_kind, amount)
			result["summary"] = ammo.get_summary()
		_:
			result["ok"] = false
			result["reason"] = "unsupported_kind"
	return result

func get_summary() -> Dictionary:
	return {
		"effect_count": effect_definitions.size(),
		"effect_ids": effect_definitions.keys(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	if summary.has("effect_definitions") and summary["effect_definitions"] is Dictionary:
		effect_definitions = (summary["effect_definitions"] as Dictionary).duplicate(true)
		return true
	return false

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Effects: %d" % effect_definitions.size())
	return lines

func _load_definitions() -> Dictionary:
	if not FileAccess.file_exists(DEFINITIONS_PATH):
		return {}
	var text: String = FileAccess.get_file_as_string(DEFINITIONS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _missing_target(effect_id: String, target: String) -> Dictionary:
	return {"ok": false, "effect_id": effect_id, "reason": "missing_target", "target": target}
