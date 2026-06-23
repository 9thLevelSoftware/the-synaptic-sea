extends SceneTree

## Claiming a derelict and piloting it (lifeboat docked to it) round-trips through
## save -> load: owner, piloted pointer, and the lifeboat->derelict dock edge survive.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	ship.force_repair_all_for_validation()
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in range")
	# Land on a CLAIMABLE (bridge-bearing) derelict (bridge is weighted, not guaranteed).
	var landed := false
	for mid in ids:
		# 5b precondition: the player must be aboard the piloted ship before travelling.
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		if not ship.travel_to_marker_id(String(mid)).get("success", false):
			continue
		for _i in range(2):
			await process_frame
		if ship.current_ship_has_bridge_for_validation():
			landed = true
			break
	assert(landed, "travelled to a claimable derelict")

	var derelict_id: String = ship.current_ship_id_for_validation()
	ship.make_ship_working_for_validation(derelict_id)
	assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claimed derelict")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloting derelict")

	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _i in range(3):
		await process_frame

	# Owner, piloted pointer, and the lifeboat->derelict edge survive the round-trip.
	assert(ship.ship_owner_for_validation(derelict_id) == "player_local", "derelict ownership persisted")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloted pointer persisted")
	assert(ship.lifeboat_docked_to_piloted_for_validation() == true, "lifeboat->derelict edge persisted")

	print("CLAIM PERSISTENCE SMOKE PASS piloted=%s owner=%s" % [ship.piloted_ship_id_for_validation(), ship.ship_owner_for_validation(derelict_id)])
	quit()
