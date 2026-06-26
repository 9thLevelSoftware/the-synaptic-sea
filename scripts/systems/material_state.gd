extends RefCounted
class_name MaterialState

## Pure model for material inventory with per-stack quality tracking.
## Materials are also items (shared IDs with item_definitions.json).
## This model tracks quality per material ID; quantities live in InventoryState.
## Never touches the scene tree.

const MATERIAL_DEFINITIONS_PATH: String = "res://data/materials/material_definitions.json"

var _definitions: Dictionary = {}
var _material_quality: Dictionary = {}   # material_id -> quality float [0.0, 1.0]
var _loaded: bool = false

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	if not FileAccess.file_exists(MATERIAL_DEFINITIONS_PATH):
		return
	var file := FileAccess.open(MATERIAL_DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var root: Dictionary = parsed as Dictionary
		var mats: Variant = root.get("materials", {})
		if mats is Dictionary:
			_definitions = mats as Dictionary
	_loaded = true

func has_definition(material_id: String) -> bool:
	return _definitions.has(material_id)

func get_definition(material_id: String) -> Dictionary:
	var def: Variant = _definitions.get(material_id, {})
	return def if def is Dictionary else {}

func get_display_name(material_id: String) -> String:
	var def: Dictionary = get_definition(material_id)
	var name: String = str(def.get("display_name", ""))
	return name if not name.is_empty() else material_id.replace("_", " ").capitalize()

func get_category(material_id: String) -> String:
	return str(get_definition(material_id).get("category", ""))

func get_weight(material_id: String) -> float:
	return float(get_definition(material_id).get("weight", 0.0))

func get_max_stack(material_id: String) -> int:
	return int(get_definition(material_id).get("max_stack", 99))

func get_base_quality(material_id: String) -> float:
	return clampf(float(get_definition(material_id).get("base_quality", 0.5)), 0.0, 1.0)

func get_all_material_ids() -> Array:
	var ids: Array = _definitions.keys()
	ids.sort()
	return ids

func count_defined() -> int:
	return _definitions.size()

# --- quality tracking ---

func set_quality(material_id: String, quality: float) -> void:
	if material_id.is_empty():
		return
	_material_quality[material_id] = clampf(quality, 0.0, 1.0)

func get_quality(material_id: String) -> float:
	return clampf(float(_material_quality.get(material_id, get_base_quality(material_id))), 0.0, 1.0)

func remove_quality(material_id: String) -> void:
	_material_quality.erase(material_id)

func reset() -> void:
	_material_quality.clear()
	_load_definitions()

# --- average quality for a recipe's ingredient list ---
## Given an ingredients dict {material_id: qty}, returns the average quality
## of those materials weighted by quantity. Falls back to base_quality if
## no per-stack quality is set.
func average_ingredient_quality(ingredients: Dictionary) -> float:
	if ingredients.is_empty():
		return 0.5
	var total_qty: int = 0
	var weighted: float = 0.0
	for mat_id in ingredients:
		var qty: int = maxi(1, int(ingredients[mat_id]))
		var q: float = get_quality(str(mat_id))
		weighted += q * float(qty)
		total_qty += qty
	if total_qty <= 0:
		return 0.5
	return clampf(weighted / float(total_qty), 0.0, 1.0)

# --- save/load ---

func get_summary() -> Dictionary:
	return {
		"material_quality": _material_quality.duplicate(),
		"defined_count": count_defined(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var mq: Variant = summary.get("material_quality", {})
	if mq is Dictionary:
		for mat_id in (mq as Dictionary):
			var new_q: float = clampf(float((mq as Dictionary)[mat_id]), 0.0, 1.0)
			var old_q: float = get_quality(str(mat_id))
			if absf(new_q - old_q) > 0.001:
				_material_quality[str(mat_id)] = new_q
				changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var ids: Array = _material_quality.keys()
	ids.sort()
	for mat_id in ids:
		lines.append("%s q=%.2f" % [get_display_name(str(mat_id)), get_quality(str(mat_id))])
	return lines
