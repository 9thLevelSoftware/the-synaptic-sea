extends RefCounted
class_name CartState

## A pushable cart: a mobile container wrapping a ShipInventory. Its contents are
## never added to the player's personal encumbrance (they live in the cart hold);
## a cart "removes" weight from the player whereas a worn bag only raises the cap.
## Pure model; never touches the scene tree. Constructed via the load()-self-ref
## factory (class_name globals unreliable headless). Round-trips via get/apply_summary.

const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

const MAX_WEIGHT_DEFAULT: float = 200.0
const PUSH_SPEED_MULTIPLIER_DEFAULT: float = 0.7

var cart_id: String = ""
var parked_ship_id: String = ""
var parked_position: Vector3 = Vector3.ZERO
var push_speed_multiplier: float = PUSH_SPEED_MULTIPLIER_DEFAULT
var _hold                                   # ShipInventory

func _init() -> void:
	_hold = ShipInventoryScript.create(MAX_WEIGHT_DEFAULT)

static func create(p_cart_id: String = "", p_max_weight: float = MAX_WEIGHT_DEFAULT) -> CartState:
	var script: GDScript = load("res://scripts/systems/cart_state.gd")
	var inst = script.new()
	inst.cart_id = p_cart_id
	inst._hold = load("res://scripts/systems/ship_inventory.gd").create(p_max_weight, "cart:%s" % p_cart_id)
	return inst

func get_hold():
	return _hold

func get_summary() -> Dictionary:
	return {
		"cart_id": cart_id,
		"parked_ship_id": parked_ship_id,
		"parked_position": [parked_position.x, parked_position.y, parked_position.z],
		"push_speed_multiplier": push_speed_multiplier,
		"hold": _hold.get_summary(),
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	var d: Dictionary = summary
	var restored_cart_id: String = str(d.get("cart_id", cart_id))
	if restored_cart_id.is_empty() or (not cart_id.is_empty() and restored_cart_id != cart_id):
		return false
	var restored_ship_id: String = str(d.get("parked_ship_id", parked_ship_id))
	var restored_position: Vector3 = parked_position
	var p: Variant = d.get("parked_position", null)
	if p != null:
		if not (p is Array) or (p as Array).size() != 3:
			return false
		for component in p as Array:
			if not _is_finite_number(component):
				return false
		restored_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var restored_speed: float = push_speed_multiplier
	if d.has("push_speed_multiplier"):
		if not _is_finite_number(d["push_speed_multiplier"]):
			return false
		restored_speed = float(d["push_speed_multiplier"])
		if restored_speed <= 0.0:
			return false
	var candidate_hold = ShipInventoryScript.create(MAX_WEIGHT_DEFAULT, "cart:%s" % restored_cart_id)
	var hold_summary: Variant = d.get("hold", null)
	if hold_summary != null:
		if not (hold_summary is Dictionary) or (hold_summary as Dictionary).is_empty():
			return false
		if not candidate_hold.apply_summary(hold_summary as Dictionary):
			return false
	cart_id = restored_cart_id
	parked_ship_id = restored_ship_id
	parked_position = restored_position
	push_speed_multiplier = restored_speed
	_hold = candidate_hold
	return true

static func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))
