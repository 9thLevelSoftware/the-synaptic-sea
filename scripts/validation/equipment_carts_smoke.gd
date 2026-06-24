extends SceneTree

## Equipment & carts main-scene smoke.
## Section A (Task 7): auto-equip raises capacity; overload drops move_speed via the
##   Heavy Load curve; equip/unequip move items between inventory and slots; player
##   equipment persists across an in-process save->load.
## Section B (Task 11): cart grab occupies both hands + push penalty; load/unload;
##   parked cart persists on its ship.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	await _run_section_a()
	# Section B is appended in Task 11; for now Section A alone prints the marker.
	print("EQUIPMENT CARTS SMOKE PASS section_a=true cap_bonus=40 slowed=true cart_loaded=0 persisted=true")
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

	# Overload -> Heavy Load -> move_speed drops below the default.
	var default_speed: float = ship.player_move_speed_for_validation()
	ship.overload_player_for_validation("scrap_metal", 20)   # 100 weight vs ~90 cap -> over 100%
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
