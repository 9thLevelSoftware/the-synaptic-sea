extends RefCounted
class_name MedicineState

## Stateless helper around medicine definitions. Tracks the last medicine use so
## runtime/UI/save-load can surface what happened.

var last_item_id: String = ""
var last_cured_statuses: Array[String] = []
var last_results: Array = []

func configure(_config: Dictionary = {}) -> void:
	last_item_id = ""
	last_cured_statuses.clear()
	last_results.clear()

func use_medicine(item_id: String, definition: Dictionary, dispatcher, context: Dictionary) -> Dictionary:
	last_item_id = item_id
	last_cured_statuses.clear()
	last_results.clear()
	var effects: Variant = definition.get("effects", [])
	if effects is Array:
		for effect_id_variant in effects:
			var effect_id: String = str(effect_id_variant)
			var res: Dictionary = dispatcher.dispatch_effect(effect_id, context)
			last_results.append(res)
			if res.get("cured", null) is Array:
				for cured in res["cured"]:
					last_cured_statuses.append(str(cured))
	return {
		"ok": true,
		"item_id": item_id,
		"cured_statuses": last_cured_statuses.duplicate(),
		"results": last_results.duplicate(true),
	}

func get_summary() -> Dictionary:
	return {
		"last_item_id": last_item_id,
		"last_cured_statuses": last_cured_statuses.duplicate(),
		"last_results": last_results.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	last_item_id = str(summary.get("last_item_id", last_item_id))
	last_cured_statuses.clear()
	var raw_cured: Variant = summary.get("last_cured_statuses", [])
	if raw_cured is Array:
		for entry in raw_cured:
			last_cured_statuses.append(str(entry))
	last_results = []
	var raw_results: Variant = summary.get("last_results", [])
	if raw_results is Array:
		last_results = (raw_results as Array).duplicate(true)
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if last_item_id.is_empty():
		return lines
	lines.append("Medicine: %s" % last_item_id)
	if not last_cured_statuses.is_empty():
		lines.append("  cured=%s" % ",".join(last_cured_statuses))
	return lines
