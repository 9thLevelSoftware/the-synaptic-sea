extends SceneTree

## REQ-DECAY-002: live structural wrappers use walkability_contract slab proxies.
## Marker: STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS walls=true corners=true doors=true aperture=true thickness=0.2 hatch_skipped=true

const WalkabilityContractScript := preload("res://scripts/procgen/walkability_contract.gd")
const WRAPPER_ROOT := "res://scenes/wrappers/structural/ship_structural_v0/"
const STRAIGHT_PATH := WRAPPER_ROOT + "wall_straight_1x1.tscn"
const END_CAP_PATH := WRAPPER_ROOT + "wall_end_cap.tscn"
const INNER_CORNER_PATH := WRAPPER_ROOT + "wall_inner_corner.tscn"
const OUTER_CORNER_PATH := WRAPPER_ROOT + "wall_outer_corner.tscn"
const T_JUNCTION_PATH := WRAPPER_ROOT + "wall_t_junction.tscn"
const DOOR_BLOCKED_PATH := WRAPPER_ROOT + "doorway_frame_blocked_1x1.tscn"
const DOOR_OPEN_PATH := WRAPPER_ROOT + "doorway_frame_open_1x1.tscn"
const HATCH_PATH := WRAPPER_ROOT + "bulkhead_portal_2x1.tscn"
const SIZE_EPS := 0.001
const POS_EPS := 0.05

var _parsed_boxes: Dictionary = {}


func _initialize() -> void:
	var failures: Array[String] = []
	var walls_ok: bool = _check_walls(failures)
	var corners_ok: bool = _check_corners(failures)
	var doors_ok: bool = _check_doors(failures)
	var aperture_ok: bool = _check_aperture(failures)
	var thickness_ok: bool = _check_thickness(failures)
	var hatch_skipped: bool = _check_hatch_skipped(failures)
	if not (walls_ok and corners_ok and doors_ok and aperture_ok and thickness_ok and hatch_skipped):
		failures.append("flag mismatch walls=%s corners=%s doors=%s aperture=%s thickness=%s hatch_skipped=%s" % [
			str(walls_ok), str(corners_ok), str(doors_ok), str(aperture_ok), str(thickness_ok), str(hatch_skipped)
		])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print(
		"STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS walls=%s corners=%s doors=%s aperture=%s thickness=%.1f hatch_skipped=%s"
		% [
			str(walls_ok).to_lower(),
			str(corners_ok).to_lower(),
			str(doors_ok).to_lower(),
			str(aperture_ok).to_lower(),
			WalkabilityContractScript.SLAB_THICKNESS_M,
			str(hatch_skipped).to_lower(),
		]
	)
	quit(0)


func _check_walls(failures: Array[String]) -> bool:
	var wall_size := Vector3(
		WalkabilityContractScript.WALL_HALF_SPAN_M * 2.0,
		WalkabilityContractScript.WALL_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var wall_center := Vector3(0.0, WalkabilityContractScript.WALL_HEIGHT_M * 0.5, 0.0)
	var ok: bool = true
	for scene_path in [STRAIGHT_PATH, END_CAP_PATH]:
		var boxes: Array[CollisionShape3D] = _load_boxes(scene_path, failures)
		if boxes.size() != 1:
			failures.append("%s expected 1 wall slab got %d" % [scene_path, boxes.size()])
			ok = false
			continue
		if not _box_matches(boxes[0], wall_size, wall_center, false):
			failures.append("%s wall slab size/pose mismatch size=%s pos=%s" % [
				scene_path, str(_box_size(boxes[0])), str(boxes[0].position)
			])
			ok = false
	return ok


func _check_corners(failures: Array[String]) -> bool:
	var wing_size := Vector3(
		WalkabilityContractScript.WALL_HALF_SPAN_M * 2.0,
		WalkabilityContractScript.WALL_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var ok: bool = true
	ok = _check_two_wing_corner(INNER_CORNER_PATH, wing_size, failures) and ok
	ok = _check_two_wing_corner(OUTER_CORNER_PATH, wing_size, failures) and ok
	var t_boxes: Array[CollisionShape3D] = _load_boxes(T_JUNCTION_PATH, failures)
	if t_boxes.size() != 3:
		failures.append("%s expected 3 wing slabs got %d" % [T_JUNCTION_PATH, t_boxes.size()])
		return false
	var north: CollisionShape3D = _find_wing_at_axis(t_boxes, "north")
	var east: CollisionShape3D = _find_wing_at_axis(t_boxes, "east")
	var west: CollisionShape3D = _find_wing_at_axis(t_boxes, "west")
	if north == null or east == null or west == null:
		failures.append("%s missing SOLID-wing slabs north/east/west" % T_JUNCTION_PATH)
		return false
	if not _box_size_close(_box_size(north), wing_size) or not _box_size_close(_box_size(east), wing_size) or not _box_size_close(_box_size(west), wing_size):
		failures.append("%s wing sizes must be %s" % [T_JUNCTION_PATH, str(wing_size)])
		ok = false
	if not _is_yaw_identity(north) or not _is_yaw_90(east) or not _is_yaw_90(west):
		failures.append("%s wing axes must match north/east/west sockets" % T_JUNCTION_PATH)
		ok = false
	return ok


func _check_two_wing_corner(scene_path: String, wing_size: Vector3, failures: Array[String]) -> bool:
	var boxes: Array[CollisionShape3D] = _load_boxes(scene_path, failures)
	if boxes.size() != 2:
		failures.append("%s expected 2 wing slabs got %d" % [scene_path, boxes.size()])
		return false
	var north: CollisionShape3D = _find_wing_at_axis(boxes, "north")
	var east: CollisionShape3D = _find_wing_at_axis(boxes, "east")
	if north == null or east == null:
		failures.append("%s missing north/east SOLID-wing slabs" % scene_path)
		return false
	if not _box_size_close(_box_size(north), wing_size) or not _box_size_close(_box_size(east), wing_size):
		failures.append("%s wing sizes must be %s" % [scene_path, str(wing_size)])
		return false
	if not _is_yaw_identity(north) or not _is_yaw_90(east):
		failures.append("%s wing axes must match north/east sockets" % scene_path)
		return false
	return true


func _check_doors(failures: Array[String]) -> bool:
	var ok: bool = true
	var blocked_size := Vector3(
		WalkabilityContractScript.WALL_HALF_SPAN_M * 2.0,
		WalkabilityContractScript.DOOR_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var blocked_center := Vector3(0.0, WalkabilityContractScript.DOOR_HEIGHT_M * 0.5, 0.0)
	var blocked: Array[CollisionShape3D] = _load_boxes(DOOR_BLOCKED_PATH, failures)
	if blocked.size() != 1:
		failures.append("%s expected 1 full slab got %d" % [DOOR_BLOCKED_PATH, blocked.size()])
		ok = false
	elif not _box_matches(blocked[0], blocked_size, blocked_center, false):
		failures.append("%s blocked slab size/pose mismatch size=%s pos=%s" % [
			DOOR_BLOCKED_PATH, str(_box_size(blocked[0])), str(blocked[0].position)
		])
		ok = false
	var open_boxes: Array[CollisionShape3D] = _load_boxes(DOOR_OPEN_PATH, failures)
	if open_boxes.size() != 3:
		failures.append("%s expected 2 posts + header got %d" % [DOOR_OPEN_PATH, open_boxes.size()])
		return false
	var post_size := Vector3(
		WalkabilityContractScript.DOOR_POST_WIDTH_M,
		WalkabilityContractScript.DOOR_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var header_size := Vector3(
		WalkabilityContractScript.WALL_HALF_SPAN_M * 2.0,
		WalkabilityContractScript.DOOR_HEADER_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var west: CollisionShape3D = _find_box_near_x(open_boxes, -WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_size)
	var east: CollisionShape3D = _find_box_near_x(open_boxes, WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_size)
	var header: CollisionShape3D = _find_header(open_boxes, header_size)
	if west == null or east == null or header == null:
		failures.append("%s missing post/header boxes" % DOOR_OPEN_PATH)
		return false
	var post_y: float = WalkabilityContractScript.DOOR_HEIGHT_M * 0.5
	if not _box_matches(west, post_size, Vector3(-WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_y, 0.0), false):
		failures.append("%s west post pose mismatch pos=%s" % [DOOR_OPEN_PATH, str(west.position)])
		ok = false
	if not _box_matches(east, post_size, Vector3(WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_y, 0.0), false):
		failures.append("%s east post pose mismatch pos=%s" % [DOOR_OPEN_PATH, str(east.position)])
		ok = false
	var header_y: float = WalkabilityContractScript.DOOR_HEADER_BOTTOM_Y_M + WalkabilityContractScript.DOOR_HEADER_HEIGHT_M * 0.5
	if not _box_matches(header, header_size, Vector3(0.0, header_y, 0.0), false):
		failures.append("%s header pose mismatch pos=%s size=%s" % [
			DOOR_OPEN_PATH, str(header.position), str(_box_size(header))
		])
		ok = false
	return ok


func _check_aperture(failures: Array[String]) -> bool:
	var open_boxes: Array[CollisionShape3D] = _load_boxes(DOOR_OPEN_PATH, failures)
	if open_boxes.size() != 3:
		return false
	var post_size := Vector3(
		WalkabilityContractScript.DOOR_POST_WIDTH_M,
		WalkabilityContractScript.DOOR_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	)
	var west: CollisionShape3D = _find_box_near_x(open_boxes, -WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_size)
	var east: CollisionShape3D = _find_box_near_x(open_boxes, WalkabilityContractScript.DOOR_POST_OFFSET_X_M, post_size)
	var header: CollisionShape3D = _find_header(open_boxes, Vector3(
		WalkabilityContractScript.WALL_HALF_SPAN_M * 2.0,
		WalkabilityContractScript.DOOR_HEADER_HEIGHT_M,
		WalkabilityContractScript.SLAB_THICKNESS_M
	))
	if west == null or east == null or header == null:
		return false
	var inner_west: float = west.position.x + _box_size(west).x * 0.5
	var inner_east: float = east.position.x - _box_size(east).x * 0.5
	var opening_width: float = inner_east - inner_west
	var header_bottom: float = header.position.y - _box_size(header).y * 0.5
	if opening_width + SIZE_EPS < WalkabilityContractScript.DOOR_OPENING_WIDTH_M:
		failures.append("open doorway aperture width=%.3f expected>=%.2f" % [
			opening_width, WalkabilityContractScript.DOOR_OPENING_WIDTH_M
		])
		return false
	if header_bottom + SIZE_EPS < WalkabilityContractScript.STANDING_OPENING_HEIGHT_M:
		failures.append("open doorway header bottom=%.3f expected>=%.2f" % [
			header_bottom, WalkabilityContractScript.STANDING_OPENING_HEIGHT_M
		])
		return false
	if opening_width + SIZE_EPS < WalkabilityContractScript.STANDING_OPENING_WIDTH_M:
		failures.append("open doorway cannot pass standing width=%.2f" % WalkabilityContractScript.STANDING_OPENING_WIDTH_M)
		return false
	return true


func _check_thickness(failures: Array[String]) -> bool:
	var paths: Array[String] = [
		STRAIGHT_PATH, END_CAP_PATH, INNER_CORNER_PATH, OUTER_CORNER_PATH,
		T_JUNCTION_PATH, DOOR_BLOCKED_PATH, DOOR_OPEN_PATH,
	]
	var expected: float = WalkabilityContractScript.SLAB_THICKNESS_M
	for scene_path in paths:
		var boxes: Array[CollisionShape3D] = _load_boxes(scene_path, failures)
		for box_node in boxes:
			var size: Vector3 = _box_size(box_node)
			if absf(size.z - expected) > SIZE_EPS:
				failures.append("%s slab thickness actual=%.3f expected=%.2f" % [scene_path, size.z, expected])
				return false
	return is_equal_approx(expected, 0.2)


func _check_hatch_skipped(failures: Array[String]) -> bool:
	var boxes: Array[CollisionShape3D] = _load_boxes(HATCH_PATH, failures)
	if boxes.size() != 1:
		failures.append("%s hatch must stay a single proxy, got %d" % [HATCH_PATH, boxes.size()])
		return false
	if not _box_size_close(_box_size(boxes[0]), Vector3(1.0, 1.0, 1.0)):
		failures.append("%s hatch proxy changed size=%s (out of scope)" % [HATCH_PATH, str(_box_size(boxes[0]))])
		return false
	return true


func _load_boxes(scene_path: String, failures: Array[String]) -> Array[CollisionShape3D]:
	if _parsed_boxes.has(scene_path):
		return _parsed_boxes[scene_path]
	var boxes: Array[CollisionShape3D] = _parse_wrapper_boxes(scene_path, failures)
	_parsed_boxes[scene_path] = boxes
	return boxes


func _parse_wrapper_boxes(scene_path: String, failures: Array[String]) -> Array[CollisionShape3D]:
	# Authored CollisionShape3D proxies only — skip PackedScene so missing
	# damaged/breached GLB imports cannot mask a collision-contract failure.
	var text: String = FileAccess.get_file_as_string(scene_path)
	if text.is_empty():
		failures.append("could not read %s" % scene_path)
		return []
	var shape_sizes: Dictionary = {}
	var boxes: Array[CollisionShape3D] = []
	var in_box_res: bool = false
	var in_collision: bool = false
	var current_shape_id: String = ""
	var current_pos := Vector3.ZERO
	var current_xform := Transform3D.IDENTITY
	var current_has_xform: bool = false
	var current_shape_ref: String = ""
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("[sub_resource type=\"BoxShape3D\""):
			_flush_collision(boxes, shape_sizes, in_collision, current_pos, current_xform, current_has_xform, current_shape_ref)
			in_collision = false
			in_box_res = true
			current_shape_id = _extract_quoted(line, "id")
			continue
		if line.begins_with("[node ") and line.contains("type=\"CollisionShape3D\""):
			_flush_collision(boxes, shape_sizes, in_collision, current_pos, current_xform, current_has_xform, current_shape_ref)
			in_box_res = false
			in_collision = true
			current_pos = Vector3.ZERO
			current_xform = Transform3D.IDENTITY
			current_has_xform = false
			current_shape_ref = ""
			continue
		if line.begins_with("["):
			_flush_collision(boxes, shape_sizes, in_collision, current_pos, current_xform, current_has_xform, current_shape_ref)
			in_box_res = false
			in_collision = false
			continue
		if in_box_res and line.begins_with("size ="):
			shape_sizes[current_shape_id] = _parse_vector3(line)
		elif in_collision and line.begins_with("position ="):
			current_pos = _parse_vector3(line)
		elif in_collision and line.begins_with("transform ="):
			current_xform = _parse_transform3d(line)
			current_has_xform = true
		elif in_collision and line.begins_with("shape ="):
			current_shape_ref = _extract_subresource_id(line)
	_flush_collision(boxes, shape_sizes, in_collision, current_pos, current_xform, current_has_xform, current_shape_ref)
	if boxes.is_empty():
		failures.append("no BoxShape3D collision in %s" % scene_path)
	return boxes


func _flush_collision(
		boxes: Array[CollisionShape3D],
		shape_sizes: Dictionary,
		in_collision: bool,
		pos: Vector3,
		xform: Transform3D,
		has_xform: bool,
		shape_ref: String) -> void:
	if not in_collision or shape_ref.is_empty() or not shape_sizes.has(shape_ref):
		return
	var box := BoxShape3D.new()
	box.size = shape_sizes[shape_ref]
	var node := CollisionShape3D.new()
	node.shape = box
	if has_xform:
		node.transform = xform
	else:
		node.position = pos
	get_root().add_child(node)
	boxes.append(node)


func _extract_quoted(line: String, key: String) -> String:
	var token: String = key + "=\""
	var start: int = line.find(token)
	if start < 0:
		return ""
	start += token.length()
	var end: int = line.find("\"", start)
	if end < 0:
		return ""
	return line.substr(start, end - start)


func _extract_subresource_id(line: String) -> String:
	var start: int = line.find("SubResource(\"")
	if start < 0:
		return ""
	start += 13
	var end: int = line.find("\"", start)
	if end < 0:
		return ""
	return line.substr(start, end - start)


func _parse_vector3(line: String) -> Vector3:
	var start: int = line.find("Vector3(")
	if start < 0:
		return Vector3.ZERO
	var inner: String = line.substr(start + 8, line.rfind(")") - start - 8)
	var parts: PackedStringArray = inner.split(",")
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float())


func _parse_transform3d(line: String) -> Transform3D:
	var start: int = line.find("Transform3D(")
	if start < 0:
		return Transform3D.IDENTITY
	var inner: String = line.substr(start + 12, line.rfind(")") - start - 12)
	var parts: PackedStringArray = inner.split(",")
	if parts.size() < 12:
		return Transform3D.IDENTITY
	var values: Array[float] = []
	for part in parts:
		values.append(part.strip_edges().to_float())
	var x_axis := Vector3(values[0], values[3], values[6])
	var y_axis := Vector3(values[1], values[4], values[7])
	var z_axis := Vector3(values[2], values[5], values[8])
	var origin := Vector3(values[9], values[10], values[11])
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


func _box_size(node: CollisionShape3D) -> Vector3:
	return (node.shape as BoxShape3D).size


func _box_size_close(actual: Vector3, expected: Vector3) -> bool:
	return actual.distance_to(expected) < SIZE_EPS


func _box_matches(node: CollisionShape3D, expected_size: Vector3, expected_pos: Vector3, require_yaw_90: bool) -> bool:
	if not _box_size_close(_box_size(node), expected_size):
		return false
	if node.position.distance_to(expected_pos) > POS_EPS:
		return false
	if require_yaw_90:
		return _is_yaw_90(node)
	return _is_yaw_identity(node)


func _is_yaw_identity(node: CollisionShape3D) -> bool:
	# Local Z is the 0.20 m thickness axis; identity keeps it on world ±Z.
	var basis: Basis = node.transform.basis.orthonormalized()
	return absf(basis.z.dot(Vector3.RIGHT)) < 0.05


func _is_yaw_90(node: CollisionShape3D) -> bool:
	var basis: Basis = node.transform.basis.orthonormalized()
	# +90° Y maps local +Z (thickness) onto world ±X.
	return absf(basis.z.dot(Vector3.RIGHT)) > 0.95


func _find_wing_at_axis(boxes: Array[CollisionShape3D], axis: String) -> CollisionShape3D:
	var half_span: float = WalkabilityContractScript.WALL_HALF_SPAN_M
	for box_node in boxes:
		match axis:
			"north":
				if absf(box_node.position.z + half_span) <= POS_EPS and _is_yaw_identity(box_node):
					return box_node
			"east":
				if absf(box_node.position.x - half_span) <= POS_EPS and _is_yaw_90(box_node):
					return box_node
			"west":
				if absf(box_node.position.x + half_span) <= POS_EPS and _is_yaw_90(box_node):
					return box_node
	return null


func _find_box_near_x(boxes: Array[CollisionShape3D], expected_x: float, expected_size: Vector3) -> CollisionShape3D:
	for box_node in boxes:
		if absf(box_node.position.x - expected_x) <= POS_EPS and _box_size_close(_box_size(box_node), expected_size):
			return box_node
	return null


func _find_header(boxes: Array[CollisionShape3D], expected_size: Vector3) -> CollisionShape3D:
	for box_node in boxes:
		if _box_size_close(_box_size(box_node), expected_size):
			return box_node
	return null
