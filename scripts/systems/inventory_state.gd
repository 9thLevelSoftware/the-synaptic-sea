extends RefCounted
class_name InventoryState

## Player-global inventory: quantitied, categorized (part/supply/tool), SOFT weight-capped
## (PZ-style: carrying over capacity is allowed and penalized via Heavy Load movement, NOT
## refused — see get_capacity/get_load_ratio/is_over_capacity; add_item gates on max_stack only).
## Pure model; never touches the scene tree. Tools are category 'tool' items, exposed
## through legacy shims (add_tool/has_tool/tool_ids/get_drain_multiplier) so OxygenState,
## ToolPickup, and the junction gate are untouched. Round-trips via get/apply_summary.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const MAX_WEIGHT: float = 50.0
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

var _lot_ledger                     # ItemLotLedger; sole quantity/metadata authority
## Read-only aggregate compatibility view. A fresh dictionary prevents external
## writes from creating a quantity state that disagrees with the lot ledger.
var items: Dictionary:
	get:
		return _lot_ledger.get_quantities() if _lot_ledger != null else {}
var bonus_capacity: float = 0.0     # added by worn containers (set by the coordinator)
var weight_reduction: float = 0.0   # saved kg from worn containers (set by the coordinator)
var _definitions: Dictionary = {}   # item_id -> def Dictionary (merged)
var _holder_namespace_bound: bool = false

func _init(holder_namespace: String = "") -> void:
	_load_definitions()
	_lot_ledger = ItemLotLedgerScript.new(_definitions, holder_namespace)
	_holder_namespace_bound = not holder_namespace.is_empty()

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
	var quantities: Dictionary = items
	for item_id in quantities:
		total += get_weight_each(item_id) * float(quantities[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return _lot_ledger.get_quantity(item_id)

## Adds up to qty, honoring max_stack ONLY. Weight does NOT gate (PZ soft-cap):
## the player may carry over capacity and suffer a Heavy Load movement penalty.
## Returns the quantity actually added (0 if the stack is full).
func add_item(item_id: String, qty: int) -> int:
	var added: int = _lot_ledger.add_standard(item_id, qty)
	if added > 0:
		_holder_namespace_bound = true
	return added

## Metadata-aware deposit for crafting, salvage, transfer, and persistence paths.
func add_lot(lot: Dictionary) -> int:
	var added: int = _lot_ledger.add_lot(lot)
	if added > 0:
		_holder_namespace_bound = true
	return added

## Atomic metadata-aware removal. Explicit IDs constrain selection; an empty list
## uses the legacy standard-quality-first ordering.
func take_lots(item_id: String, qty: int, preferred_ids: PackedStringArray = PackedStringArray()) -> Array:
	return _lot_ledger.take_lots(item_id, qty, preferred_ids)

func get_lot_summary() -> Dictionary:
	return _lot_ledger.get_summary()

func bind_holder_namespace(holder_namespace: String) -> bool:
	var bound: bool = _lot_ledger.bind_holder_namespace(holder_namespace)
	if bound:
		_holder_namespace_bound = true
	return bound

func get_holder_namespace() -> String:
	return _lot_ledger.get_holder_namespace()

## Returns true if at least `qty` of item_id can be added without exceeding max_stack.
## Weight is a soft-cap (never blocks); only the per-item stack ceiling gates here. Use to
## guard actions that consume inputs and then deposit an output (e.g. crafting), so the
## output is never silently dropped after the inputs are spent.
func can_accept(item_id: String, qty: int) -> bool:
	if item_id.is_empty() or qty <= 0:
		return true
	return (_max_stack(item_id) - get_quantity(item_id)) >= qty

func remove_item(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var removed: int = min(qty, current)
	if removed <= 0:
		return 0
	var taken: Array = _lot_ledger.take_lots(item_id, removed)
	return removed if not taken.is_empty() else 0

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
	_lot_ledger.clear()
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
		"item_lots_v1": _lot_ledger.get_summary(),
		"tool_ids": tool_ids.duplicate(),          # derived; kept for backward compat
		"active_effects": effects,
		"drain_multiplier": get_drain_multiplier(), # OxygenState consumes this
		"total_weight": get_total_weight(),
		"max_weight": get_max_weight(),
	}

## Accepts lot-aware, aggregate-only, and legacy tool-only shapes atomically.
## material_summary is optional until P10 wires the separately persisted material
## payload into the versioned snapshot migration.
func apply_summary(summary: Dictionary, material_summary: Dictionary = {}, legacy_holder_namespace: String = "") -> bool:
	if summary == null or summary.is_empty():
		return false
	var candidate = ItemLotLedgerScript.new(_definitions, _lot_ledger.get_holder_namespace()) \
		if _holder_namespace_bound else ItemLotLedgerScript.new(_definitions)
	if summary.has("item_lots_v1"):
		var lot_payload: Variant = summary.get("item_lots_v1")
		if not (lot_payload is Dictionary):
			return false
		if not candidate.apply_summary(lot_payload as Dictionary):
			return false
		var aggregate_variant: Variant = summary.get("items", null)
		if aggregate_variant is Dictionary:
			var normalized: Dictionary = _normalize_aggregate(aggregate_variant as Dictionary)
			if not bool(normalized.get("ok", false)) \
					or normalized.get("items", {}) != candidate.get_quantities():
				return false
	else:
		var legacy_items: Dictionary = {}
		var items_variant: Variant = summary.get("items", null)
		if items_variant is Dictionary:
			legacy_items = (items_variant as Dictionary).duplicate(true)
		else:
			var legacy_ids: Variant = summary.get("tool_ids", [])
			if legacy_ids is Array:
				for tool_id: Variant in legacy_ids as Array:
					var id: String = str(tool_id)
					if not id.is_empty():
						legacy_items[id] = 1
		var legacy_payload: Dictionary = {"items": legacy_items}
		if not material_summary.is_empty():
			legacy_payload.material_summary = material_summary
		elif summary.get("material_quality", null) is Dictionary:
			legacy_payload.material_quality = summary.get("material_quality")
		var source_namespace: String = legacy_holder_namespace
		if source_namespace.is_empty():
			source_namespace = _lot_ledger.get_holder_namespace()
		if not candidate.apply_summary(legacy_payload, source_namespace):
			return false
	_lot_ledger = candidate
	_holder_namespace_bound = true
	return true

static func _normalize_aggregate(raw: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for raw_item_id: Variant in raw:
		var item_id: String = str(raw_item_id)
		var value: Variant = raw[raw_item_id]
		var quantity: int = 0
		if typeof(value) == TYPE_INT:
			quantity = int(value)
		elif typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
				and float(value) == floorf(float(value)):
			quantity = int(value)
		else:
			return {"ok": false, "items": {}}
		if item_id.is_empty() or quantity <= 0:
			return {"ok": false, "items": {}}
		normalized[item_id] = quantity
	return {"ok": true, "items": normalized}

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
