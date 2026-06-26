extends RefCounted
class_name ShipInventory

## Per-ship cargo hold. A focused, weight-capped item container — no player-tool
## shims. Shares item weights/stack-limits with the player InventoryState via
## ItemDefs. Pure model; never touches the scene tree. Round-trips via
## get_summary/apply_summary. Constructed through the load()-self-reference factory
## so it resolves under --headless --script (class_name globals are unreliable
## there; mirrors ShipInstance.create).

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const MAX_WEIGHT_DEFAULT: float = 500.0

var items: Dictionary = {}          # item_id: String -> quantity: int
var max_weight: float = MAX_WEIGHT_DEFAULT
var _defs: Dictionary = {}

func _init() -> void:
	_defs = ItemDefsScript.load_definitions()

static func create(p_max_weight: float = MAX_WEIGHT_DEFAULT) -> ShipInventory:
	var script: GDScript = load("res://scripts/systems/ship_inventory.gd")
	var inst = script.new()
	inst.max_weight = p_max_weight
	return inst

func get_max_weight() -> float:
	return max_weight

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items:
		total += ItemDefsScript.weight_each(_defs, item_id) * float(items[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Adds up to qty, honoring max_stack and the weight cap. Returns the quantity
## actually added (0 if none fit). Weight-0 items ignore the cap. Mirrors
## InventoryState.add_item semantics exactly.
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, ItemDefsScript.max_stack(_defs, item_id) - current)
	var want: int = min(qty, stack_room)
	if want <= 0:
		return 0
	var w: float = ItemDefsScript.weight_each(_defs, item_id)
	if w > 0.0:
		var remaining: float = max_weight - get_total_weight()
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
		if ItemDefsScript.category(_defs, item_id) == category:
			out.append({
				"id": item_id,
				"quantity": get_quantity(item_id),
				"weight_each": ItemDefsScript.weight_each(_defs, item_id),
			})
	return out

func reset() -> void:
	items.clear()

func get_summary() -> Dictionary:
	return {
		"items": items.duplicate(true),
		"max_weight": max_weight,
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	items.clear()
	var items_variant: Variant = (summary as Dictionary).get("items", null)
	if typeof(items_variant) == TYPE_DICTIONARY:
		for item_id in (items_variant as Dictionary):
			items[String(item_id)] = int((items_variant as Dictionary)[item_id])
	if (summary as Dictionary).has("max_weight"):
		max_weight = float((summary as Dictionary)["max_weight"])
	return true
