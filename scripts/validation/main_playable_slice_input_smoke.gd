extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 240
const MOVE_FRAMES: int = 45
const SETTLE_FRAMES: int = 10
const PHASE_TIMEOUT_FRAMES: int = MOVE_FRAMES + SETTLE_FRAMES + 120
const MIN_MOVE_DISTANCE: float = 0.75
const MIN_CAMERA_MOVE_DISTANCE: float = 0.25

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting"
var phase_frames: int = 0
var total_phase_frames: int = 0
var finished: bool = false
var player_start: Vector3 = Vector3.ZERO
var camera_start: Vector3 = Vector3.ZERO

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	if phase == "waiting":
		_begin_move_probe()
		return
	if phase == "moving":
		phase_frames += 1
		total_phase_frames += 1
		if total_phase_frames > PHASE_TIMEOUT_FRAMES:
			_fail(
				"movement phase stalled phase=moving phase_frames=%d total_phase_frames=%d"
				% [phase_frames, total_phase_frames]
			)
			return
		if phase_frames >= MOVE_FRAMES:
			playable.player.clear_scripted_move_direction()
			phase = "settling"
			phase_frames = 0
		return
	if phase == "settling":
		phase_frames += 1
		total_phase_frames += 1
		if total_phase_frames > PHASE_TIMEOUT_FRAMES:
			_fail(
				"movement phase stalled phase=settling phase_frames=%d total_phase_frames=%d"
				% [phase_frames, total_phase_frames]
			)
			return
		if phase_frames >= SETTLE_FRAMES:
			_validate_movement_and_interaction()

func _begin_move_probe() -> void:
	if playable.player == null:
		_fail("player missing")
		return
	if playable.camera_rig == null or playable.camera_rig.camera == null:
		_fail("camera missing")
		return
	player_start = playable.player.global_position
	camera_start = playable.camera_rig.camera.global_position
	playable.player.set_scripted_move_direction(Vector3.RIGHT)
	phase = "moving"
	phase_frames = 0
	total_phase_frames = 0

func _validate_movement_and_interaction() -> void:
	var player_delta: float = playable.player.global_position.distance_to(player_start)
	var camera_delta: float = playable.camera_rig.camera.global_position.distance_to(camera_start)
	var player_final: Vector3 = playable.player.global_position
	if player_delta < MIN_MOVE_DISTANCE:
		_fail(
			"player moved %.3f expected_at_least %.3f player_start=%s player_final=%s"
			% [player_delta, MIN_MOVE_DISTANCE, str(player_start), str(player_final)]
		)
		return
	if camera_delta < MIN_CAMERA_MOVE_DISTANCE:
		var camera_final: Vector3 = playable.camera_rig.camera.global_position
		_fail(
			"camera moved %.3f expected_at_least %.3f camera_start=%s camera_final=%s"
			% [camera_delta, MIN_CAMERA_MOVE_DISTANCE, str(camera_start), str(camera_final)]
		)
		return
	if not playable.teleport_player_to_objective_for_validation(1):
		_fail("could not move player to objective 1")
		return
	var interactable = playable.get_interactable_by_sequence(1)
	if interactable == null or not interactable.has_method("set_validation_player_in_range"):
		_fail("objective 1 interactable missing")
		return
	interactable.set_validation_player_in_range(playable.player)
	playable.player.request_interact()
	if playable.get_current_objective_sequence() != 2:
		_fail("interaction input path did not advance current_sequence=%d" % playable.get_current_objective_sequence())
		return
	finished = true
	print("MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2")
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
	printerr("MAIN PLAYABLE INPUT LOOP FAIL reason=%s" % reason)
	push_error("MAIN PLAYABLE INPUT LOOP FAIL reason=%s" % reason)
	quit(1)
