extends RefCounted
class_name UtilityItemResolver

## Lightweight state for utility-item use. Utility items resolve through the same
## shared EffectDispatcher as medicine/stimulants, then retain a visible summary.

var last_item_id: String = ""
var last_note: String = ""
var active_flags: Dictionary = {}

func configure(config: Dictionary = {}) -> void:
	last_item_id = ""
	last_note = ""
	active_flags.clear()
	var raw: Variant = config.get("active_flags", {})
	if raw is Dictionary:
		active_flags = (raw as Dictionary).duplicate(true)

func use_item(item_id: String, definition: Dictionary, dispatcher, context: Dictionary) -> Dictionary:
	last_item_id = item_id
	last_note = str(definition.get("use_note", ""))
	var effects: Variant = definition.get("effects", [])
	if effects is Array:
		for effect_id_variant in effects:
			dispatcher.dispatch_effect(str(effect_id_variant), context)
	var utility_flag: String = str(definition.get("utility_flag", ""))
	if not utility_flag.is_empty():
		active_flags[utility_flag] = {
			"item_id": item_id,
			"note": last_note,
			"count": int(active_flags.get(utility_flag, {}).get("count", 0)) + 1 if active_flags.get(utility_flag, {}) is Dictionary else 1,
		}
	return {"ok": true, "item_id": item_id, "utility_flag": utility_flag, "note": last_note}

## Domain 5: a utility flag is consumed when its promised bypass fires (e.g. a
## sealed hatch opened by lockpick/hack_chip). Returns true if a flag was removed.
func consume_flag(flag: String) -> bool:
	if flag.is_empty() or not active_flags.has(flag):
		return false
	active_flags.erase(flag)
	return true

func get_summary() -> Dictionary:
	return {
		"last_item_id": last_item_id,
		"last_note": last_note,
		"active_flags": active_flags.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	last_item_id = str(summary.get("last_item_id", last_item_id))
	last_note = str(summary.get("last_note", last_note))
	active_flags.clear()
	var raw: Variant = summary.get("active_flags", {})
	if raw is Dictionary:
		active_flags = (raw as Dictionary).duplicate(true)
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if not last_item_id.is_empty():
		lines.append("Utility: %s" % last_item_id)
	if not last_note.is_empty():
		lines.append("  %s" % last_note)
	return lines
