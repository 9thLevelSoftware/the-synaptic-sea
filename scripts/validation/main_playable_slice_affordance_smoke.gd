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
	var summary: Dictionary = playable.get_affordance_summary()
	var objectives: int = int(summary.get("objective_labels", 0))
	var blocked: int = int(summary.get("blocked_labels", 0))
	var vertical: int = int(summary.get("vertical_labels", 0))
	var landmarks: int = int(summary.get("landmark_labels", 0))
	if objectives != 4:
		_fail("objective_labels=%d" % objectives)
		return
	if blocked != 1:
		_fail("blocked_labels=%d" % blocked)
		return
	if vertical != 1:
		_fail("vertical_labels=%d" % vertical)
		return
	if landmarks < 2:
		_fail("landmark_labels=%d" % landmarks)
		return
	if not bool(summary.get("has_blocked_text", false)):
		_fail("blocked label text missing")
		return
	if not bool(summary.get("has_vertical_text", false)):
		_fail("vertical label text missing")
		return
	finished = true
	print("MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=%d blocked=%d vertical=%d landmarks=%d" % [objectives, blocked, vertical, landmarks])
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
	push_error("MAIN PLAYABLE SLICE AFFORDANCE FAIL reason=%s" % reason)
	quit(1)
