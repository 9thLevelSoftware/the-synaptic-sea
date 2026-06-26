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
	inst._hold = load("res://scripts/systems/ship_inventory.gd").create(p_max_weight)
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
	cart_id = str(d.get("cart_id", cart_id))
	parked_ship_id = str(d.get("parked_ship_id", parked_ship_id))
	var p: Variant = d.get("parked_position", null)
	if p is Array and (p as Array).size() == 3:
		parked_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if d.has("push_speed_multiplier"):
		push_speed_multiplier = float(d["push_speed_multiplier"])
	var hold_summary: Variant = d.get("hold", null)
	if typeof(hold_summary) == TYPE_DICTIONARY:
		_hold.apply_summary(hold_summary as Dictionary)
	return true
