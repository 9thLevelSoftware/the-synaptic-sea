extends SceneTree

## Switching the piloted ship by logging in at different bridges, and the no_access guard.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var lifeboat = ship.get_lifeboat_ship_for_validation()
	var lb_id: String = String(lifeboat.ship_id)
	assert(ship.piloted_ship_id_for_validation() == lb_id, "lifeboat piloted at boot")

	# Claim + pilot a second working vessel.
	var other_id: String = ship.register_offline_test_ship_for_validation()
	ship.make_ship_working_for_validation(other_id)
	assert(ship.login_at_terminal_for_validation(other_id) == true, "claim other ship")
	assert(ship.piloted_ship_id_for_validation() == other_id, "piloted is the other ship")

	# Switch back by logging in at the lifeboat terminal (lifeboat needs to be operational
	# for the login gate to admit it — same requirement as any pilotable vessel).
	ship.make_ship_working_for_validation(lb_id)
	assert(ship.login_at_terminal_for_validation(lb_id) == true, "switch back to lifeboat")
	assert(ship.piloted_ship_id_for_validation() == lb_id, "piloted back to lifeboat")

	# set_piloted_ship to a ship the player has no access to is refused.
	var no_access_id: String = ship.register_offline_test_ship_for_validation()
	var res: Dictionary = ship.set_piloted_ship_by_id_for_validation(no_access_id)
	assert(res.get("success", true) == false and res.get("reason", "") == "no_access", "no_access guard")
	assert(ship.piloted_ship_id_for_validation() == lb_id, "piloted unchanged after no_access")

	print("PILOT SWITCH SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
