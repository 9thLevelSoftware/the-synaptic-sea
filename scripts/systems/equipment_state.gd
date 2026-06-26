extends RefCounted
class_name EquipmentState

## The player's worn equipment, keyed by body-location slot (one item per slot).
## Pure model; never touches the scene tree. Worn containers raise carry capacity;
## a suit modifies the oxygen drain. Constructed via the load()-self-reference
## factory so it resolves under --headless --script (class_name globals unreliable
## there; mirrors ShipInstance.create). Round-trips via get_summary/apply_summary.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const SLOTS: Array = ["suit", "back", "waist", "primary_hand", "secondary_hand"]

var slots: Dictionary = {}          # slot_id: String -> item_id: String (absent = empty)
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
	return {"ok": true, "displaced": displaced}

## Removes and returns the item in `slot` ("" if empty).
func unequip(slot: String) -> String:
	var item_id: String = str(slots.get(slot, ""))
	if item_id != "":
		slots.erase(slot)
	return item_id

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
	return {"slots": slots.duplicate(true)}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	slots.clear()
	var slots_variant: Variant = (summary as Dictionary).get("slots", null)
	if typeof(slots_variant) == TYPE_DICTIONARY:
		for slot in (slots_variant as Dictionary):
			var item_id: String = str((slots_variant as Dictionary)[slot])
			if String(slot) in SLOTS and item_id != "":
				slots[String(slot)] = item_id
	return true
