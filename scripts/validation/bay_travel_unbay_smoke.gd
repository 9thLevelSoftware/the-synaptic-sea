extends SceneTree

## Codex PR#16 P2 regression: baying the piloted lifeboat in the home cargo bay and then
## TRAVELLING must clear the home bay slot (the travel undock path unbays it). Without the
## fix the slot is left stale — the lifeboat undocks but home.hangar still reports it bayed,
## the slot stays unusable, and a later airlock re-dock is misclassified as a hangar edge.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var home_id: String = ship.home_ship_id_for_validation()
	var lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
	assert(ship.ship_bay_slot_count_for_validation(home_id) >= 1, "home has a bay")

	# Bay the piloted lifeboat in the home cargo bay (the candidate airlock-docked to home).
	var slot: int = ship.bay_dock_for_validation(home_id)
	assert(slot >= 0, "lifeboat bayed in home bay")
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == true, "lifeboat bayed before travel")

	# Travel away while piloting the (now-bayed) lifeboat. The undock path must unbay it.
	ship.force_repair_all_for_validation()
	ship.make_ship_working_for_validation(lifeboat_id)
	ship.set_manual_power_route_for_validation("propulsion", 30.0)
	var ids: Array = ship.scannable_marker_ids_for_validation()
	assert(ids.size() > 0, "a derelict is in scanner range")
	var travelled := false
	for mid in ids:
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		if ship.travel_to_marker_id(String(mid)).get("success", false):
			travelled = true
			for _i in range(2):
				await process_frame
			break
	assert(travelled, "travelled away while piloting the formerly-bayed lifeboat")

	# The home bay slot must be cleared — no stale occupant left behind.
	assert(ship.ship_is_bayed_in_for_validation(lifeboat_id, home_id) == false, "home bay slot cleared on travel undock (no stale slot)")

	print("BAY TRAVEL UNBAY SMOKE PASS slot=%d cleared=true" % slot)
	quit()
