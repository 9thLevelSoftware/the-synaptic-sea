extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT_DIR: String = "res://artifacts/validation-previews/main-playable-slice-v1"
const TIMEOUT_FRAMES: int = 360
const SETTLE_FRAMES: int = 10

var output_dir: String = DEFAULT_OUTPUT_DIR
var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var pending_steps: Array[String] = []
var settle_remaining: int = -1
var captured_count: int = 0

func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail("arg_parse %s" % parsed["error"])
		return
	output_dir = parsed.get("output_dir", DEFAULT_OUTPUT_DIR)
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	pending_steps = ["spawn", "objective_prompt", "objective_complete", "blocked", "vertical", "complete"]
	process_frame.connect(_on_process_frame)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output-dir":
			if index + 1 >= args.size():
				result["error"] = "missing value for --output-dir"
				return result
			result["output_dir"] = args[index + 1]
			index += 2
			continue
		index += 1
	if not result.has("output_dir"):
		result["error"] = "missing --output-dir <directory>"
	return result

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if DisplayServer.get_name() == "headless":
		_fail("capture sequence requires non-headless display")
		return
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	if settle_remaining > 0:
		settle_remaining -= 1
		return
	if settle_remaining == 0:
		_capture_current_step()
		return
	_run_next_step()

func _run_next_step() -> void:
	if pending_steps.is_empty():
		finished = true
		print("MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=%d mode=viewport output_dir=%s" % [captured_count, _resolved_output_dir()])
		quit(0)
		return
	var step: String = pending_steps.pop_front()
	match step:
		"spawn":
			_set_affordance_visibility(PackedStringArray(["EntryBeacon", "RouteCue_", "DestinationReactorCore"]))
			_prepare_capture("01_spawn_airlock")
		"objective_prompt":
			if not playable.teleport_player_to_objective_for_validation(1):
				_fail("could not stage objective 1 prompt")
				return
			_set_affordance_visibility(PackedStringArray(["ObjectiveAffordance_01", "RouteCue_", "EntryBeacon", "DestinationReactorCore"]))
			_prepare_capture("02_objective_01_prompt")
		"objective_complete":
			if not playable.complete_objective_sequence_for_validation(1):
				_fail("could not complete objective 1")
				return
			_set_affordance_visibility(PackedStringArray(["ObjectiveAffordance_02", "RouteCue_", "EntryBeacon", "DestinationReactorCore"]))
			_prepare_capture("03_objective_01_complete")
		"blocked":
			if not _stage_player_near_first_node(playable.loader.get_blocked_route_nodes(), Vector3(0.0, 0.65, -1.4)):
				_fail("could not stage blocked route")
				return
			_set_affordance_visibility(PackedStringArray(["BlockedAffordance_", "RouteCue_", "DestinationReactorCore"]))
			_prepare_capture("04_blocked_route")
		"vertical":
			if not _stage_player_near_first_node(playable.loader.get_visible_vertical_transition_nodes(), Vector3(0.0, 0.65, -1.4)):
				_fail("could not stage vertical transition")
				return
			_set_affordance_visibility(PackedStringArray(["VerticalAffordance_", "RouteCue_", "DestinationReactorCore"]))
			_prepare_capture("05_vertical_transition")
		"complete":
			var completion_guard: int = 0
			var max_completion_steps: int = max(playable.interactables.size() + 2, 8)
			while not playable.slice_complete:
				completion_guard += 1
				if completion_guard > max_completion_steps:
					_fail("completion loop exceeded max steps=%d current_sequence=%d" % [max_completion_steps, playable.get_current_objective_sequence()])
					return
				if not playable.complete_objective_sequence_for_validation(playable.get_current_objective_sequence()):
					_fail("could not complete remaining objective sequence=%d" % playable.get_current_objective_sequence())
					return
			_set_affordance_visibility(PackedStringArray(["EntryBeacon", "RouteCue_", "DestinationReactorCore"]))
			_prepare_capture("06_slice_complete")
		_:
			_fail("unknown capture step %s" % step)

func _prepare_capture(name: String) -> void:
	set_meta("capture_name", name)
	settle_remaining = SETTLE_FRAMES

func _capture_current_step() -> void:
	settle_remaining = -1
	var name: String = str(get_meta("capture_name", "capture"))
	if not _assert_no_visible_label_clutter():
		return
	var image: Image = _capture_viewport_image()
	if image == null:
		_fail("viewport image unavailable")
		return
	var resolved_dir: String = _resolved_output_dir()
	var mkdir_err: int = DirAccess.make_dir_recursive_absolute(resolved_dir)
	if mkdir_err != OK:
		_fail("make_dir_recursive_absolute error=%d dir=%s" % [mkdir_err, resolved_dir])
		return
	var output_path: String = resolved_dir.path_join("%s.png" % name)
	var err: int = image.save_png(output_path)
	if err != OK:
		_fail("save_png error=%d output=%s" % [err, output_path])
		return
	captured_count += 1

func _stage_player_near_first_node(nodes: Array, offset: Vector3) -> bool:
	if playable.player == null or nodes.is_empty():
		return false
	var first = nodes[0]
	if not (first is Node3D):
		return false
	playable.player.teleport_to((first as Node3D).global_position + offset)
	return true

func _assert_no_visible_label_clutter() -> bool:
	if playable == null or not playable.has_method("get_readability_summary"):
		return true
	var summary: Dictionary = playable.get_readability_summary()
	var visible_labels: int = int(summary.get("visible_label3d_count", 0))
	if visible_labels > 0:
		_fail("visible label clutter count=%d" % visible_labels)
		return false
	return true

func _set_affordance_visibility(visible_prefixes: PackedStringArray) -> void:
	if playable == null or playable.affordance_root == null:
		return
	for child in playable.affordance_root.get_children():
		var should_show: bool = false
		for prefix in visible_prefixes:
			if child.name.begins_with(prefix):
				should_show = true
				break
		child.visible = should_show

func _capture_viewport_image() -> Image:
	var texture: ViewportTexture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image

func _resolved_output_dir() -> String:
	return ProjectSettings.globalize_path(output_dir) if output_dir.begins_with("res://") else output_dir

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
	push_error("MAIN PLAYABLE SLICE CAPTURE SEQUENCE FAIL reason=%s" % reason)
	quit(1)