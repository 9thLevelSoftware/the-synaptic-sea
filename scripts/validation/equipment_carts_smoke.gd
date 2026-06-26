extends SceneTree

## Equipment & carts main-scene smoke.
## Section A (Task 7): auto-equip raises capacity; overload drops move_speed via the
##   Heavy Load curve; equip/unequip move items between inventory and slots; player
##   equipment persists across an in-process save->load.
## Section B (Task 11): cart grab occupies both hands + push penalty; load/unload;
##   parked cart persists on its ship.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

var _b_loaded: int = 0
var _b_persisted: bool = false

func _init() -> void:
	await _run_section_a()
	await _run_section_b()
	print(_section_b_marker())
	quit()

func _run_section_a() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Auto-equip path via the manual seam (equips a backpack from inventory).
	var base_cap: float = ship.player_capacity_for_validation()
	assert(ship.equip_for_validation("eva_backpack") == true, "backpack equipped")
	assert(ship.player_equipped_for_validation("back") == "eva_backpack", "back slot holds backpack")
	assert(ship.player_capacity_for_validation() == base_cap + 40.0, "capacity rose by 40 (base=%s now=%s)" % [str(base_cap), str(ship.player_capacity_for_validation())])

	# Overload -> Heavy Load -> move_speed drops below the default. The EVA
	# backpack now applies a 30% worn-container weight reduction, so use two
	# heavy part stacks rather than scrap alone to stay over capacity.
	var default_speed: float = ship.player_move_speed_for_validation()
	ship.overload_player_for_validation("scrap_metal", 20)
	ship.overload_player_for_validation("plating", 10)
	var slowed_speed: float = ship.player_move_speed_for_validation()
	assert(slowed_speed < default_speed, "move_speed dropped under Heavy Load (%s -> %s)" % [str(default_speed), str(slowed_speed)])

	# Unequip returns the item to inventory and drops the capacity bonus.
	assert(ship.unequip_for_validation("back") == "eva_backpack", "unequip returns backpack")
	assert(ship.player_capacity_for_validation() == base_cap, "capacity back to base after unequip")

	# Re-equip, then persist equipment across save->load.
	ship.equip_for_validation("hardsuit")
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	assert(ship.player_equipped_for_validation("suit") == "hardsuit", "suit persisted across save/load")

	# --- Cargo-transfer encumbrance recompute (Finding #1/#2 regression guard) ---
	# Ensure a backpack is worn so effective capacity is ~90 (base + 40 bonus).
	if ship.player_equipped_for_validation("back") != "eva_backpack":
		ship.equip_for_validation("eva_backpack")
	# Overload the player: scrap_metal x20 = 100 weight vs ~90 cap -> Heavy Load.
	ship.overload_player_for_validation("scrap_metal", 20)
	var slow: float = ship.player_move_speed_for_validation()
	assert(slow < 6.0, "move_speed below default 6.0 when over-encumbered (got %s)" % str(slow))

	# Deposit all cargo to the home hold: player weight drops, move_speed should recompute up.
	var home_id: String = ship.home_ship_id_for_validation()
	ship.cargo_deposit_for_validation(home_id)
	var fast: float = ship.player_move_speed_for_validation()
	assert(fast > slow, "deposit recomputed encumbrance: speed rose after unloading (%s -> %s)" % [str(slow), str(fast)])

	# Withdraw the parts back: player weight rises again, move_speed should recompute down.
	ship.cargo_withdraw_for_validation(home_id, "part")
	var slow2: float = ship.player_move_speed_for_validation()
	assert(slow2 < fast, "withdraw recomputed encumbrance: speed fell after reloading (%s -> %s)" % [str(fast), str(slow2)])

	ship.queue_free()

func _run_section_b() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame
	var home_id: String = ship.home_ship_id_for_validation()
	var cart_id: String = ship.spawn_cart_for_validation(home_id)
	assert(cart_id != "", "cart spawned on the home ship")
	for _k in range(2):
		await process_frame

	# Grab: cart marked grabbed + push penalty lowers move_speed.
	var pre_speed: float = ship.player_move_speed_for_validation()
	assert(ship.cart_grab_for_validation(cart_id) == true, "cart grabbed in range")
	assert(ship.cart_is_grabbed_for_validation() == true, "cart marked grabbed")
	assert(ship.player_move_speed_for_validation() < pre_speed, "push penalty slowed the player")

	# Load salvage into the cart (it leaves the player inventory -> off personal
	# encumbrance), then unload it straight back out.
	ship.overload_player_for_validation("scrap_metal", 5)
	_b_loaded = ship.cart_load_for_validation(cart_id)
	assert(_b_loaded == 5, "loaded 5 into the cart (got %d)" % _b_loaded)
	assert(ship.cart_hold_quantity_for_validation(cart_id, "scrap_metal") == 5, "cart holds 5")
	var unloaded: int = ship.cart_unload_for_validation(cart_id, "part")
	assert(unloaded == 5, "unloaded all 5 back to the player (got %d)" % unloaded)
	assert(ship.cart_hold_quantity_for_validation(cart_id, "scrap_metal") == 0, "cart emptied after unload")
	# Clear the inventory before re-loading so the cart ends up with exactly 5 items
	# (post-unload inventory holds the 5 just returned; we flush them to the home hold).
	ship.cargo_deposit_for_validation(home_id)
	# Re-load so the parked cart is non-empty for the persistence check.
	ship.overload_player_for_validation("scrap_metal", 5)
	ship.cart_load_for_validation(cart_id)

	# Persist a parked cart across save->load.
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	var home2: String = ship.home_ship_id_for_validation()
	# After reload the cart_id is deterministic ("cart_<ship_id>") and the parked
	# cart's contents persist via WorldSnapshot.home_ship_carts.
	var persisted_qty: int = ship.cart_hold_quantity_for_validation("cart_%s" % home2, "scrap_metal")
	_b_persisted = persisted_qty == 5
	assert(_b_persisted, "parked home cart persisted across save/load (got %d)" % persisted_qty)
	ship.queue_free()

func _section_b_marker() -> String:
	return "EQUIPMENT CARTS SMOKE PASS section_a=true cap_bonus=40 slowed=true cart_loaded=%d persisted=%s" % [_b_loaded, str(_b_persisted)]
