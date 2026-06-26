extends SceneTree

## Claiming a derelict and piloting it (lifeboat docked to it) round-trips through
## save -> load: owner, piloted pointer, and the lifeboat->derelict dock edge survive.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var lifeboat_id: String = String(ship.get_lifeboat_ship_for_validation().ship_id)
	ship.make_ship_working_for_validation(lifeboat_id)
	ship.set_manual_power_route_for_validation("propulsion", 30.0)
	var ids: Array = ship.claimable_marker_ids_for_validation()
	assert(ids.size() > 0, "a claimable derelict is in range")
	# Land on a CLAIMABLE (bridge-bearing) derelict. Nearby bridge rooms are weighted,
	# so filter the in-range markers through the playable's claimable-marker seam.
	var landed := false
	for mid in ids:
		# 5b precondition: the player must be aboard the piloted ship before travelling.
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		if not ship.travel_to_marker_id(String(mid)).get("success", false):
			continue
		for _i in range(2):
			await process_frame
		if ship.current_ship_has_bridge_for_validation() and ship.current_ship_id_for_validation() != "":
			landed = true
			break
	assert(landed, "travelled to a claimable derelict")

	var derelict_id: String = ship.current_ship_id_for_validation()
	ship.make_ship_working_for_validation(derelict_id)
	assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claimed derelict")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloting derelict")

	# Rigid-pair travel the claimed derelict to a SECOND host so that current_location
	# (the new host) != piloted (the claimed derelict). This is the scenario the
	# persistence fix targets: the piloted derelict becomes a mobile dock endpoint that is
	# NOT current_location and must still reload WITH geometry (Codex P2). Without the fix
	# it reloads scene_root == null and piloted_ship points at a geometry-less ship.
	var ids2: Array = ship.scannable_marker_ids_for_validation()
	var second := false
	for mid2 in ids2:
		if ship.is_marker_current_for_validation(String(mid2)):
			continue
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		if ship.travel_to_marker_id(String(mid2)).get("success", false):
			second = true
			for _i in range(2):
				await process_frame
			break
	assert(second, "rigid-pair travelled the claimed derelict to a second host")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "still piloting the claimed derelict")

	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _i in range(3):
		await process_frame

	# Owner, piloted pointer, the piloted ship's GEOMETRY, and the lifeboat->derelict edge
	# all survive the round-trip — even though the piloted derelict was not current_location.
	assert(ship.ship_owner_for_validation(derelict_id) == "player_local", "derelict ownership persisted")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloted pointer persisted")
	assert(ship.piloted_ship_has_geometry_for_validation() == true, "piloted derelict reloaded with geometry")
	assert(ship.lifeboat_docked_to_piloted_for_validation() == true, "lifeboat->derelict edge persisted")

	print("CLAIM PERSISTENCE SMOKE PASS piloted=%s owner=%s" % [ship.piloted_ship_id_for_validation(), ship.ship_owner_for_validation(derelict_id)])
	quit()
