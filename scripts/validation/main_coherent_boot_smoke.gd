extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COHERENT_LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const EXPECTED_OBJECTIVES: int = 4
const EXPECTED_CRITICAL_PATH: int = 5
const EXPECTED_LANDMARKS: int = 2
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
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip child found under main scene")
		return
	if playable.layout_path != COHERENT_LAYOUT_PATH:
		_fail("expected coherent layout %s got %s" % [COHERENT_LAYOUT_PATH, playable.layout_path])
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("coherent playable loader did not finish")
		return
	var summary: Dictionary = playable.get_playable_summary()
	var objective_count: int = int(summary.get("objective_count", 0))
	var critical_path_count: int = playable.loader.get_critical_path().size()
	var landmark_count: int = playable.loader.get_landmark_nodes().size()
	if not bool(summary.get("player_spawned", false)):
		_fail("player not spawned")
		return
	if not bool(summary.get("camera_spawned", false)):
		_fail("camera not spawned")
		return
	if objective_count != EXPECTED_OBJECTIVES:
		_fail("expected %d objectives got %d" % [EXPECTED_OBJECTIVES, objective_count])
		return
	if critical_path_count != EXPECTED_CRITICAL_PATH:
		_fail("expected critical_path=%d got %d" % [EXPECTED_CRITICAL_PATH, critical_path_count])
		return
	if landmark_count < EXPECTED_LANDMARKS:
		_fail("expected landmarks>=%d got %d" % [EXPECTED_LANDMARKS, landmark_count])
		return
	print("MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=%d critical_path=%d landmarks=%d frames=%d" % [objective_count, critical_path_count, landmark_count, frame_count])
	finished = true
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
	push_error("MAIN COHERENT BOOT FAIL reason=%s" % reason)
	quit(1)