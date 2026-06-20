extends SceneTree

# Fresh in-engine viewport capture for the coherent proof ship.
#
# Instantiates the sibling `res://scenes/procgen/playable_coherent_ship.tscn`
# scene (the Task 4 coherent playable scene that reuses the seed-17
# `PlayableGeneratedShip` script with the three fixture-path exports
# overridden to point at the coherent golden fixture), waits for
# `playable_ready`, lets the iso camera settle for a few process frames,
# then captures the root viewport's texture and saves it as PNG.
#
# The pass marker is intentionally:
#   COHERENT PROOF SHIP CAPTURE PASS output=<absolute_path> frame=<frame> mode=viewport
# We deliberately do NOT silently fall back to a synthetic map if the
# viewport texture is unavailable — that would defeat the purpose of an
# "in-engine viewport" capture. Headless runs will fail clearly.
#
# Usage:
#   godot --path <project> --script res://scripts/validation/coherent_proof_ship_capture.gd -- \
#     --output <png> [--capture-frame <n>]
#
# Defaults match the spec: capture frame 180, output
# res://artifacts/validation-previews/coherent-proof-ship.png.

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")
const DEFAULT_OUTPUT_PATH: String = "res://artifacts/validation-previews/coherent-proof-ship.png"
const DEFAULT_CAPTURE_FRAME: int = 180
const POST_READY_SETTLE_FRAMES: int = 6

var output_path: String = DEFAULT_OUTPUT_PATH
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var finished: bool = false
var playable_ship
var playable_ready: bool = false
var post_ready_settle_remaining: int = 0


func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		push_error("COHERENT PROOF SHIP CAPTURE FAIL reason=%s" % parsed["error"])
		quit(1)
		return
	output_path = parsed.get("output", DEFAULT_OUTPUT_PATH)
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))

	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	get_root().add_child(playable_ship)
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
	if not playable_ready:
		return
	if post_ready_settle_remaining > 0:
		post_ready_settle_remaining -= 1
		return
	if frame_count < capture_frame:
		return
	_capture_and_finish()


func _on_playable_ready(_summary: Dictionary) -> void:
	playable_ready = true
	post_ready_settle_remaining = POST_READY_SETTLE_FRAMES


func _on_playable_failed(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COHERENT PROOF SHIP CAPTURE FAIL reason=%s" % reason)
	quit(1)


func _capture_and_finish() -> void:
	finished = true
	var image: Image = _capture_viewport_image()
	if image == null:
		push_error("COHERENT PROOF SHIP CAPTURE FAIL reason=viewport_texture_unavailable display=%s headless=%s" % [DisplayServer.get_name(), str(DisplayServer.get_name() == "headless")])
		quit(1)
		return
	var resolved_path: String = ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") else output_path
	var base_dir: String = resolved_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var save_error: int = image.save_png(resolved_path)
	if save_error != OK:
		push_error("COHERENT PROOF SHIP CAPTURE FAIL reason=save_png error=%d output=%s" % [save_error, resolved_path])
		quit(1)
		return
	print("COHERENT PROOF SHIP CAPTURE PASS output=%s frame=%d mode=viewport" % [resolved_path, frame_count])
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
