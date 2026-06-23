extends SceneTree

## CartControl strict in-range gate: off-tree / out-of-range refuses (no emit);
## in-range grab/load/unload emit their intents. Mirrors CargoHoldControl's gate.

const CartControlScript := preload("res://scripts/tools/cart_control.gd")

var _grab_emits: int = 0
var _load_emits: int = 0
var _unload_cat: String = ""

func _init() -> void:
	await _run()
	print("CART CONTROL SMOKE PASS grabs=%d loads=%d" % [_grab_emits, _load_emits])
	quit()

func _run() -> void:
	var control = CartControlScript.new()
	control.cart_grab_requested.connect(func(_cid): _grab_emits += 1)
	control.cart_load_requested.connect(func(_cid): _load_emits += 1)
	control.cart_unload_requested.connect(func(_cid, cat): _unload_cat = cat)

	assert(control.try_grab(null) == false, "off-tree grab refused")
	assert(_grab_emits == 0, "no emit while refused")

	root.add_child(control)
	control.configure("cart_1", Vector3.ZERO, 1.8)
	await process_frame
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3(0.5, 0.0, 0.0)
	await process_frame
	assert(control.try_grab(player) == true, "in-range grab emits")
	assert(_grab_emits == 1, "grab emitted once")
	assert(control.try_load(player) == true, "in-range load emits")
	assert(_load_emits == 1, "load emitted once")
	assert(control.try_unload(player, "part") == true, "in-range unload emits")
	assert(_unload_cat == "part", "unload carried the category")

	player.global_position = Vector3(100.0, 0.0, 0.0)
	await process_frame
	assert(control.try_grab(player) == false, "out-of-range grab refused")
	assert(_grab_emits == 1, "no extra emit out of range")
