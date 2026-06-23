extends SceneTree

## Coordinator smoke: a co-present ship airlock-docked to a bay-bearing carrier can be
## docked INTO a hangar slot and launched back out. The home ship has a bay (cargo
## fallback); the lifeboat starts airlock-docked to it.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# The home ship has a bay via the cargo fallback.
	var home_id: String = ship.home_ship_id_for_validation()
	assert(ship.ship_bay_slot_count_for_validation(home_id) >= 1, "home ship has >=1 bay slot")

	# The lifeboat is airlock-docked to home at boot: bay it into the home hangar.
	var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == false, "lifeboat not bayed yet")
	var slot: int = ship.bay_dock_for_validation(home_id)
	assert(slot >= 0, "lifeboat docked into a home bay slot")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "lifeboat now bayed in home")

	# Launch it back out: it is no longer bayed.
	var launched_slot: int = ship.bay_launch_for_validation(home_id)
	assert(launched_slot >= 0, "a slot was launched")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == false, "lifeboat launched out of the bay")

	print("BAY DOCK LAUNCH SMOKE PASS slot=%d launched=%d" % [slot, launched_slot])
	quit()
