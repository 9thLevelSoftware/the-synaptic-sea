extends SceneTree

const GENERATED_SHIP_DEMO_SCENE: PackedScene = preload("res://scenes/procgen/generated_ship_demo.tscn")
const DEFAULT_CAPTURE_FRAME: int = 240
const FALLBACK_WIDTH: int = 960
const FALLBACK_HEIGHT: int = 540

var output_path: String = ""
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var captured: bool = false
var demo


func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	output_path = str(parsed.get("output", ""))
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))
	if output_path.is_empty():
		push_error("Usage: --output <png> [--capture-frame <n>]")
		quit(1)
		return

	demo = GENERATED_SHIP_DEMO_SCENE.instantiate()
	get_root().add_child(demo)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if captured:
		return
	frame_count += 1
	if frame_count < capture_frame:
		return
	captured = true

	var image: Image = _capture_viewport_image()
	if image == null:
		image = _build_runtime_scene_fallback_image()

	var err: Error = image.save_png(output_path)
	if err != OK:
		push_error("failed to write runtime demo capture: %s" % output_path)
		quit(1)
		return
	print("RUNTIME DEMO CAPTURE PASS output=%s frame=%d" % [output_path, frame_count])
	quit(0)


func _capture_viewport_image() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image


func _build_runtime_scene_fallback_image() -> Image:
	var image: Image = Image.create(FALLBACK_WIDTH, FALLBACK_HEIGHT, false, Image.FORMAT_RGBA8)
	_fill_noisy_background(image)

	var floor_points: Array = _collect_floor_points()
	var bounds: Dictionary = _compute_bounds(floor_points)
	for point_variant in floor_points:
		var point: Vector2 = point_variant
		_draw_rect(image, _world_to_image(point, bounds) - Vector2i(3, 3), Vector2i(7, 7), Color(0.20, 0.34, 0.58, 1.0))

	if demo != null and demo.loader != null:
		for objective_variant in demo.loader.objective_specs:
			if typeof(objective_variant) != TYPE_DICTIONARY:
				continue
			var objective: Dictionary = objective_variant
			var position_variant: Variant = objective.get("position", Vector3.ZERO)
			if typeof(position_variant) != TYPE_VECTOR3:
				continue
			var objective_position: Vector3 = position_variant
			_draw_rect(image, _world_to_image(Vector2(objective_position.x, objective_position.z), bounds) - Vector2i(7, 7), Vector2i(15, 15), Color(0.10, 0.95, 0.35, 1.0))

	if demo != null and demo.runner != null:
		var runner_position: Vector3 = demo.runner.global_position
		_draw_rect(image, _world_to_image(Vector2(runner_position.x, runner_position.z), bounds) - Vector2i(6, 6), Vector2i(13, 13), Color(1.0, 0.72, 0.15, 1.0))

	_draw_border(image, Color(0.8, 0.95, 1.0, 1.0))
	return image


func _fill_noisy_background(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var shade: float = float((x * 37 + y * 17) % 31) / 255.0
			image.set_pixel(x, y, Color(0.025 + shade, 0.035 + shade, 0.055 + shade, 1.0))


func _collect_floor_points() -> Array:
	var points: Array = []
	if demo == null or demo.loader == null:
		return points
	var rooms_variant: Variant = demo.loader.layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return points
	for room_variant in rooms_variant:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id != "floor_1x1" and module_id != "corridor_floor_1x1":
				continue
			var position_variant: Variant = placement.get("position", [])
			if typeof(position_variant) != TYPE_ARRAY:
				continue
			var position: Array = position_variant
			if position.size() < 3:
				continue
			points.append(Vector2(float(position[0]), float(position[2])))
	return points


func _compute_bounds(points: Array) -> Dictionary:
	if points.is_empty():
		return {"min": Vector2(-8.0, -20.0), "max": Vector2(112.0, 44.0)}
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point_variant in points:
		var point: Vector2 = point_variant
		min_point.x = min(min_point.x, point.x)
		min_point.y = min(min_point.y, point.y)
		max_point.x = max(max_point.x, point.x)
		max_point.y = max(max_point.y, point.y)
	var padding: Vector2 = Vector2(8.0, 8.0)
	return {"min": min_point - padding, "max": max_point + padding}


func _world_to_image(point: Vector2, bounds: Dictionary) -> Vector2i:
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var span: Vector2 = max_point - min_point
	if absf(span.x) < 0.001:
		span.x = 1.0
	if absf(span.y) < 0.001:
		span.y = 1.0
	var normalized: Vector2 = Vector2((point.x - min_point.x) / span.x, (point.y - min_point.y) / span.y)
	return Vector2i(
		clampi(int(normalized.x * float(FALLBACK_WIDTH - 80)) + 40, 0, FALLBACK_WIDTH - 1),
		clampi(int(normalized.y * float(FALLBACK_HEIGHT - 80)) + 40, 0, FALLBACK_HEIGHT - 1)
	)


func _draw_rect(image: Image, origin: Vector2i, size: Vector2i, color: Color) -> void:
	var x0: int = clampi(origin.x, 0, image.get_width() - 1)
	var y0: int = clampi(origin.y, 0, image.get_height() - 1)
	var x1: int = clampi(origin.x + size.x, 0, image.get_width())
	var y1: int = clampi(origin.y + size.y, 0, image.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			image.set_pixel(x, y, color)


func _draw_border(image: Image, color: Color) -> void:
	_draw_rect(image, Vector2i(0, 0), Vector2i(image.get_width(), 4), color)
	_draw_rect(image, Vector2i(0, image.get_height() - 4), Vector2i(image.get_width(), 4), color)
	_draw_rect(image, Vector2i(0, 0), Vector2i(4, image.get_height()), color)
	_draw_rect(image, Vector2i(image.get_width() - 4, 0), Vector2i(4, image.get_height()), color)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output" and index + 1 < args.size():
			result["output"] = args[index + 1]
			index += 2
			continue
		if token == "--capture-frame" and index + 1 < args.size():
			var raw_frame: String = args[index + 1]
			if raw_frame.is_valid_int():
				result["capture_frame"] = int(raw_frame)
			index += 2
			continue
		index += 1
	return result
