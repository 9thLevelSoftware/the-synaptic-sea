extends RefCounted
class_name InventoryState

## Player-global inventory: quantitied, categorized (part/supply/tool), weight-capped.
## Pure model; never touches the scene tree. Tools are category 'tool' items, exposed
## through legacy shims (add_tool/has_tool/tool_ids/get_drain_multiplier) so OxygenState,
## ToolPickup, and the junction gate are untouched. Round-trips via get/apply_summary.

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const MAX_WEIGHT: float = 50.0
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

var items: Dictionary = {}          # item_id: String -> quantity: int
var _definitions: Dictionary = {}   # item_id -> def Dictionary (merged)

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	_definitions.clear()
	# Tools first (so item_definitions can override if ever needed); tool defs get a
	# synthetic 'tool' category + default weight while preserving their 'effect' field.
	var tool_defs: Dictionary = _read_json_dict(TOOL_DEFINITIONS_PATH)
	for tool_id in tool_defs:
		var def: Dictionary = (tool_defs[tool_id] as Dictionary).duplicate(true)
		def["category"] = "tool"
		if not def.has("weight"):
			def["weight"] = DEFAULT_TOOL_WEIGHT
		_definitions[tool_id] = def
	var item_defs: Dictionary = _read_json_dict(ITEM_DEFINITIONS_PATH)
	for item_id in item_defs:
		_definitions[item_id] = item_defs[item_id]

func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# --- definition helpers ---

func get_definition(item_id: String) -> Dictionary:
	var def: Variant = _definitions.get(item_id, {})
	return def if def is Dictionary else {}

func get_category(item_id: String) -> String:
	return str(get_definition(item_id).get("category", ""))

func get_weight_each(item_id: String) -> float:
	# Unknown items weigh 0 so a foreign save round-trips without corrupting the cap.
	return float(get_definition(item_id).get("weight", 0.0))

func _max_stack(item_id: String) -> int:
	return int(get_definition(item_id).get("max_stack", DEFAULT_MAX_STACK))

func get_display_name(item_id: String) -> String:
	var name: String = str(get_definition(item_id).get("display_name", ""))
	return name if not name.is_empty() else item_id.replace("_", " ").capitalize()

# --- item API ---

func get_max_weight() -> float:
	return MAX_WEIGHT

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items:
		total += get_weight_each(item_id) * float(items[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Adds up to qty, honoring max_stack and the carry-weight cap. Returns the
## quantity actually added (0 if none fit). Items with weight 0 ignore the cap.
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, _max_stack(item_id) - current)
	var want: int = min(qty, stack_room)
	if want <= 0:
		return 0
	var w: float = get_weight_each(item_id)
	if w > 0.0:
		var remaining: float = get_max_weight() - get_total_weight()
		var weight_room: int = int(floor(remaining / w + 0.0001))
		want = min(want, max(0, weight_room))
	if want <= 0:
		return 0
	items[item_id] = current + want
	return want

func remove_item(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var removed: int = min(qty, current)
	if removed <= 0:
		return 0
	if removed >= current:
		items.erase(item_id)
	else:
		items[item_id] = current - removed
	return removed

func get_items_by_category(category: String) -> Array:
	var out: Array = []
	var ids: Array = items.keys()
	ids.sort()
	for item_id in ids:
		if get_category(item_id) == category:
			out.append({
				"id": item_id,
				"quantity": get_quantity(item_id),
				"weight_each": get_weight_each(item_id),
			})
	return out

func reset() -> void:
	items.clear()
	_load_definitions()

# --- legacy tool shims (REQ-007 consumers depend on these) ---

var tool_ids: Array[String]:
	get:
		var out: Array[String] = []
		var ids: Array = items.keys()
		ids.sort()
		for item_id in ids:
			if get_category(item_id) == "tool":
				out.append(String(item_id))
		return out

func add_tool(tool_id: String) -> bool:
	if tool_id.is_empty() or get_quantity(tool_id) > 0:
		return false
	return add_item(tool_id, 1) == 1

func has_tool(tool_id: String) -> bool:
	return get_quantity(tool_id) > 0 and get_category(tool_id) == "tool"

func remove_tool(tool_id: String) -> bool:
	return remove_item(tool_id, 1) == 1

func get_drain_multiplier() -> float:
	return 0.5 if has_tool("portable_oxygen_pump") else 1.0

# --- save/load ---

func get_summary() -> Dictionary:
	var effects: Array[Dictionary] = []
	for tool_id in tool_ids:
		var effect: Variant = get_definition(tool_id).get("effect", {})
		if effect is Dictionary:
			effects.append({
				"tool_id": tool_id,
				"type": str(effect.get("type", "")),
				"value": effect.get("value", 1.0),
			})
	return {
		"items": items.duplicate(true),
		"tool_ids": tool_ids.duplicate(),          # derived; kept for backward compat
		"active_effects": effects,
		"drain_multiplier": get_drain_multiplier(), # OxygenState consumes this
		"total_weight": get_total_weight(),
		"max_weight": get_max_weight(),
	}

## Accepts the new ("items") shape AND the legacy ("tool_ids"-only) shape.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	items.clear()
	var items_variant: Variant = summary.get("items", null)
	if typeof(items_variant) == TYPE_DICTIONARY:
		for item_id in (items_variant as Dictionary):
			items[String(item_id)] = int((items_variant as Dictionary)[item_id])
	else:
		# Legacy save: reconstruct tool items from tool_ids.
		var legacy_ids: Variant = summary.get("tool_ids", [])
		if typeof(legacy_ids) == TYPE_ARRAY:
			for tool_id in (legacy_ids as Array):
				items[String(tool_id)] = 1
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	# Tools first, preserving the REQ-007 markers the inventory HUD smoke greps.
	for tool_id in tool_ids:
		lines.append("Tool: %s" % get_display_name(tool_id))
		lines.append("tool=%s" % tool_id)
		if tool_id == "portable_oxygen_pump" and get_drain_multiplier() != 1.0:
			lines.append("drain_multiplier=%s" % str(get_drain_multiplier()))
	# Then non-tool items + a weight readout for the loot HUD.
	for cat in ["part", "supply"]:
		for entry in get_items_by_category(cat):
			lines.append("item=%s x%d" % [String(entry["id"]), int(entry["quantity"])])
	lines.append("weight=%s/%s" % [str(snappedf(get_total_weight(), 0.1)), str(get_max_weight())])
	return lines
