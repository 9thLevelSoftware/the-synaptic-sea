extends SceneTree

## Save-anywhere smoke. Proves: saving WHILE aboard a derelict succeeds; reloading
## restores current_location, the derelict's persisted systems state, and the
## player's in-ship position; saving on the home ship restores home cleanly.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate(playable: PlayableGeneratedShip) -> void:
	playable.get_save_load_service().delete_current_run()  # clean slot
	_all_operational(playable.get_ship_systems_manager())

	# I1 coverage: put the player at a KNOWN home position before traveling away,
	# so travel_to captures it into _home_player_position. After an away-save +
	# fresh-process reload, travel_home() must return the player here (not origin).
	var known_home_pos: Vector3 = Vector3(5.0, 1.5, -3.0)
	if playable.player != null and playable.player is Node3D:
		(playable.player as Node3D).global_position = known_home_pos

	# Travel to a derelict and mutate its systems to a recognisable state.
	var world = playable.get_sargasso_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var id_a: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(id_a).get("success", false)):
		_fail("travel to derelict failed")
		return
	var inst_a = playable.visited_ships[id_a]
	inst_a.systems_manager.force_repair("power", inst_a.systems_manager.get_system("power").subcomponents[0].subcomponent_id)
	var expected_summary: Dictionary = inst_a.systems_manager.get_summary()

	# M1: complete ONE non-reach_goal (salvage) derelict objective through the real
	# interaction path before saving, so the disk round-trip below can prove the
	# derelict's OBJECTIVE progress survives — not just its systems state.
	if playable.derelict_interactables.is_empty():
		_fail("no derelict objective interactables built on board")
		return
	var salvage_seq: int = -1
	for it in playable.derelict_interactables:
		var seq: int = int(it.sequence)
		if String(it.objective_id) == "obj_reach_goal":
			continue
		if salvage_seq < 0 or seq < salvage_seq:
			salvage_seq = seq
	if salvage_seq < 0:
		_fail("no non-reach_goal derelict objective to complete")
		return
	if not playable.complete_derelict_objective_for_validation(salvage_seq):
		_fail("could not complete derelict salvage objective sequence %d" % salvage_seq)
		return
	if not playable.get_current_ship().get_objective_controller().is_objective_complete(salvage_seq):
		_fail("derelict objective %d not marked complete after completion" % salvage_seq)
		return

	# Move the player to a recognisable in-ship position.
	if playable.player != null and playable.player is Node3D:
		(playable.player as Node3D).global_position = Vector3(12.0, 1.5, 7.0)

	# SAVE WHILE ABOARD A DERELICT — must succeed now (was blocked pre-Task 4).
	if not playable.request_save():
		_fail("request_save while aboard a derelict should succeed (save-anywhere)")
		return

	# I1 coverage: simulate a fresh process — the in-memory _home_player_position
	# is gone, so the world load must repopulate it from the saved home slice.
	playable._home_player_position = Vector3.ZERO

	# RELOAD — must restore the derelict location, state, and position.
	if not playable.request_load():
		_fail("request_load of a world save should succeed")
		return
	if not playable.away_from_start:
		_fail("away_from_start false after loading a saved-aboard-derelict world")
		return
	var cur = playable.get_current_ship()
	if cur == null or String(cur.marker_id) != id_a:
		_fail("current_location not restored to the saved derelict")
		return
	if cur.systems_manager.get_summary() != expected_summary:
		_fail("derelict systems state not restored from world save")
		return
	if playable.player == null or not is_instance_valid(playable.player):
		_fail("player invalid after world load")
		return
	var p: Vector3 = (playable.player as Node3D).global_position
	if p.distance_to(Vector3(12.0, 1.5, 7.0)) > 0.5:
		_fail("player in-ship position not restored from world save (got %s)" % str(p))
		return
	# M1: the derelict objective completed before the save must STILL read complete
	# after the disk save -> reload round-trip (objective progress is persisted on the
	# ShipInstance's DerelictObjectiveController, restored via its slice summary).
	if not playable.get_current_ship().get_objective_controller().is_objective_complete(salvage_seq):
		_fail("derelict objective %d did not survive the disk save->load round-trip" % salvage_seq)
		return

	# Return home, save on home, reload — home restored, not away.
	if not playable.travel_home():
		_fail("travel_home failed before home-save check")
		return
	# Phase 5b Task 5 (physical-travel contract): travel_home no longer teleports the
	# player to the saved _home_player_position. The player RIDES the piloted lifeboat,
	# which physically undocks from the derelict and re-docks to home — so they end up
	# aboard the lifeboat docked at home, not at a stored home floor coordinate. The
	# I1 invariant is therefore re-expressed as "back at the home complex, not away":
	# occupancy resolves to the home ship OR the lifeboat docked to home, and
	# away_from_start is false. (Pre-5b this asserted the exact known_home_pos restore.)
	if playable.player == null or not is_instance_valid(playable.player):
		_fail("player invalid after travel_home")
		return
	playable.recompute_occupancy()
	if playable.away_from_start:
		_fail("travel_home left away_from_start true (player not back at home complex)")
		return
	var home_after = playable.get_home_ship_for_validation()
	var lb_after = playable.get_lifeboat_ship_for_validation()
	var occ_after = playable.get_current_occupancy_for_validation()
	if occ_after != home_after and occ_after != lb_after:
		_fail("travel_home did not return the player to the home complex (occupancy=%s)" % str(occ_after))
		return
	# The piloted lifeboat must be physically re-docked to the home ship.
	if lb_after == null or lb_after.parent_ship != home_after:
		_fail("travel_home did not re-dock the lifeboat to home (parent=%s)" % str(lb_after.parent_ship if lb_after != null else null))
		return
	if not playable.request_save():
		_fail("request_save on the home ship should succeed")
		return
	if not playable.request_load():
		_fail("request_load of a home-saved world should succeed")
		return
	if playable.away_from_start:
		_fail("away_from_start true after loading a home-saved world")
		return
	if String(playable.get_current_ship().marker_id) != "":
		_fail("current ship after home-saved load is not the home ship")
		return
	# FIX 1 coverage: after a home-saved reload, the starting-ship gameplay roots
	# must be re-attached under the coordinator so the home sim rebuilds in-tree.
	if playable.oxygen_root == null or playable.oxygen_root.get_parent() != playable:
		_fail("oxygen_root not re-attached under coordinator after home-saved reload")
		return
	if playable.interaction_root == null or playable.interaction_root.get_parent() != playable:
		_fail("interaction_root not re-attached under coordinator after home-saved reload")
		return
	# I1 regression: once back on the home ship, NO derelict objective interactables
	# may remain orphaned under derelict_objective_root, and the tracking array must
	# be empty. A reload-into-home from aboard a derelict (or a travel_home) must have
	# run _clear_derelict_objectives; otherwise the prior derelict's Area3D volumes
	# overlay the home ship.
	if playable.derelict_objective_root == null or playable.derelict_objective_root.get_child_count() != 0:
		_fail("orphaned derelict interactables remain under derelict_objective_root on home ship (I1)")
		return
	if not playable.derelict_interactables.is_empty():
		_fail("derelict_interactables not cleared on home ship (I1)")
		return

	finished = true
	print("WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("WORLD SAVE ANYWHERE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
