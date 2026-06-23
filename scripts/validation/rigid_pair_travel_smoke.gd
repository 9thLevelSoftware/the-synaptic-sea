extends SceneTree

## Piloting a claimed derelict with the lifeboat docked to it: travelling moves the
## whole rigid pair. The lifeboat ends flush against the (moved) piloted ship and the
## piloted ship is never freed.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Make the lifeboat travel-capable and jump to a CLAIMABLE (bridge-bearing) derelict.
	# bridge is weighted (not guaranteed), so iterate in-range markers until one has a bridge.
	ship.force_repair_all_for_validation()
	# 5b precondition: the player must be aboard the piloted ship (the lifeboat) before
	# travelling — the ride physically takes them with it. Mirror physical_travel_smoke.
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in scanner range")
	var landed := false
	for mid in ids:
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		var res: Dictionary = ship.travel_to_marker_id(String(mid))
		if not res.get("success", false):
			continue
		for _i in range(2):
			await process_frame
		if ship.current_ship_has_bridge_for_validation():
			landed = true
			break
	assert(landed, "found and travelled to a claimable (bridge-bearing) derelict")

	# Claim the derelict and take command (its propulsion repaired so it is a working vessel).
	var derelict_id: String = ship.current_ship_id_for_validation()
	ship.make_ship_working_for_validation(derelict_id)
	assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claim derelict")
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "piloting the derelict")

	# The lifeboat is still docked to the derelict (the rigid pair).
	assert(ship.lifeboat_docked_to_piloted_for_validation() == true, "lifeboat docked to piloted ship")

	# Travel to another derelict piloting the derelict; the lifeboat must come along flush.
	var ids2: Array = ship.scannable_marker_ids_for_validation()
	var target := ""
	for m in ids2:
		if String(m) != derelict_id and not ship.is_marker_current_for_validation(String(m)):
			target = String(m)
			break
	assert(target != "", "a second distinct target is in range")
	# Aboard the piloted derelict before the rigid-pair travel (same 5b precondition).
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	var res2: Dictionary = ship.travel_to_marker_id(target)
	assert(res2.get("success", false), "rigid-pair travel succeeded")
	for _i in range(2):
		await process_frame

	# The piloted derelict still exists (never freed) and the lifeboat is flush to it.
	assert(ship.piloted_ship_id_for_validation() == derelict_id, "still piloting the same derelict")
	assert(ship.lifeboat_flush_to_piloted_for_validation() == true, "lifeboat flush to moved piloted ship")

	# Lifecycle regression: the lifeboat's bridge terminal must SURVIVE travel (dock-barrier
	# respawn must not wipe it). Logging in at the lifeboat terminal takes command back.
	var lb_id: String = String(ship.get_lifeboat_ship_for_validation().ship_id)
	assert(ship.login_at_terminal_for_validation(lb_id) == true, "lifeboat terminal survived travel")
	assert(ship.piloted_ship_id_for_validation() == lb_id, "took command of lifeboat after travel")

	print("RIGID PAIR TRAVEL SMOKE PASS piloted=%s" % ship.piloted_ship_id_for_validation())
	quit()
