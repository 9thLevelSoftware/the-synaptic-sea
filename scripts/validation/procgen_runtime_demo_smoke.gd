extends SceneTree

const GENERATED_SHIP_DEMO_SCENE: PackedScene = preload("res://scenes/procgen/generated_ship_demo.tscn")
const DEFAULT_TIMEOUT_FRAMES: int = 9000

# objective_completed is emitted by GameplayObjectiveVolume and exercised through the runtime demo runner.

var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var frame_count: int = 0
var finished: bool = false
var demo


func _initialize() -> void:
	timeout_frames = _parse_timeout_frames(OS.get_cmdline_user_args())
	demo = GENERATED_SHIP_DEMO_SCENE.instantiate()
	demo.timeout_frames = timeout_frames
	demo.demo_completed.connect(_on_demo_completed)
	demo.demo_failed.connect(_on_demo_failed)
	get_root().add_child(demo)
	physics_frame.connect(_on_physics_frame)


func _parse_timeout_frames(args: PackedStringArray) -> int:
	var parsed_timeout: int = DEFAULT_TIMEOUT_FRAMES
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--timeout-frames":
			if index + 1 >= args.size():
				push_error("missing value for --timeout-frames")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			var value: String = args[index + 1]
			if not value.is_valid_int():
				push_error("--timeout-frames must be an integer")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			parsed_timeout = int(value)
			index += 2
			continue
		index += 1
	return parsed_timeout


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > timeout_frames + 30:
		_timeout_fail()


func _on_demo_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float) -> void:
	if finished:
		return
	finished = true
	print("RUNTIME GAMEPLAY DEMO PASS objectives=%d interactions=%d frames=%d final_distance=%.3f" % [objective_count, interaction_count, frame_count, final_distance])
	quit(0)


func _on_demo_failed(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("RUNTIME GAMEPLAY DEMO SMOKE FAIL reason=%s" % reason)
	quit(1)


func _timeout_fail() -> void:
	if finished:
		return
	finished = true
	push_error("RUNTIME GAMEPLAY DEMO SMOKE FAIL reason=timeout frames=%d" % frame_count)
	quit(1)
