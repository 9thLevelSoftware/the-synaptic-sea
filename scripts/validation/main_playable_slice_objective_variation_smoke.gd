extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false

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

func _validate(playable: PlayableGeneratedShip) -> void:
	if not playable.has_method("get_ship_systems_summary"):
		_fail("get_ship_systems_summary missing")
		return
	if not playable.has_method("get_route_control_summary"):
		_fail("get_route_control_summary missing")
		return
	if not playable.has_method("get_objective_progress_summary"):
		_fail("get_objective_progress_summary missing")
		return

	var progress_summary: Dictionary = playable.get_objective_progress_summary()
	if not progress_summary.has(2):
		_fail("sequence 2 not registered in objective progress state")
		return
	var seq2_progress: Dictionary = progress_summary.get(2, {})
	if int(seq2_progress.get("required_steps", -1)) != 2:
		_fail("sequence 2 required_steps=%d expected 2" % int(seq2_progress.get("required_steps", -1)))
		return
	if str(seq2_progress.get("objective_type", "")) != "restore_systems":
		_fail("sequence 2 objective_type=%s expected restore_systems" % str(seq2_progress.get("objective_type", "")))
		return

	var group: Array = playable.sequence_interactables.get(2, [])
	if group.size() != 2:
		_fail("sequence 2 interactable group size=%d expected 2" % group.size())
		return

	# Complete sequence 1 first to advance current_objective_sequence to 2.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective sequence 1 failed")
		return

	# Complete both steps of the repair junction.
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective sequence 2 failed")
		return

	var after_two: Dictionary = playable.get_ship_systems_summary()
	if not bool(after_two.get("main_power_restored", false)):
		_fail("after sequence 2 main_power_restored=false")
		return
	if not bool(after_two.get("blocked_routes_cleared", false)):
		_fail("after sequence 2 blocked_routes_cleared=false")
		return

	var route_after_two: Dictionary = playable.get_route_control_summary()
	if not bool(route_after_two.get("powered_gates_open", false)):
		_fail("after sequence 2 powered_gates_open=false")
		return
	if int(route_after_two.get("active_blocker_count", -1)) != 0:
		_fail("after sequence 2 active_blocker_count=%d expected 0" % int(route_after_two.get("active_blocker_count", -1)))
		return

	var progress_after_two: Dictionary = playable.get_objective_progress_summary().get(2, {})
	if not bool(progress_after_two.get("complete", false)):
		_fail("sequence 2 progress complete=false after both steps")
		return

	# Complete remaining single-step objectives.
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete objective sequence 3 failed")
		return
	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete objective sequence 4 failed")
		return

	var final_route: Dictionary = playable.get_route_control_summary()
	if not bool(final_route.get("extraction_unlocked", false)):
		_fail("final extraction_unlocked=false")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("final run_complete=false")
		return

	finished = true
	print("MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true")
	_cleanup_and_quit(0)

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
	push_error("MAIN PLAYABLE OBJECTIVE VARIATION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
