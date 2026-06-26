extends RefCounted
class_name JunkYieldResolver

const JUNK_ITEMS_PATH: String = "res://data/items/junk_items.json"

static func load_definitions() -> Dictionary:
	if not FileAccess.file_exists(JUNK_ITEMS_PATH):
		return {}
	var file := FileAccess.open(JUNK_ITEMS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var root: Dictionary = parsed as Dictionary
		var items_v: Variant = root.get("items", {})
		return items_v if items_v is Dictionary else {}
	return {}

static func yields_for_item(item_id: String, defs: Dictionary = {}) -> Array:
	var catalog: Dictionary = defs if not defs.is_empty() else load_definitions()
	var def_v: Variant = catalog.get(item_id, {})
	if not (def_v is Dictionary):
		return []
	var yields_v: Variant = (def_v as Dictionary).get("yields", [])
	return (yields_v as Array).duplicate(true) if yields_v is Array else []

static func total_material_value(item_id: String, defs: Dictionary = {}) -> int:
	var total: int = 0
	for entry in yields_for_item(item_id, defs):
		if entry is Dictionary:
			total += int((entry as Dictionary).get("quantity", 0))
	return total

static func to_status_line(item_id: String, defs: Dictionary = {}) -> String:
	var yields: Array = yields_for_item(item_id, defs)
	var parts: Array[String] = []
	for entry in yields:
		if entry is Dictionary:
			parts.append("%s x%d" % [str((entry as Dictionary).get("material_id", "")), int((entry as Dictionary).get("quantity", 0))])
	return "%s -> %s" % [item_id, ", ".join(parts)]
