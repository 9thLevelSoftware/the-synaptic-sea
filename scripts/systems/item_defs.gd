extends RefCounted
class_name ItemDefs

## Shared, all-static item-definition lookups. Extracted from InventoryState so
## both the player inventory and the per-ship ShipInventory read one source of
## truth for weights, stack limits, categories, and display names. Tool defs are
## merged first with a synthetic 'tool' category + default weight (preserving the
## original InventoryState merge order and semantics).

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const EQUIPMENT_DEFINITIONS_PATH: String = "res://data/items/equipment_definitions.json"
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

## Merged tool+item definitions. Tools first (so item_definitions can override),
## tool defs get a synthetic 'tool' category + default weight while preserving
## their 'effect' field.
static func load_definitions() -> Dictionary:
	var defs: Dictionary = {}
	var tool_defs: Dictionary = _read_json_dict(TOOL_DEFINITIONS_PATH)
	for tool_id in tool_defs:
		var raw_def: Variant = tool_defs[tool_id]
		if not (raw_def is Dictionary):
			continue   # skip malformed/corrupt tool entries rather than crash on .duplicate(null)
		var def: Dictionary = (raw_def as Dictionary).duplicate(true)
		def["category"] = "tool"
		if not def.has("weight"):
			def["weight"] = DEFAULT_TOOL_WEIGHT
		defs[tool_id] = def
	var item_defs: Dictionary = _read_json_dict(ITEM_DEFINITIONS_PATH)
	for item_id in item_defs:
		if not (item_defs[item_id] is Dictionary):
			continue   # skip malformed/corrupt item entries rather than store a non-dict def
		defs[item_id] = item_defs[item_id]
	var equip_defs: Dictionary = _read_json_dict(EQUIPMENT_DEFINITIONS_PATH)
	for equip_id in equip_defs:
		var raw_equip: Variant = equip_defs[equip_id]
		if not (raw_equip is Dictionary):
			continue   # skip malformed entries rather than crash
		defs[equip_id] = raw_equip
	return defs

static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func get_definition(defs: Dictionary, item_id: String) -> Dictionary:
	var def: Variant = defs.get(item_id, {})
	return def if def is Dictionary else {}

static func category(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("category", ""))

static func weight_each(defs: Dictionary, item_id: String) -> float:
	# Unknown items weigh 0 so a foreign save round-trips without corrupting the cap.
	return float(get_definition(defs, item_id).get("weight", 0.0))

static func max_stack(defs: Dictionary, item_id: String) -> int:
	return int(get_definition(defs, item_id).get("max_stack", DEFAULT_MAX_STACK))

static func display_name(defs: Dictionary, item_id: String) -> String:
	var name: String = str(get_definition(defs, item_id).get("display_name", ""))
	return name if not name.is_empty() else item_id.replace("_", " ").capitalize()

static func equip_slot(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("equip_slot", ""))

static func container_capacity(defs: Dictionary, item_id: String) -> float:
	return float(get_definition(defs, item_id).get("container_capacity", 0.0))

static func effects(defs: Dictionary, item_id: String) -> Array:
	var e: Variant = get_definition(defs, item_id).get("effects", [])
	return e if e is Array else []

static func icon(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("icon", ""))
