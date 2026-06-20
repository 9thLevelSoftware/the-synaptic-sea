extends SceneTree

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const DEFAULT_OUTPUT_PATH: String = "res://playable-ship-capture.png"
const DEFAULT_CAPTURE_FRAME: int = 60
const IMAGE_WIDTH: int = 960
const IMAGE_HEIGHT: int = 540
const IMAGE_MARGIN: int = 36
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

var output_path: String = DEFAULT_OUTPUT_PATH
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var finished: bool = false
var playable_ship
var playable_ready: bool = false


func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		push_error("PLAYABLE SHIP CAPTURE FAIL reason=%s" % parsed["error"])
		quit(1)
		return
	output_path = parsed.get("output", DEFAULT_OUTPUT_PATH)
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))

	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)


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


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable_ready and frame_count >= capture_frame:
		_capture_and_finish()


func _on_playable_ready(_summary: Dictionary) -> void:
	playable_ready = true


func _on_playable_failed(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PLAYABLE SHIP CAPTURE FAIL reason=%s" % reason)
	quit(1)


func _capture_and_finish() -> void:
	finished = true
	var image: Image = _capture_viewport_image()
	var used_viewport: bool = image != null
	if image == null:
		# Headless Godot often cannot expose a framebuffer texture. In that case,
		# draw a top-down diagnostic from the actual loaded generated-ship data:
		# floor placements, objective positions, start, goal, and player spawn. This
		# is intentionally not a fake gameplay screenshot.
		image = _build_generated_ship_map_image()
	if image == null:
		push_error("PLAYABLE SHIP CAPTURE FAIL reason=image creation failed")
		quit(1)
		return
	var resolved_path: String = ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") else output_path
	var base_dir: String = resolved_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var save_error: int = image.save_png(resolved_path)
	if save_error != OK:
		push_error("PLAYABLE SHIP CAPTURE FAIL reason=save_png error=%d output=%s" % [save_error, resolved_path])
		quit(1)
		return
	var mode: String = "viewport" if used_viewport else "diagnostic_map"
	print("PLAYABLE SHIP CAPTURE PASS output=%s frame=%d mode=%s" % [resolved_path, frame_count, mode])
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


func _build_generated_ship_map_image() -> Image:
	if playable_ship == null or playable_ship.loader == null:
		return null
	var loader = playable_ship.loader
	var floor_cells: Array = _collect_floor_cells(loader.layout_doc)
	if floor_cells.is_empty():
		return null

	var objective_specs: Array = loader.get_objective_specs_copy()
	var bounds: Dictionary = _compute_bounds(floor_cells, objective_specs, loader.get_start_transform().origin, loader.get_goal_position())
	var image: Image = Image.create(IMAGE_WIDTH, IMAGE_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.015, 0.020, 0.035, 1.0))

	var path_points: Array = [loader.get_start_transform().origin]
	for objective_variant in objective_specs:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var objective_position: Vector3 = _variant_to_vector3(objective.get("position", Vector3.INF))
		if objective_position != Vector3.INF:
			path_points.append(objective_position)
	path_points.append(loader.get_goal_position())
	_draw_path(image, path_points, bounds, Color(0.25, 0.95, 0.55, 1.0))

	for cell_variant in floor_cells:
		var cell: Dictionary = cell_variant
		var position: Vector3 = cell["position"]
		var role: String = str(cell.get("role", "room"))
		var module_id: String = str(cell.get("module_id", ""))
		var color: Color = _room_role_color(role)
		if module_id == "corridor_floor_1x1":
			color = Color(0.32, 0.36, 0.44, 1.0)
		var center: Vector2i = _world_to_pixel(position, bounds)
		var half_cell: int = max(2, int(round(float(bounds["scale"]) * 1.85)))
		_draw_rect(image, center - Vector2i(half_cell, half_cell), Vector2i(half_cell * 2 + 1, half_cell * 2 + 1), color)
		_draw_rect_outline(image, center - Vector2i(half_cell, half_cell), Vector2i(half_cell * 2 + 1, half_cell * 2 + 1), Color(0.04, 0.05, 0.08, 1.0))

	for objective_variant in objective_specs:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var objective_position: Vector3 = _variant_to_vector3(objective.get("position", Vector3.INF))
		if objective_position == Vector3.INF:
			continue
		var objective_pixel: Vector2i = _world_to_pixel(objective_position, bounds)
		_draw_diamond(image, objective_pixel, 9, Color(1.0, 0.86, 0.22, 1.0))
		_draw_diamond(image, objective_pixel, 4, Color(0.10, 0.06, 0.01, 1.0))

	_draw_marker(image, _world_to_pixel(loader.get_start_transform().origin, bounds), Color(0.15, 0.72, 1.0, 1.0), 9)
	_draw_marker(image, _world_to_pixel(loader.get_goal_position(), bounds), Color(1.0, 0.28, 0.22, 1.0), 9)
	if playable_ship.player != null:
		_draw_marker(image, _world_to_pixel(playable_ship.player.global_position, bounds), Color(0.10, 1.0, 1.0, 1.0), 6)

	_draw_legend(image)
	return image


func _collect_floor_cells(layout_doc: Dictionary) -> Array:
	var floor_cells: Array = []
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return floor_cells
	for room_variant in rooms_variant:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", room_id))
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not FLOOR_MODULES.has(module_id):
				continue
			var position: Vector3 = _variant_to_vector3(placement.get("position", []))
			if position == Vector3.INF:
				continue
			floor_cells.append({"position": position, "room_id": room_id, "role": role, "module_id": module_id})
	return floor_cells


func _compute_bounds(floor_cells: Array, objective_specs: Array, start_position: Vector3, goal_position: Vector3) -> Dictionary:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for cell_variant in floor_cells:
		var cell: Dictionary = cell_variant
		var position: Vector3 = cell["position"]
		min_x = min(min_x, position.x)
		max_x = max(max_x, position.x)
		min_z = min(min_z, position.z)
		max_z = max(max_z, position.z)
	for objective_variant in objective_specs:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var objective_position: Vector3 = _variant_to_vector3(objective.get("position", Vector3.INF))
		if objective_position == Vector3.INF:
			continue
		min_x = min(min_x, objective_position.x)
		max_x = max(max_x, objective_position.x)
		min_z = min(min_z, objective_position.z)
		max_z = max(max_z, objective_position.z)
	if start_position != Vector3.INF:
		min_x = min(min_x, start_position.x)
		max_x = max(max_x, start_position.x)
		min_z = min(min_z, start_position.z)
		max_z = max(max_z, start_position.z)
	if goal_position != Vector3.INF:
		min_x = min(min_x, goal_position.x)
		max_x = max(max_x, goal_position.x)
		min_z = min(min_z, goal_position.z)
		max_z = max(max_z, goal_position.z)
	var width: float = max(4.0, max_x - min_x + 4.0)
	var height: float = max(4.0, max_z - min_z + 4.0)
	var scale: float = min(float(IMAGE_WIDTH - IMAGE_MARGIN * 2) / width, float(IMAGE_HEIGHT - IMAGE_MARGIN * 2) / height)
	return {"min_x": min_x - 2.0, "min_z": min_z - 2.0, "scale": scale}


func _world_to_pixel(world_position: Vector3, bounds: Dictionary) -> Vector2i:
	var scale: float = float(bounds["scale"])
	var x: int = int(round(float(IMAGE_MARGIN) + (world_position.x - float(bounds["min_x"])) * scale))
	var y: int = int(round(float(IMAGE_MARGIN) + (world_position.z - float(bounds["min_z"])) * scale))
	return Vector2i(clampi(x, 0, IMAGE_WIDTH - 1), clampi(y, 0, IMAGE_HEIGHT - 1))


func _variant_to_vector3(value: Variant) -> Vector3:
	if typeof(value) == TYPE_VECTOR3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value
		if array_value.size() >= 3:
			return Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))
	return Vector3.INF


func _room_role_color(role: String) -> Color:
	match role:
		"airlock":
			return Color(0.20, 0.46, 0.78, 1.0)
		"cargo":
			return Color(0.64, 0.42, 0.20, 1.0)
		"maintenance":
			return Color(0.60, 0.56, 0.25, 1.0)
		"bridge":
			return Color(0.44, 0.32, 0.70, 1.0)
		"reactor":
			return Color(0.70, 0.26, 0.22, 1.0)
		_:
			return Color(0.24, 0.30, 0.39, 1.0)


func _draw_path(image: Image, path_points: Array, bounds: Dictionary, color: Color) -> void:
	for index in range(path_points.size() - 1):
		var from_position: Vector3 = path_points[index]
		var to_position: Vector3 = path_points[index + 1]
		if from_position == Vector3.INF or to_position == Vector3.INF:
			continue
		_draw_line(image, _world_to_pixel(from_position, bounds), _world_to_pixel(to_position, bounds), color)


func _draw_legend(image: Image) -> void:
	_draw_rect(image, Vector2i(16, 16), Vector2i(132, 16), Color(0.20, 0.46, 0.78, 1.0))
	_draw_rect(image, Vector2i(16, 38), Vector2i(132, 16), Color(0.64, 0.42, 0.20, 1.0))
	_draw_rect(image, Vector2i(16, 60), Vector2i(132, 16), Color(0.60, 0.56, 0.25, 1.0))
	_draw_rect(image, Vector2i(16, 82), Vector2i(132, 16), Color(0.44, 0.32, 0.70, 1.0))
	_draw_rect(image, Vector2i(16, 104), Vector2i(132, 16), Color(0.70, 0.26, 0.22, 1.0))
	_draw_diamond(image, Vector2i(29, 134), 8, Color(1.0, 0.86, 0.22, 1.0))
	_draw_marker(image, Vector2i(74, 134), Color(0.15, 0.72, 1.0, 1.0), 7)
	_draw_marker(image, Vector2i(119, 134), Color(1.0, 0.28, 0.22, 1.0), 7)


func _draw_rect(image: Image, origin: Vector2i, size: Vector2i, color: Color) -> void:
	var x0: int = clampi(origin.x, 0, image.get_width() - 1)
	var y0: int = clampi(origin.y, 0, image.get_height() - 1)
	var x1: int = clampi(origin.x + size.x, 0, image.get_width())
	var y1: int = clampi(origin.y + size.y, 0, image.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			image.set_pixel(x, y, color)


func _draw_rect_outline(image: Image, origin: Vector2i, size: Vector2i, color: Color) -> void:
	_draw_line(image, origin, origin + Vector2i(size.x, 0), color)
	_draw_line(image, origin, origin + Vector2i(0, size.y), color)
	_draw_line(image, origin + Vector2i(size.x, 0), origin + size, color)
	_draw_line(image, origin + Vector2i(0, size.y), origin + size, color)


func _draw_diamond(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y_offset in range(-radius, radius + 1):
		var span: int = radius - abs(y_offset)
		for x_offset in range(-span, span + 1):
			_set_pixel_safe(image, center.x + x_offset, center.y + y_offset, color)


func _draw_marker(image: Image, center: Vector2i, color: Color, radius: int) -> void:
	for y_offset in range(-radius, radius + 1):
		for x_offset in range(-radius, radius + 1):
			if x_offset * x_offset + y_offset * y_offset <= radius * radius:
				_set_pixel_safe(image, center.x + x_offset, center.y + y_offset, color)


func _draw_line(image: Image, from_point: Vector2i, to_point: Vector2i, color: Color) -> void:
	var x0: int = from_point.x
	var y0: int = from_point.y
	var x1: int = to_point.x
	var y1: int = to_point.y
	var dx: int = abs(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -abs(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		_draw_marker(image, Vector2i(x0, y0), color, 2)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


func _set_pixel_safe(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, color)
