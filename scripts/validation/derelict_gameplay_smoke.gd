extends SceneTree

## Main-scene smoke: a boarded derelict runs its own objective loop, completion
## clears it, progress persists across leave/revisit, and the home loop is intact.

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
	var home_sequence_before: int = playable.get_current_objective_sequence()
	_all_operational(playable.get_ship_systems_manager())

	# Board a derelict.
	var world = playable.get_sargasso_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel to derelict failed")
		return

	# Derelict objectives were built and are interactable while aboard.
	if playable.derelict_interactables.is_empty():
		_fail("no derelict objective interactables built on board")
		return
	var controller = playable.get_current_ship().get_objective_controller()
	if controller == null or controller.is_cleared():
		_fail("fresh derelict controller missing or already cleared")
		return

	# Complete every derelict objective through the real interaction path.
	var sequences: Array = []
	for it in playable.derelict_interactables:
		if not sequences.has(int(it.sequence)):
			sequences.append(int(it.sequence))
	sequences.sort()
	for seq in sequences:
		if not playable.complete_derelict_objective_for_validation(seq):
			_fail("could not complete derelict objective sequence %d" % seq)
			return
	if not controller.is_cleared():
		_fail("derelict not cleared after completing all objectives (incl. reach_goal)")
		return
	# HUD reflects derelict completion (codex P2): the tracker must show every
	# completed sequence, not stay at 0/N.
	if playable.tracker == null or playable.tracker.get_completed_count() != sequences.size():
		_fail("derelict HUD did not reflect completions (tracker completed=%d expected=%d)" % [
			(playable.tracker.get_completed_count() if playable.tracker != null else -1), sequences.size()])
		return

	# Leave to home, then revisit: progress + cleared must be restored, and the
	# rebuilt interactables for completed objectives must read as completed.
	if not playable.travel_home():
		_fail("travel_home failed")
		return
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("revisit travel failed")
		return
	var controller2 = playable.get_current_ship().get_objective_controller()
	if not controller2.is_cleared():
		_fail("cleared state not preserved across revisit")
		return
	if playable.derelict_interactables.is_empty():
		_fail("revisit rebuilt no derelict interactables")
		return
	for it in playable.derelict_interactables:
		if not it.completed:
			_fail("revisit: a previously-completed derelict interactable is not marked completed (respawned)")
			return
	# HUD reflects restored completion on revisit (codex P2): the rebuilt tracker
	# must show the cleared derelict's completed sequences, not 0/N.
	if playable.tracker == null or playable.tracker.get_completed_count() != sequences.size():
		_fail("revisit derelict HUD did not reflect restored completions (tracker completed=%d expected=%d)" % [
			(playable.tracker.get_completed_count() if playable.tracker != null else -1), sequences.size()])
		return

	# Home loop intact: return home and confirm the home objective sequence is unchanged.
	if not playable.travel_home():
		_fail("second travel_home failed")
		return
	if playable.away_from_start:
		_fail("away_from_start still true after returning home")
		return
	if playable.get_current_objective_sequence() != home_sequence_before:
		_fail("home objective sequence changed (home loop disturbed)")
		return

	finished = true
	print("DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true")
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
	push_error("DERELICT GAMEPLAY FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
