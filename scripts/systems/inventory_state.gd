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
var generated_item_records: Dictionary = {} # item_id -> validated Rust blueprint/bindings

const GENERATED_ITEM_FAMILIES: Dictionary = {
	"armor": {
		"socket_id":"socket_armor", "visual_tag":"item_armor", "stat":"armor",
		"asset_id":"asset:primitive:item_armor", "binding_id":"binding:item:armor",
		"weight":8.0,
	},
	"tool": {
		"socket_id":"socket_tool", "visual_tag":"item_tool", "stat":"capacity",
		"asset_id":"asset:primitive:item_tool", "binding_id":"binding:item:tool",
		"weight":2.0,
	},
	"weapon": {
		"socket_id":"socket_weapon", "visual_tag":"item_weapon", "stat":"damage",
		"asset_id":"asset:primitive:item_weapon", "binding_id":"binding:item:weapon",
		"weight":3.0,
	},
}

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	_definitions = ItemDefsScript.load_definitions()
	for item_id in generated_item_records:
		var record: Variant = generated_item_records[item_id]
		if record is Dictionary:
			_definitions[item_id] = _generated_runtime_definition(record as Dictionary)


## Registers one fully validated Rust item blueprint plus its approved presentation
## assembly. Derived runtime fields are rebuilt locally; generated text never controls
## stats, category, weight, or stack limits.
func register_generated_item(exact_item: Dictionary) -> bool:
	var normalized: Dictionary = _normalize_generated_item(exact_item)
	if normalized.is_empty():
		return false
	var item_id: String = str(normalized.get("item_id", ""))
	if _definitions.has(item_id) and not generated_item_records.has(item_id):
		return false
	if generated_item_records.has(item_id):
		return JSON.stringify(generated_item_records[item_id]) == JSON.stringify(normalized)
	generated_item_records[item_id] = normalized
	_definitions[item_id] = _generated_runtime_definition(normalized)
	return true


func get_generated_item_record(item_id: String) -> Dictionary:
	var record: Variant = generated_item_records.get(item_id, {})
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


func _normalize_generated_item(exact_item: Dictionary) -> Dictionary:
	var item_id: String = str(exact_item.get("item_id", ""))
	var quantity: Variant = exact_item.get("quantity", null)
	var blueprint_value: Variant = exact_item.get("blueprint", null)
	var assets_value: Variant = exact_item.get("asset_ids", null)
	var bindings_value: Variant = exact_item.get("presentation_binding_ids", null)
	if not _valid_generated_id(item_id) or typeof(quantity) != TYPE_INT or int(quantity) != 1 \
			or not blueprint_value is Dictionary or not assets_value is Array or not bindings_value is Array \
			or (assets_value as Array).size() != 1 or (bindings_value as Array).size() != 1:
		return {}
	var blueprint: Dictionary = blueprint_value
	var expected_keys: Array[String] = [
		"id", "family_id", "rarity_id", "socket_id", "affixes", "stat_budget",
		"economy_value", "visual_tag",
	]
	if not _has_exact_generated_keys(blueprint, expected_keys) or str(blueprint.get("id", "")) != item_id:
		return {}
	var family_id: String = str(blueprint.get("family_id", ""))
	if not GENERATED_ITEM_FAMILIES.has(family_id):
		return {}
	var family: Dictionary = GENERATED_ITEM_FAMILIES[family_id]
	if str(blueprint.get("rarity_id", "")) != "common" \
			or str(blueprint.get("socket_id", "")) != str(family.socket_id) \
			or str(blueprint.get("visual_tag", "")) != str(family.visual_tag) \
			or typeof(blueprint.get("stat_budget", null)) != TYPE_INT \
			or int(blueprint.get("stat_budget", -1)) < 0 or int(blueprint.get("stat_budget", -1)) > 200 \
			or typeof(blueprint.get("economy_value", null)) != TYPE_INT \
			or int(blueprint.get("economy_value", -1)) < 0 or int(blueprint.get("economy_value", -1)) > 1000 \
			or str((assets_value as Array)[0]) != str(family.asset_id) \
			or str((bindings_value as Array)[0]) != str(family.binding_id):
		return {}
	var affixes_value: Variant = blueprint.get("affixes", null)
	if not affixes_value is Array or (affixes_value as Array).size() > 1:
		return {}
	for affix_value in affixes_value:
		if not affix_value is Dictionary:
			return {}
		var affix: Dictionary = affix_value
		if not _has_exact_generated_keys(affix, ["affix_id", "stat", "value"]) \
				or not _valid_generated_id(str(affix.get("affix_id", ""))) \
				or str(affix.get("stat", "")) != str(family.stat) \
				or typeof(affix.get("value", null)) != TYPE_INT \
				or int(affix.get("value", 0)) < 10 or int(affix.get("value", 0)) > 50:
			return {}
	if exact_item.has("frequency_bp"):
		var frequency: Variant = exact_item.get("frequency_bp")
		if typeof(frequency) != TYPE_INT or int(frequency) < 0 or int(frequency) > 10000:
			return {}
	return {
		"item_id":item_id,
		"blueprint":blueprint.duplicate(true),
		"asset_ids":(assets_value as Array).duplicate(true),
		"presentation_binding_ids":(bindings_value as Array).duplicate(true),
	}


func _generated_runtime_definition(record: Dictionary) -> Dictionary:
	var blueprint: Dictionary = record.get("blueprint", {})
	var family_id: String = str(blueprint.get("family_id", ""))
	var family: Dictionary = GENERATED_ITEM_FAMILIES.get(family_id, {})
	return {
		"display_name":"Common %s" % family_id.capitalize(),
		"category":"generated_item",
		"weight":float(family.get("weight", 0.0)),
		"max_stack":1,
		"rarity":"common",
		"procgen_blueprint":blueprint.duplicate(true),
		"procgen_asset_ids":(record.get("asset_ids", []) as Array).duplicate(true),
		"procgen_presentation_binding_ids":(record.get("presentation_binding_ids", []) as Array).duplicate(true),
	}


func _valid_generated_id(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		var valid: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) \
				or value.substr(index, 1) in ["_", ":", ".", "-"]
		if not valid:
			return false
	return true


func _has_exact_generated_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

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
	generated_item_records.clear()
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
	var summary: Dictionary = {
		"items": items.duplicate(true),
		"tool_ids": tool_ids.duplicate(),          # derived; kept for backward compat
		"active_effects": effects,
		"drain_multiplier": get_drain_multiplier(), # OxygenState consumes this
		"total_weight": get_total_weight(),
		"max_weight": get_max_weight(),
	}
	if not generated_item_records.is_empty():
		summary["generated_item_definitions"] = generated_item_records.duplicate(true)
	return summary

## Accepts the new ("items") shape AND the legacy ("tool_ids"-only) shape.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	items.clear()
	generated_item_records.clear()
	_load_definitions()
	var generated_value: Variant = summary.get("generated_item_definitions", null)
	if generated_value is Dictionary:
		var generated_ids: Array = (generated_value as Dictionary).keys()
		generated_ids.sort()
		for item_id_value in generated_ids:
			var item_id: String = str(item_id_value)
			var record_value: Variant = (generated_value as Dictionary)[item_id_value]
			if not record_value is Dictionary:
				return false
			var saved_record: Dictionary = record_value
			var restored_exact: Dictionary = saved_record.duplicate(true)
			restored_exact["quantity"] = 1
			if str(restored_exact.get("item_id", "")) != item_id or not register_generated_item(restored_exact):
				return false
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
