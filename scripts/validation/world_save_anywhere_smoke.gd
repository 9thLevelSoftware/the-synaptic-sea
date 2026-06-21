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

	# Move the player to a recognisable in-ship position.
	if playable.player != null and playable.player is Node3D:
		(playable.player as Node3D).global_position = Vector3(12.0, 1.5, 7.0)

	# SAVE WHILE ABOARD A DERELICT — must succeed now (was blocked pre-Task 4).
	if not playable.request_save():
		_fail("request_save while aboard a derelict should succeed (save-anywhere)")
		return

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

	# Return home, save on home, reload — home restored, not away.
	if not playable.travel_home():
		_fail("travel_home failed before home-save check")
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
