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
	if not playable.has_method("get_ship_systems_manager"):
		_fail("get_ship_systems_manager missing")
		return
	var mgr = playable.get_ship_systems_manager()
	if mgr == null:
		_fail("ship_systems_manager null")
		return
	if mgr.system_order.size() != 6:
		_fail("expected 6 systems, got %d" % mgr.system_order.size())
		return
	if mgr.get_system("power") == null or mgr.get_system("life_support") == null:
		_fail("power/life_support missing from manager")
		return
	finished = true
	print("PLAYABLE MANAGER BUILT PASS systems=%d" % mgr.system_order.size())
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
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
	push_error("PLAYABLE MANAGER BUILT FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
