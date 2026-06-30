extends SceneTree

## The coordinator registers a "crouch" InputMap action (Domain 2 stealth control).
##
## Pass marker: CROUCH ACTION PASS registered=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360
var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	# Actions are registered during coordinator init; a few frames is plenty.
	if frame_count < 5 and not InputMap.has_action("crouch"):
		return
	if not InputMap.has_action("crouch"):
		if frame_count > TIMEOUT_FRAMES:
			_fail("crouch action never registered")
		return
	finished = true
	print("CROUCH ACTION PASS registered=true")
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("CROUCH ACTION FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
