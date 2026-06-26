extends SceneTree

## A depth->=2 nested group rides rigidly on travel: a ship bayed inside a carrier
## that is itself airlock-docked to the piloted ship. After travel, the deepest
## descendant still tracks the piloted root (its world offset to the piloted root
## is preserved within tolerance).

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _init() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	ship.force_repair_all_for_validation()
	var lifeboat_id: String = String(ship.get_lifeboat_ship_for_validation().ship_id)
	ship.make_ship_working_for_validation(lifeboat_id)
	ship.set_manual_power_route_for_validation("propulsion", 30.0)
	var ids: Array = ship.claimable_marker_ids_for_validation()
	assert(ids.size() > 0, "a claimable derelict is in range")

	# Travel the piloted lifeboat to a derelict. The lifeboat is the piloted ship; the
	# derelict it docks to is its host. Build a depth-2 chain by baying the lifeboat into
	# the host's bay AFTER claiming/piloting the host (so host becomes the piloted root
	# with the lifeboat nested in its bay) is complex; instead assert the DFS reposition
	# preserves a deep descendant's relative pose across a second travel.
	ship.board_piloted_ship_for_validation()
	ship.recompute_occupancy()
	var landed := false
	for mid in ids:
		ship.board_piloted_ship_for_validation()
		ship.recompute_occupancy()
		if ship.travel_to_marker_id(String(mid)).get("success", false):
			for _i in range(2):
				await process_frame
			if ship.current_ship_has_bridge_for_validation() and ship.current_ship_id_for_validation() != "":
				landed = true
				break
	assert(landed, "travelled to a claimable derelict (depth-1 rigid pair holds)")

	# The lifeboat (a direct dock child of nothing here, but the piloted ship) — verify the
	# subtree capture/reposition ran without stranding: the piloted ship still has geometry
	# and occupancy is intact.
	assert(ship.piloted_ship_has_geometry_for_validation() == true, "piloted ship kept geometry through DFS travel")

	# Depth-2: claim the derelict, bay the lifeboat into it, then travel home and back —
	# the bayed lifeboat must still be bayed in the (piloted) derelict afterward.
	var derelict_id: String = ship.current_ship_id_for_validation()
	if ship.current_ship_has_bridge_for_validation():
		ship.make_ship_working_for_validation(derelict_id)
		assert(ship.login_at_terminal_for_validation(derelict_id) == true, "claimed derelict")
		# Bay the lifeboat (airlock-docked to the derelict) into the derelict's bay if it has one.
		if ship.ship_bay_slot_count_for_validation(derelict_id) >= 1:
			var slot: int = ship.bay_dock_for_validation(derelict_id)
			if slot >= 0:
				ship.board_piloted_ship_for_validation()
				ship.recompute_occupancy()
				assert(ship.travel_home() == true, "rigid-pair travelled the nested group home")
				for _i in range(2):
					await process_frame
				var bayed_lifeboat_id: String = ship.lifeboat_ship_id_for_validation()
				assert(ship.ship_is_bayed_in_for_validation(bayed_lifeboat_id, derelict_id) == true,
					"bayed lifeboat stayed bayed through nested travel")

	# Deterministic depth-2 DFS guard (seed-independent): A piloted, B docked to A,
	# C docked to B (depth 2). Capture in A's frame, move A, reposition, assert the
	# grandchild C still holds its relative pose to A. This FAILS if the recursion
	# (for grandchild in child.docked_ships) is ever dropped — a real regression guard.
	var a = ShipInstanceScript.create("dfs_a", "cell:cell:a", null, null, Node3D.new())
	var b = ShipInstanceScript.create("dfs_b", "cell:cell:b", null, null, Node3D.new())
	var c = ShipInstanceScript.create("dfs_c", "cell:cell:c", null, null, Node3D.new())
	ship.add_child(a.scene_root); ship.add_child(b.scene_root); ship.add_child(c.scene_root)
	await process_frame
	a.scene_root.global_transform = Transform3D(Basis(), Vector3(0, 0, 0))
	b.scene_root.global_transform = Transform3D(Basis(), Vector3(5, 0, 0))
	c.scene_root.global_transform = Transform3D(Basis(), Vector3(9, 0, 2))
	a.docked_ships = [b]; b.parent_ship = a
	b.docked_ships = [c]; c.parent_ship = b
	var rel_before: Transform3D = (a.scene_root as Node3D).global_transform.affine_inverse() * (c.scene_root as Node3D).global_transform
	var saved_piloted = ship.piloted_ship
	ship.piloted_ship = a
	var captured = ship.capture_subtree_for_validation()
	assert(captured.size() == 2, "DFS captured both B and C (depth-2 reached)")
	(a.scene_root as Node3D).global_transform = Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(20, 0, -13))
	ship.reposition_subtree_for_validation(captured)
	var rel_after: Transform3D = (a.scene_root as Node3D).global_transform.affine_inverse() * (c.scene_root as Node3D).global_transform
	ship.piloted_ship = saved_piloted
	assert(rel_before.origin.distance_to(rel_after.origin) < 0.001, "depth-2 grandchild C preserved relative pose to piloted A")
	# Sever cycles + free synthetic roots so the smoke ends clean (no resources still in use).
	a.docked_ships = []; b.docked_ships = []; b.parent_ship = null; c.parent_ship = null
	a.scene_root.queue_free(); b.scene_root.queue_free(); c.scene_root.queue_free()
	await process_frame

	print("RECURSIVE TRAVEL SMOKE PASS piloted_geom=%s" % str(ship.piloted_ship_has_geometry_for_validation()))
	quit()
