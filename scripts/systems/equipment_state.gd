extends RefCounted
class_name EquipmentState

## The player's worn equipment, keyed by body-location slot (one item per slot).
## Pure model; never touches the scene tree. Worn containers raise carry capacity;
## a suit modifies the oxygen drain. Constructed via the load()-self-reference
## factory so it resolves under --headless --script (class_name globals unreliable
## there; mirrors ShipInstance.create). Round-trips via get_summary/apply_summary.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const SLOTS: Array = ["suit", "back", "waist", "primary_hand", "secondary_hand"]

var slots: Dictionary = {}          # slot_id: String -> item_id: String (absent = empty)
var slot_lots: Dictionary = {}     # slot_id: String -> exact equipped lot
var _defs: Dictionary = {}

func _init() -> void:
	_defs = ItemDefsScript.load_definitions()

static func create() -> EquipmentState:
	var script: GDScript = load("res://scripts/systems/equipment_state.gd")
	return script.new()

## True iff the item declares a slot in SLOTS.
func can_equip(item_id: String) -> bool:
	var slot: String = ItemDefsScript.equip_slot(_defs, item_id)
	return slot in SLOTS

## Equips item_id into its declared slot, displacing whatever was there.
## Returns { "ok": bool, "displaced": String } (displaced "" if the slot was empty
## or on failure).
func equip(item_id: String) -> Dictionary:
	if not can_equip(item_id):
		return {"ok": false, "displaced": ""}
	var slot: String = ItemDefsScript.equip_slot(_defs, item_id)
	var displaced: String = str(slots.get(slot, ""))
	slots[slot] = item_id
	slot_lots[slot] = _legacy_lot(slot, item_id)
	return {"ok": true, "displaced": displaced}

func equip_lot(lot: Dictionary) -> Dictionary:
	var item_id: String = str(lot.get("item_id", ""))
	if not can_equip(item_id):
		return {"ok": false, "displaced": "", "displaced_lot": {}}
	var slot: String = ItemDefsScript.equip_slot(_defs, item_id)
	var displaced: String = str(slots.get(slot, ""))
	var displaced_lot: Dictionary = (slot_lots.get(slot, {}) as Dictionary).duplicate(true)
	slots[slot] = item_id
	slot_lots[slot] = lot.duplicate(true)
	return {"ok": true, "displaced": displaced, "displaced_lot": displaced_lot}

## Removes and returns the item in `slot` ("" if empty).
func unequip(slot: String) -> String:
	var item_id: String = str(slots.get(slot, ""))
	if item_id != "":
		slots.erase(slot)
		slot_lots.erase(slot)
	return item_id

func unequip_lot(slot: String) -> Dictionary:
	var item_id: String = str(slots.get(slot, ""))
	if item_id.is_empty():
		return {}
	var lot: Dictionary = (slot_lots.get(slot, {}) as Dictionary).duplicate(true)
	slots.erase(slot)
	slot_lots.erase(slot)
	return lot

func get_equipped(slot: String) -> String:
	return str(slots.get(slot, ""))

func is_slot_occupied(slot: String) -> bool:
	return slots.has(slot) and str(slots[slot]) != ""

## Sum of container_capacity across all worn containers.
func get_carry_capacity_bonus() -> float:
	var bonus: float = 0.0
	for slot in slots:
		bonus += ItemDefsScript.container_capacity(_defs, str(slots[slot]))
	return bonus

## [{capacity, reduction}] for each worn item that is a container (capacity > 0).
## The suit (no container_capacity) is excluded. Pure data; feeds
## Encumbrance.weight_reduction_saved at the coordinator.
func get_container_reductions() -> Array:
	var out: Array = []
	for slot in slots:
		var cap: float = ItemDefsScript.container_capacity(_defs, str(slots[slot]))
		if cap > 0.0:
			out.append({
				"capacity": cap,
				"reduction": ItemDefsScript.weight_reduction(_defs, str(slots[slot])),
			})
	return out

## Product of all worn 'oxygen_drain' effect values (default 1.0 = neutral).
func get_oxygen_drain_multiplier() -> float:
	var mult: float = 1.0
	for slot in slots:
		for fx in ItemDefsScript.effects(_defs, str(slots[slot])):
			if fx is Dictionary and str(fx.get("type", "")) == "oxygen_drain":
				mult *= float(fx.get("value", 1.0))
	return mult

func get_summary() -> Dictionary:
	return {"slots": slots.duplicate(true), "slot_lots_v1": slot_lots.duplicate(true)}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	var d: Dictionary = summary as Dictionary
	var slots_variant: Variant = d.get("slots", null)
	if not (slots_variant is Dictionary):
		return false
	var restored_slots: Dictionary = {}
	for raw_slot in slots_variant as Dictionary:
		var slot: String = str(raw_slot)
		var raw_item: Variant = (slots_variant as Dictionary)[raw_slot]
		if not (raw_item is String):
			return false
		var item_id: String = raw_item as String
		if not (slot in SLOTS) or item_id.is_empty() or ItemDefsScript.equip_slot(_defs, item_id) != slot:
			return false
		restored_slots[slot] = item_id
	var restored_lots: Dictionary = {}
	if d.has("slot_lots_v1"):
		var lot_variant: Variant = d["slot_lots_v1"]
		if not (lot_variant is Dictionary) or (lot_variant as Dictionary).size() != restored_slots.size():
			return false
		var seen_lot_ids: Dictionary = {}
		for raw_slot in lot_variant as Dictionary:
			var slot: String = str(raw_slot)
			var raw_lot: Variant = (lot_variant as Dictionary)[raw_slot]
			if not restored_slots.has(slot) or not (raw_lot is Dictionary):
				return false
			var lot: Dictionary = _validated_equipped_lot(raw_lot as Dictionary, slot, str(restored_slots[slot]))
			var lot_id: String = str(lot.get("lot_id", ""))
			if lot.is_empty() or seen_lot_ids.has(lot_id):
				return false
			seen_lot_ids[lot_id] = true
			restored_lots[slot] = lot
	else:
		# Legacy scalar slots had no lot metadata. Migrate them deterministically.
		for slot in restored_slots:
			var item_id: String = str(restored_slots[slot])
			restored_lots[slot] = _legacy_lot(slot, item_id)
	slots = restored_slots
	slot_lots = restored_lots
	return true

func _validated_equipped_lot(raw: Dictionary, slot: String, item_id: String) -> Dictionary:
	var lot_id: String = str(raw.get("lot_id", ""))
	var raw_quantity: Variant = raw.get("quantity", null)
	var raw_score: Variant = raw.get("quality_score", null)
	var raw_condition: Variant = raw.get("condition", null)
	var tier: String = str(raw.get("quality_tier", ""))
	var origin: Variant = raw.get("origin", null)
	if lot_id.is_empty() or str(raw.get("item_id", "")) != item_id \
			or not _is_exact_one(raw_quantity) \
			or not _is_unit_number(raw_score) \
			or not _is_unit_number(raw_condition) \
			or not (origin is Dictionary) \
			or not QualityTierResolverScript.TIER_ORDER.has(tier) \
			or QualityTierResolverScript.tier_for_score(float(raw_score)) != tier:
		return {}
	return {
		"lot_id": lot_id,
		"item_id": item_id,
		"quantity": 1,
		"quality_score": float(raw_score),
		"quality_tier": tier,
		"condition": float(raw_condition),
		"origin": (origin as Dictionary).duplicate(true),
	}

static func _legacy_lot(slot: String, item_id: String) -> Dictionary:
	return {
		"lot_id": "equipment:legacy:%s:%s" % [slot, item_id],
		"item_id": item_id,
		"quantity": 1,
		"quality_score": 0.5,
		"quality_tier": "standard",
		"condition": 1.0,
		"origin": {"source": "legacy_equipment", "slot_id": slot},
	}

static func _is_exact_one(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) == 1 \
			or typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == 1.0

static func _is_unit_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
			and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0
