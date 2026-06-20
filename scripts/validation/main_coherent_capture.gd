extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT_PATH: String = "res://artifacts/validation-previews/main-coherent-proof-ship.png"
const DEFAULT_CAPTURE_FRAME: int = 180
const POST_READY_SETTLE_FRAMES: int = 6
const TIMEOUT_FRAMES: int = 360

var output_path: String = DEFAULT_OUTPUT_PATH
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var finished: bool = false
var main_node: Node
var playable_ship: PlayableGeneratedShip
var post_ready_settle_remaining: int = -1

func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail("arg_parse %s" % parsed["error"])
		return
	output_path = parsed.get("output", DEFAULT_OUTPUT_PATH)
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output":
			if index + 1 >= args.size():
				result["error"] = "missing value for --output"
				return result
			result["output"] = args[index + 1]
			index += 2
			continue
		if token == "--capture-frame":
			if index + 1 >= args.size():
				result["error"] = "missing value for --capture-frame"
				return result
			var value: String = args[index + 1]
			if not value.is_valid_int():
				result["error"] = "--capture-frame must be an integer"
				return result
			result["capture_frame"] = int(value)
			index += 2
			continue
		index += 1
	if not result.has("output"):
		result["error"] = "missing --output <png>"
	return result

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable_ship == null:
		playable_ship = _find_playable(main_node)
	if playable_ship == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip child found under main")
		return
	if playable_ship.loader == null or not playable_ship.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable loader did not finish")
		return
	if post_ready_settle_remaining < 0:
		post_ready_settle_remaining = POST_READY_SETTLE_FRAMES
		return
	if post_ready_settle_remaining > 0:
		post_ready_settle_remaining -= 1
		return
	if frame_count < capture_frame:
		return
	_capture_and_finish()

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _capture_and_finish() -> void:
	finished = true
	var image: Image = _capture_viewport_image()
	if image == null:
		_fail("viewport_texture_unavailable display=%s headless=%s" % [DisplayServer.get_name(), str(DisplayServer.get_name() == "headless")])
		return
	var resolved_path: String = ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") else output_path
	var base_dir: String = resolved_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var save_error: int = image.save_png(resolved_path)
	if save_error != OK:
		_fail("save_png error=%d output=%s" % [save_error, resolved_path])
		return
	print("MAIN COHERENT CAPTURE PASS output=%s frame=%d mode=viewport" % [resolved_path, frame_count])
	quit(0)

func _capture_viewport_image() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture: ViewportTexture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN COHERENT CAPTURE FAIL reason=%s" % reason)
	quit(1)