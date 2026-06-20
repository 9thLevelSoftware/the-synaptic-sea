extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

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
	if playable.tracker == null or not (playable.tracker is ObjectiveTracker):
		_fail("tracker is missing or wrong type")
		return
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker

	# Complete sequence 1 so sequence 2 (the repair junction) becomes current.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective sequence 1 failed")
		return

	# After sequence 1 the tracker should show sequence 2 with the
	# REQ-011 "Repair junction" label, not the raw ship-system type
	# "Restore Systems". This is the player-facing HUD label.
	var hud_after_one: String = tracker.get_hud_text()
	if not hud_after_one.contains("Repair junction"):
		_fail("HUD missing 'Repair junction' label after sequence 1: %s" % hud_after_one)
		return
	if hud_after_one.contains("Restore Systems"):
		_fail("HUD still shows ship-system type 'Restore Systems' instead of 'Repair junction': %s" % hud_after_one)
		return
	if not hud_after_one.contains("Repair junction (0/2)"):
		_fail("HUD missing 'Repair junction (0/2)' progress marker: %s" % hud_after_one)
		return

	# Complete the first step of the junction.
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective sequence 2 (first step) failed")
		return
	# The validation helper for sequences with required_steps>1 completes
	# every step on the first call. After it runs, the tracker should show
	# sequence 3 (download_logs) and the repair_junction HUD label must
	# no longer appear.
	var hud_after_two: String = tracker.get_hud_text()
	if hud_after_two.contains("Restore Systems"):
		_fail("HUD still shows ship-system type 'Restore Systems' after sequence 2: %s" % hud_after_two)
		return
	if hud_after_two.contains("Repair junction"):
		_fail("HUD still shows 'Repair junction' after both steps completed: %s" % hud_after_two)
		return
	if not hud_after_two.contains("Download Logs"):
		_fail("HUD missing 'Download Logs' label for sequence 3: %s" % hud_after_two)
		return

	finished = true
	print("OBJECTIVE PROGRESS HUD LABEL PASS repair_junction=Repair_junction restore_systems_suppressed=true sequence_3=Download_Logs")
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
	push_error("OBJECTIVE PROGRESS HUD LABEL FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
