extends RefCounted
class_name InventoryState

## Player-global inventory: quantitied, categorized (part/supply/tool), SOFT weight-capped
## (PZ-style: carrying over capacity is allowed and penalized via Heavy Load movement, NOT
## refused — see get_capacity/get_load_ratio/is_over_capacity; add_item gates on max_stack only).
## Pure model; never touches the scene tree. Tools are category 'tool' items, exposed
## through legacy shims (add_tool/has_tool/tool_ids/get_drain_multiplier) so OxygenState,
## ToolPickup, and the junction gate are untouched. Round-trips via get/apply_summary.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const MAX_WEIGHT: float = 50.0
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

var items: Dictionary = {}          # item_id: String -> quantity: int
var bonus_capacity: float = 0.0     # added by worn containers (set by the coordinator)
var weight_reduction: float = 0.0   # saved kg from worn containers (set by the coordinator)
var _definitions: Dictionary = {}   # item_id -> def Dictionary (merged)

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	_definitions = ItemDefsScript.load_definitions()

# --- definition helpers ---

func get_definition(item_id: String) -> Dictionary:
	return ItemDefsScript.get_definition(_definitions, item_id)

func get_category(item_id: String) -> String:
	return ItemDefsScript.category(_definitions, item_id)

func get_weight_each(item_id: String) -> float:
	return ItemDefsScript.weight_each(_definitions, item_id)

func _max_stack(item_id: String) -> int:
	return ItemDefsScript.max_stack(_definitions, item_id)

func get_display_name(item_id: String) -> String:
	return ItemDefsScript.display_name(_definitions, item_id)

# --- item API ---

func get_max_weight() -> float:
	return MAX_WEIGHT

## Effective carry budget = base cap + worn-container bonus (+ future strength).
func get_capacity() -> float:
	return MAX_WEIGHT + bonus_capacity

## Raw weight minus the worn-container weight reduction (saved kg), floored at 0.
## get_total_weight() stays the true mass; this is what encumbrance keys off.
func get_effective_weight() -> float:
	return maxf(0.0, get_total_weight() - weight_reduction)

## effective_weight / capacity. >1.0 means over-encumbered (Heavy Load).
func get_load_ratio() -> float:
	return get_effective_weight() / max(0.0001, get_capacity())

func is_over_capacity() -> bool:
	return get_effective_weight() > get_capacity()

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items:
		total += get_weight_each(item_id) * float(items[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Adds up to qty, honoring max_stack ONLY. Weight does NOT gate (PZ soft-cap):
## the player may carry over capacity and suffer a Heavy Load movement penalty.
## Returns the quantity actually added (0 if the stack is full).
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, _max_stack(item_id) - current)
	var want: int = min(qty, stack_room)
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
	lines.append("weight=%s/%s" % [str(snappedf(get_total_weight(), 0.1)), str(snappedf(get_capacity(), 0.1))])
	return lines
