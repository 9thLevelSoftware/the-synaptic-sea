extends SceneTree

## Coordinator smoke: logging in at a working vessel's bridge terminal claims it
## and makes it piloted; logging in at a non-working vessel is refused.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)              # _ready() boots the home + lifeboat complex
	# Pump a couple of idle frames so deferred builds settle.
	for _i in range(3):
		await process_frame

	var lifeboat = ship.get_lifeboat_ship_for_validation()
	assert(lifeboat != null, "lifeboat exists at boot")
	assert(lifeboat.get_access().owner_id == "player_local", "lifeboat owned at boot")
	assert(ship.piloted_ship_id_for_validation() == String(lifeboat.ship_id), "lifeboat piloted at boot")

	# A non-working vessel refuses login (propulsion offline -> not a working vessel).
	# Use a fresh derelict-like ShipInstance registered for the test.
	var offline_id: String = ship.register_offline_test_ship_for_validation()
	assert(ship.login_at_terminal_for_validation(offline_id) == false, "offline vessel login refused")
	assert(ship.piloted_ship_id_for_validation() == String(lifeboat.ship_id), "piloted unchanged after refused login")

	# Make it working, then login claims + pilots it.
	ship.make_ship_working_for_validation(offline_id)
	assert(ship.login_at_terminal_for_validation(offline_id) == true, "working vessel login succeeds")
	assert(ship.piloted_ship_id_for_validation() == offline_id, "piloted flips to the claimed ship")

	print("BRIDGE TERMINAL LOGIN SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
