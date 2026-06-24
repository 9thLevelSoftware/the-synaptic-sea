extends SceneTree

## CartState pure-model smoke: a mobile container whose contents are moved via the
## same CargoTransfer flow as a ship hold, and which round-trips through
## get_summary/apply_summary. Contents live in the cart's own hold — never in the
## player inventory — so they are off personal encumbrance by construction.

const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")

func _init() -> void:
	var cart = CartStateScript.create("cart_1", 200.0)
	assert(cart.cart_id == "cart_1", "cart id set")
	assert(cart.push_speed_multiplier == 0.7, "default push multiplier 0.7")
	assert(cart.get_hold().get_max_weight() == 200.0, "cart hold cap set")

	# Load from a player inventory via CargoTransfer (deposit into the cart hold).
	var player = InventoryStateScript.new()
	player.add_item("scrap_metal", 6)       # part
	var dep: Dictionary = CargoTransferScript.deposit_all(player, cart.get_hold())
	assert(int(dep.get("total_moved", 0)) == 6, "loaded 6 into the cart")
	assert(player.get_quantity("scrap_metal") == 0, "items left the player (off personal encumbrance)")
	assert(cart.get_hold().get_quantity("scrap_metal") == 6, "cart holds the salvage")

	# Unload back to the player.
	var wd: Dictionary = CargoTransferScript.withdraw_category(cart.get_hold(), player, "part")
	assert(int(wd.get("total_moved", 0)) == 6, "unloaded 6 back to the player")

	# Park metadata + round-trip.
	cart.parked_ship_id = "home"
	cart.parked_position = Vector3(2, 0, 3)
	cart.get_hold().add_item("scrap_metal", 4)
	cart.push_speed_multiplier = 0.55   # non-default so the round-trip assertion is falsifiable
	var summary: Dictionary = cart.get_summary()
	var clone = CartStateScript.create("x", 1.0)
	assert(clone.apply_summary(summary) == true, "apply_summary accepts")
	assert(clone.cart_id == "cart_1", "cart_id round-tripped")
	assert(clone.parked_ship_id == "home", "parked_ship_id round-tripped")
	assert(clone.parked_position == Vector3(2, 0, 3), "parked_position round-tripped")
	assert(clone.push_speed_multiplier == 0.55, "push_speed_multiplier round-tripped (clone defaults 0.7, so this fails if dropped)")
	assert(clone.get_hold().get_quantity("scrap_metal") == 4, "cart contents round-tripped")
	assert(CartStateScript.create("y").apply_summary({}) == false, "empty summary rejected")

	print("CART STATE SMOKE PASS loaded=6 contents=%d" % clone.get_hold().get_quantity("scrap_metal"))
	quit()
