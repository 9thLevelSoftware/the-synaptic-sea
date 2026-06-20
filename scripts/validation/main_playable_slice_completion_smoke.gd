extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const EXPECTED_OBJECTIVE_COUNT: int = 4

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
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
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation returned false")
		return
	var summary: Dictionary = playable.get_slice_completion_summary()
	var completed: int = int(summary.get("objectives_completed", 0))
	var current_sequence: int = int(summary.get("current_sequence", 0))
	var run_complete: bool = bool(summary.get("run_complete", false))
	if completed != EXPECTED_OBJECTIVE_COUNT:
		_fail("completed=%d expected=%d" % [completed, EXPECTED_OBJECTIVE_COUNT])
		return
	if current_sequence != EXPECTED_OBJECTIVE_COUNT + 1:
		_fail("current_sequence=%d expected=%d" % [current_sequence, EXPECTED_OBJECTIVE_COUNT + 1])
		return
	if not run_complete:
		_fail("run_complete=false")
		return
	if playable.tracker == null or not playable.tracker.run_complete:
		_fail("tracker did not mark run complete")
		return
	var hud_text: String = playable.tracker.get_hud_text()
	if not hud_text.contains("Current: COMPLETE"):
		_fail("HUD missing completion banner")
		return
	finished = true
	print("MAIN PLAYABLE SLICE COMPLETE PASS completed=%d current_sequence=%d run_complete=true" % [completed, current_sequence])
	quit(0)

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
	push_error("MAIN PLAYABLE SLICE COMPLETE FAIL reason=%s" % reason)
	quit(1)
