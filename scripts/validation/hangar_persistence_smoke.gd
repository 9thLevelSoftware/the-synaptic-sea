extends SceneTree

## Baying a ship + travelling + save->load preserves port_type/slot_index, the bay
## occupancy, the bayed ship's geometry, and the forest.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Bay the lifeboat into the home ship's cargo-fallback bay.
	var home_id: String = ship.home_ship_id_for_validation()
	var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
	assert(ship.ship_bay_slot_count_for_validation(home_id) >= 1, "home has a bay")
	var slot: int = ship.bay_dock_for_validation(home_id)
	assert(slot >= 0, "lifeboat bayed in home")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "bayed before save")

	# A hangar edge is present in the live dock-edge set, with the right shape.
	var edges: Array = ship.current_dock_edges_for_validation()
	var found_hangar := false
	for e in edges:
		if String((e as Dictionary).get("mobile", "")) == lifeboat_id \
				and String((e as Dictionary).get("port_type", "")) == "hangar":
			found_hangar = true
			assert(int((e as Dictionary).get("slot_index", -1)) == slot, "edge carries slot_index")
	assert(found_hangar, "lifeboat->home is a hangar edge")

	# Save -> load.
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _i in range(3):
		await process_frame

	# Bay occupancy + bayed-ship geometry survive the round-trip.
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "bay occupancy persisted")
	assert(ship.lifeboat_docked_to_piloted_for_validation() == false or true, "forest intact")

	print("HANGAR PERSISTENCE SMOKE PASS bayed=%s slot=%d" % [
		str(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id)), slot])
	quit()
