extends SceneTree
## Main-scene smoke for coherent ship template C (stacked two-deck layout).
##
## Loads PlayableGeneratedShip directly with the template C fixture paths,
## waits for playable_ready, then completes all five objectives via the
## headless validation seam and asserts slice completion.
##
## Pass marker:
##   TEMPLATE C MAIN SCENARIO PASS objectives=5 current_sequence=6 run_complete=true

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_003/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_003/gameplay_slice.json"
const EXPECTED_OBJECTIVE_COUNT: int = 5
const TIMEOUT_FRAMES: int = 300

var playable: Node3D
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "PlayableTemplateC"
	playable.layout_path = LAYOUT_PATH
	playable.kit_path = KIT_PATH
	playable.gameplay_slice_path = GAMEPLAY_SLICE_PATH
	get_root().add_child(playable)
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null or not is_instance_valid(playable):
		_fail("playable freed unexpectedly")
		return
	if not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_run_validation()

func _run_validation() -> void:
	finished = true
	if playable.loader == null or not playable.loader.has_loaded_ship():
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
	print("TEMPLATE C MAIN SCENARIO PASS objectives=%d current_sequence=%d run_complete=true" % [completed, current_sequence])
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("TEMPLATE C MAIN SCENARIO FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
