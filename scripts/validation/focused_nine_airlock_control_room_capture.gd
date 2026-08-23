extends Node3D

# CLI (non-headless only):
#   godot --path . --scene res://scenes/validation/focused_nine_airlock_control_room_harness.tscn -- \
#     --output-dir DIR
#
# The full capture trusts the workspace against same-user concurrent filesystem
# mutation/rebinding. Existing staging/root and publication-leaf checks are
# defense-in-depth, but Godot filesystem APIs cannot pin those paths for the
# complete capture/publication window.
const TRUST_BOUNDARY_DOCUMENTATION := "same-user concurrent filesystem mutation/rebinding of project/output paths is outside the capture's trusted-workspace boundary for its full run; staging/root path checks and leaf constraints remain defense-in-depth but cannot pin Godot filesystem operations."

const CAMERA_SIZE := 18.0
const CAPTURE_WIDTH: int = 1600
const CAPTURE_HEIGHT: int = 900
const STAGED_ROOT := "res://assets/_staging/focused_nine/"
const APPROVED_OUTPUT_ROOT := "res://artifacts/validation-previews/focused-nine"
const REALPATH_COMMAND := "/bin/realpath"
const TEST_COMMAND := "/bin/test"
const MKTEMP_COMMAND := "/usr/bin/mktemp"
const FIRST_FRAME_NAME := "focused-nine-airlock-control-room00000000.png"
const STABLE_OUTPUT_NAME := "focused-nine-airlock-control-room.png"
const TEMPORARY_FILE_PREFIX := ".focused-nine-airlock-control-room"

const FLOOR_GLB_PATH := "res://assets/_staging/focused_nine/structural/floor_1x1/floor_1x1.glb"
const WALL_GLB_PATH := "res://assets/_staging/focused_nine/structural/wall_straight_1x1/wall_straight_1x1.glb"
const DOORWAY_GLB_PATH := "res://assets/_staging/focused_nine/structural/doorway_frame_open_1x1/doorway_frame_open_1x1.glb"
const PILLAR_GLB_PATH := "res://assets/_staging/focused_nine/structural/pillar_support_1x1/pillar_support_1x1.glb"
const RAMP_GLB_PATH := "res://assets/_staging/focused_nine/structural/ramp_up_1x2/ramp_up_1x2.glb"
const CEILING_GLB_PATH := "res://assets/_staging/focused_nine/structural/ceiling_cap_1x1/ceiling_cap_1x1.glb"
const PRESSURE_DOOR_GLB_PATH := "res://assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
const HULL_BREACH_GLB_PATH := "res://assets/_staging/focused_nine/props/hull_breach_seal_point.glb"
const FIRE_SUPPRESSION_GLB_PATH := "res://assets/_staging/focused_nine/props/fire_suppression_station.glb"

const FLOOR_LAYOUT: Array[Vector3] = [
	Vector3(-4.0, 0.0, -4.0), Vector3(0.0, 0.0, -4.0), Vector3(4.0, 0.0, -4.0),
	Vector3(-4.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0),
	Vector3(-4.0, 0.0, 4.0), Vector3(0.0, 0.0, 4.0), Vector3(4.0, 0.0, 4.0),
]

var _finished: bool = false
var _output_dir_global: String = ""
var _temporary_sequence: int = 0
var _last_failure_reason: String = ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("non_headless_capture_required")
		return

	var parsed: Dictionary = _parse_user_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	_output_dir_global = _prepare_output_dir(str(parsed["output_dir"]))
	if _output_dir_global.is_empty():
		return

	DisplayServer.window_set_size(Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT))
	get_viewport().size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	var camera: Camera3D = get_node_or_null("RoomCamera") as Camera3D
	var room: Node3D = get_node_or_null("Room") as Node3D
	if camera == null or room == null:
		_fail("room camera or room root is missing")
		return
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, CAMERA_SIZE):
		_fail("camera contract mismatch")
		return
	if not _populate_room(room):
		return
	call_deferred("_capture_after_frames")


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"output_dir": ""}
	var seen_output_dir: bool = false
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if token == "--":
			return {"error": "unexpected argument --"}
		if token != "--output-dir":
			return {"error": "unknown argument %s" % token}
		if seen_output_dir:
			return {"error": "duplicate option --output-dir"}
		seen_output_dir = true
		if index + 1 >= args.size() or str(args[index + 1]).begins_with("--"):
			return {"error": "missing value for --output-dir"}
		var value: String = str(args[index + 1]).strip_edges()
		if value.is_empty():
			return {"error": "empty value for --output-dir"}
		result["output_dir"] = value
		index += 2
	if str(result["output_dir"]).is_empty():
		return {"error": "missing --output-dir DIR"}
	return result


func _resolve_output_dir(raw_path: String) -> String:
	var candidate: String = raw_path.strip_edges()
	if candidate.begins_with("res://"):
		candidate = ProjectSettings.globalize_path(candidate)
	elif not candidate.is_absolute_path():
		candidate = ProjectSettings.globalize_path("res://" + candidate.trim_prefix("./"))
	candidate = candidate.simplify_path()
	var project_root: String = ProjectSettings.globalize_path("res://").simplify_path()
	var approved_root: String = ProjectSettings.globalize_path(APPROVED_OUTPUT_ROOT).simplify_path()
	if not _is_path_within(candidate, approved_root):
		_fail("output directory must be inside approved focused-nine subtree")
		return ""
	if FileAccess.file_exists(candidate) and not DirAccess.dir_exists_absolute(candidate):
		_fail("output directory is an existing file")
		return ""

	var project_physical: String = _canonicalize_path(project_root)
	var approved_physical: String = _canonicalize_path(approved_root)
	var candidate_physical: String = _canonicalize_path(candidate)
	if project_physical.is_empty() or approved_physical.is_empty() or candidate_physical.is_empty():
		return ""
	if not _is_path_within(approved_physical, project_physical):
		_fail("approved focused-nine subtree is outside physical project root")
		return ""
	if not _is_path_within(candidate_physical, project_physical):
		_fail("output directory must be inside physical project root")
		return ""
	if not _is_path_within(candidate_physical, approved_physical):
		_fail("output directory must be inside approved focused-nine subtree")
		return ""
	return candidate_physical


func _prepare_output_dir(raw_path: String) -> String:
	var resolved_path: String = _resolve_output_dir(raw_path)
	if resolved_path.is_empty():
		return ""
	var make_error: Error = DirAccess.make_dir_recursive_absolute(resolved_path)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		_fail("could not create output directory error=%d" % make_error)
		return ""
	# Re-canonicalize after creation so a symlink introduced in the output chain
	# cannot be accepted by a later publication operation.
	return _resolve_output_dir(resolved_path)


func _is_path_within(candidate: String, root: String) -> bool:
	if candidate == root:
		return true
	if root == "/":
		return candidate.begins_with("/")
	return candidate.begins_with(root + "/")


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _canonicalize_path(path: String) -> String:
	var cursor: String = path.simplify_path()
	var missing_components: Array[String] = []
	while not _path_exists(cursor):
		var parent: String = cursor.get_base_dir()
		var component: String = cursor.get_file()
		if parent == cursor or component.is_empty():
			_fail("could not find an existing path ancestor")
			return ""
		missing_components.push_front(component)
		cursor = parent
	var canonical_ancestor: String = _realpath_existing(cursor)
	if canonical_ancestor.is_empty():
		return ""
	for component in missing_components:
		canonical_ancestor = canonical_ancestor.path_join(component)
	return canonical_ancestor.simplify_path()


func _realpath_existing(path: String) -> String:
	if not _path_exists(path):
		_fail("realpath ancestor does not exist")
		return ""
	if not FileAccess.file_exists(REALPATH_COMMAND):
		_fail("realpath command is unavailable")
		return ""
	var command_output: Array[String] = []
	var command_status: int = OS.execute(REALPATH_COMMAND, PackedStringArray([path]), command_output, true, true)
	if command_status != OK or command_output.size() != 1:
		_fail("could not canonicalize path with realpath")
		return ""
	var canonical_path: String = command_output[0].strip_edges()
	if canonical_path.is_empty() or not canonical_path.is_absolute_path():
		_fail("realpath returned an invalid canonical path")
		return ""
	return canonical_path.simplify_path()


func _populate_room(room: Node3D) -> bool:
	# Nine exact 4 m floor instances. South is +Z for the locked camera below.
	for index in FLOOR_LAYOUT.size():
		var floor_visual: Node3D = _load_glb(FLOOR_GLB_PATH)
		if floor_visual == null:
			return false
		_disable_local_lights(floor_visual)
		floor_visual.name = "Floor_%02d" % index
		floor_visual.position = FLOOR_LAYOUT[index]
		room.add_child(floor_visual)

	# South entry: the open doorway and ramp point toward the viewer (+Z).
	if not _add_room_asset(room, DOORWAY_GLB_PATH, "SouthDoorway", Vector3(0.0, 0.0, 4.0), 0.0):
		return false
	# GLTF probe: the ramp's local z bounds are -4..4 and its high end is at
	# local -Z, so z=8 feeds the south doorway from z=4..12 without entering it.
	if not _add_room_asset(room, RAMP_GLB_PATH, "SouthRamp", Vector3(0.0, 0.0, 8.0), 0.0):
		return false

	# North center pressure door; the intact face looks into the room (-Z).
	if not _add_room_asset(room, PRESSURE_DOOR_GLB_PATH, "NorthPressureDoor", Vector3(0.0, 0.0, -4.0), PI):
		return false

	# The wall GLTF spans local x=-2..2 and thin local z. North and south pairs
	# leave centered pressure-door/entry cutaways; the last two are true side
	# segments rotated onto the east/west perimeter at x=+/-6.
	var wall_positions: Array[Vector3] = [
		Vector3(-4.0, 0.0, -6.0), Vector3(4.0, 0.0, -6.0),
		Vector3(-4.0, 0.0, 6.0), Vector3(4.0, 0.0, 6.0),
		Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0),
	]
	for index in wall_positions.size():
		var wall_rotation: float = PI / 2.0 if index >= 4 else 0.0
		if not _add_room_asset(room, WALL_GLB_PATH, "Wall_%02d" % index, wall_positions[index], wall_rotation):
			return false

	# Rear pillars frame the door and rear ceiling caps close only the back row.
	if not _add_room_asset(room, PILLAR_GLB_PATH, "RearPillarWest", Vector3(-3.0, 0.0, -3.0), 0.0):
		return false
	if not _add_room_asset(room, PILLAR_GLB_PATH, "RearPillarEast", Vector3(3.0, 0.0, -3.0), 0.0):
		return false
	# GLTF probe: ceiling local y=3.72..4.0, so y=0 keeps the cap around
	# the wall's 3.5 m top; y=3 would place it at roughly y=6.7.
	for index in 3:
		if not _add_room_asset(room, CEILING_GLB_PATH, "RearCeilingCap_%02d" % index, Vector3(-4.0 + index * 4.0, 0.0, -4.0), 0.0):
			return false

	# Dressing: fire station beside the south entry and breach seal on east wall.
	if not _add_room_asset(room, FIRE_SUPPRESSION_GLB_PATH, "FireSuppressionBesideEntry", Vector3(-2.0, 0.0, 3.0), 0.0):
		return false
	var east_wall: Node3D = room.get_node_or_null("Wall_05") as Node3D
	if east_wall == null:
		_fail("east wall is missing for breach seal anchoring")
		return false
	var breach_visual: Node3D = _load_glb(HULL_BREACH_GLB_PATH)
	if breach_visual == null:
		return false
	_disable_local_lights(breach_visual)
	breach_visual.name = "EastWallBreachSeal"
	breach_visual.rotation.y = PI / 2.0
	# Anchor from direct imported bounds: the prop's rotated max-x meets the
	# east wall's inner-face min-x, and its min-y meets the floor.
	var east_wall_bounds: AABB = _bounds_in_ancestor(east_wall, room)
	var breach_local_bounds: AABB = _bounds_in_ancestor(breach_visual, breach_visual)
	var breach_rotated_bounds: AABB = _transform_aabb(breach_local_bounds, Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO))
	var wall_midpoint_z: float = (east_wall_bounds.position.z + east_wall_bounds.end.z) / 2.0
	var breach_midpoint_z: float = (breach_rotated_bounds.position.z + breach_rotated_bounds.end.z) / 2.0
	breach_visual.position = Vector3(
		east_wall_bounds.position.x - breach_rotated_bounds.end.x,
		-breach_rotated_bounds.position.y,
		wall_midpoint_z - breach_midpoint_z,
	)
	room.add_child(breach_visual)
	return true


func _bounds_in_ancestor(node: Node3D, ancestor: Node3D) -> AABB:
	var found: bool = false
	var combined := AABB()
	var node_transform: Transform3D = _transform_to_ancestor(node, ancestor)
	for mesh_node: Node in node.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = mesh_node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var mesh_transform: Transform3D = node_transform * _transform_to_ancestor(instance, node)
		var local_bounds: AABB = instance.mesh.get_aabb()
		for x in [local_bounds.position.x, local_bounds.end.x]:
			for y in [local_bounds.position.y, local_bounds.end.y]:
				for z in [local_bounds.position.z, local_bounds.end.z]:
					var point: Vector3 = mesh_transform * Vector3(x, y, z)
					if not found:
						combined = AABB(point, Vector3.ZERO)
						found = true
					else:
						combined = combined.expand(point)
	if not found:
			_fail("GLTF asset has no mesh bounds")
	return combined


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor:
		var node_3d: Node3D = cursor as Node3D
		if node_3d == null:
			_fail("GLTF asset hierarchy contains a non-Node3D")
			return Transform3D.IDENTITY
		result = node_3d.transform * result
		cursor = cursor.get_parent()
		if cursor == null:
			_fail("GLTF asset escaped its ancestor")
			return Transform3D.IDENTITY
	return result


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var found: bool = false
	var transformed := AABB()
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var point: Vector3 = transform * Vector3(x, y, z)
				if not found:
					transformed = AABB(point, Vector3.ZERO)
					found = true
				else:
					transformed = transformed.expand(point)
	return transformed


func _add_room_asset(room: Node3D, path: String, node_name: String, position: Vector3, rotation_y: float) -> bool:
	var visual: Node3D = _load_glb(path)
	if visual == null:
		return false
	_disable_local_lights(visual)
	visual.name = node_name
	visual.position = position
	visual.rotation.y = rotation_y
	room.add_child(visual)
	return true


func _disable_local_lights(node: Node) -> void:
	if node is Light3D:
		node.visible = false
	for child: Node in node.get_children():
		if child is Light3D:
			child.visible = false
		_disable_local_lights(child)


func _load_glb(path: String) -> Node3D:
	if not path.begins_with(STAGED_ROOT):
		_fail("staged source path escaped focused-nine root: %s" % path)
		return null
	if not _validate_staged_component(path):
		return null
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var append_error: Error = document.append_from_file(ProjectSettings.globalize_path(path), state)
	if append_error != OK:
		_fail("could not load staged GLB: %s error=%d" % [path, append_error])
		return null
	var generated: Node = document.generate_scene(state)
	if generated == null:
		_fail("could not generate staged GLB scene: %s" % path)
		return null
	var visual: Node3D = generated as Node3D
	if visual == null:
		generated.free()
		_fail("staged GLB scene root is not Node3D: %s" % path)
		return null
	return visual


func _validate_staged_component(path: String) -> bool:
	if not path.begins_with(STAGED_ROOT):
		_fail("staged source component escaped focused-nine root: %s" % path)
		return false
	var absolute_path: String = ProjectSettings.globalize_path(path).simplify_path()
	if _contains_symlink_component(absolute_path):
		_fail("symlinked staged source component: %s" % path)
		return false
	var entry_kind: String = _path_entry_kind(absolute_path)
	if entry_kind == "missing":
		_fail("missing staged source component: %s" % path)
		return false
	if entry_kind == "error":
		return false
	if entry_kind != "regular":
		_fail("staged source component is not a regular file: %s" % path)
		return false
	var staged_root: String = _canonicalize_path(ProjectSettings.globalize_path(STAGED_ROOT))
	var canonical_path: String = _canonicalize_path(absolute_path)
	if staged_root.is_empty() or canonical_path.is_empty():
		return false
	if not _is_path_within(canonical_path, staged_root):
		_fail("staged source component resolved outside focused-nine root: %s" % path)
		return false
	return true


func _contains_symlink_component(absolute_path: String) -> bool:
	var cursor: String = absolute_path
	while true:
		var symlink_status: int = _native_test_flag("-L", cursor)
		if symlink_status < 0:
			return true
		if symlink_status == OK:
			return true
		var parent: String = cursor.get_base_dir()
		if parent == cursor:
			return false
		cursor = parent
	return false


func _capture_after_frames() -> void:
	for frame_index in 10:
		await get_tree().process_frame
	if _finished:
		return
	_capture_first_frame()


func _capture_first_frame() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("non_headless_capture_required")
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_fail("viewport is unavailable")
		return
	var root_texture: ViewportTexture = viewport.get_texture()
	if root_texture == null:
		_fail("viewport texture is unavailable")
		return
	var image: Image = root_texture.get_image()
	if image == null or image.is_empty():
		_fail("viewport image is empty")
		return
	if image.get_width() != CAPTURE_WIDTH or image.get_height() != CAPTURE_HEIGHT:
		_fail("capture resolution must be 1600x900")
		return
	if not _publish_capture_files(image):
		return
	print("FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output=%s" % _output_dir_global.path_join(STABLE_OUTPUT_NAME))
	_finished = true
	get_tree().quit(0)


func _publish_capture_files(image: Image) -> bool:
	var output_dir: String = _publication_output_dir()
	if output_dir.is_empty():
		return false
	var first_frame_path: String = output_dir.path_join(FIRST_FRAME_NAME)
	var stable_path: String = output_dir.path_join(STABLE_OUTPUT_NAME)
	if not _validate_publication_leaf(first_frame_path) or not _validate_publication_leaf(stable_path):
		return false
	var first_snapshot: Dictionary = _snapshot_publication_leaf(first_frame_path)
	var stable_snapshot: Dictionary = _snapshot_publication_leaf(stable_path)
	if first_snapshot.has("error") or stable_snapshot.has("error"):
		return false

	var first_temporary: String = _allocate_temporary_path(FIRST_FRAME_NAME)
	if first_temporary.is_empty():
		return false
	var stable_temporary: String = _allocate_temporary_path(STABLE_OUTPUT_NAME)
	if stable_temporary.is_empty():
		_cleanup_temporary_file(first_temporary)
		return false
	var save_error: Error = image.save_png(first_temporary)
	if save_error != OK:
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		_fail("could not save temporary first frame error=%d" % save_error)
		return false
	if not _validate_temporary_file(first_temporary):
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		return false
	var copy_error: Error = DirAccess.copy_absolute(first_temporary, stable_temporary)
	if copy_error != OK or not _validate_temporary_file(stable_temporary):
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		_fail("could not prepare stable temporary frame error=%d" % copy_error)
		return false
	var frame_bytes: PackedByteArray = FileAccess.get_file_as_bytes(first_temporary)
	var stable_temporary_bytes: PackedByteArray = FileAccess.get_file_as_bytes(stable_temporary)
	if frame_bytes.is_empty() or frame_bytes != stable_temporary_bytes:
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		_fail("temporary publication frames are empty or differ")
		return false

	# Recheck both fixed leaves immediately before either rename. This is still
	# defense-in-depth inside the documented trusted-workspace boundary.
	if not _validate_publication_leaf(first_frame_path) or not _validate_publication_leaf(stable_path):
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		return false
	var first_rename_error: Error = _rename_publication_leaf(first_temporary, first_frame_path)
	if first_rename_error != OK:
		_cleanup_temporary_file(first_temporary)
		_cleanup_temporary_file(stable_temporary)
		_fail("could not atomically publish first frame error=%d" % first_rename_error)
		return false
	var stable_rename_error: Error = _rename_publication_leaf(stable_temporary, stable_path)
	if stable_rename_error != OK:
		_cleanup_temporary_file(stable_temporary)
		var first_restored: bool = _restore_publication_leaf(first_frame_path, first_snapshot)
		var rollback_status: String = "prior leaves restored" if first_restored else "rollback failed restoring first frame leaf"
		_fail("could not atomically publish stable frame error=%d; %s" % [stable_rename_error, rollback_status])
		return false
	if not _verify_published_leaf(first_frame_path, "first frame") or not _verify_published_leaf(stable_path, "stable frame"):
		var first_restored: bool = _restore_publication_leaf(first_frame_path, first_snapshot)
		var stable_restored: bool = _restore_publication_leaf(stable_path, stable_snapshot)
		if not first_restored or not stable_restored:
			_fail("published leaf verification failed; rollback failed restoring prior leaves")
		return false
	var published_stable_bytes: PackedByteArray = FileAccess.get_file_as_bytes(stable_path)
	if published_stable_bytes != frame_bytes:
		var first_restored: bool = _restore_publication_leaf(first_frame_path, first_snapshot)
		var stable_restored: bool = _restore_publication_leaf(stable_path, stable_snapshot)
		var rollback_status: String = "prior leaves restored" if first_restored and stable_restored else "rollback failed restoring prior leaves"
		_fail("stable frame differs from first frame; %s" % rollback_status)
		return false
	return true


func _rename_publication_leaf(source_path: String, destination_path: String) -> Error:
	return DirAccess.rename_absolute(source_path, destination_path)


func _snapshot_publication_leaf(path: String) -> Dictionary:
	var entry_kind: String = _path_entry_kind(path)
	if entry_kind == "missing":
		return {"exists": false}
	if entry_kind != "regular":
		_fail("cannot snapshot non-regular publication leaf: %s" % path)
		return {"error": true}
	return {"exists": true, "bytes": FileAccess.get_file_as_bytes(path)}


func _restore_publication_leaf(path: String, snapshot: Dictionary) -> bool:
	var entry_kind: String = _path_entry_kind(path)
	if not bool(snapshot.get("exists", false)):
		if entry_kind == "missing":
			return true
		if entry_kind != "regular":
			return false
		var remove_error: Error = DirAccess.remove_absolute(path)
		return remove_error == OK and _path_entry_kind(path) == "missing"
	if not snapshot.has("bytes"):
		return false
	var temporary_path: String = _allocate_temporary_path(path.get_file())
	if temporary_path.is_empty():
		return false
	var handle: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if handle == null:
		_cleanup_temporary_file(temporary_path)
		return false
	handle.store_buffer(snapshot["bytes"])
	handle = null
	if not _validate_restoration_temporary_file(temporary_path):
		_cleanup_temporary_file(temporary_path)
		return false
	var rename_error: Error = _rename_publication_leaf(temporary_path, path)
	if rename_error != OK:
		_cleanup_temporary_file(temporary_path)
		return false
	if _path_entry_kind(path) != "regular":
		return false
	return FileAccess.get_file_as_bytes(path) == snapshot["bytes"]


func _validate_publication_leaf(leaf_path: String) -> bool:
	var output_dir: String = _publication_output_dir()
	if output_dir.is_empty():
		return false
	var normalized_leaf: String = leaf_path.simplify_path()
	var leaf_name: String = normalized_leaf.get_file()
	if leaf_name != FIRST_FRAME_NAME and leaf_name != STABLE_OUTPUT_NAME:
		_fail("unexpected fixed publication leaf %s" % leaf_name)
		return false
	var expected_leaf: String = output_dir.path_join(leaf_name).simplify_path()
	if normalized_leaf != expected_leaf or not _is_path_within(normalized_leaf, output_dir):
		_fail("fixed publication leaf is not the exact output directory leaf")
		return false
	var entry_kind: String = _path_entry_kind(normalized_leaf)
	if entry_kind == "error":
		return false
	if entry_kind == "missing":
		return true
	if entry_kind == "symlink":
		_fail("fixed publication leaf is a symlink")
		return false
	if entry_kind == "directory":
		_fail("fixed publication leaf is a directory")
		return false
	if entry_kind != "regular":
		_fail("fixed publication leaf is not a regular file")
		return false
	var canonical_leaf: String = _canonicalize_path(normalized_leaf)
	if canonical_leaf.is_empty():
		return false
	if canonical_leaf != expected_leaf:
		_fail("fixed publication leaf has an unexpected physical target")
		return false
	return true


func _validate_temporary_file(path: String) -> bool:
	if not _validate_temporary_path(path):
		return false
	if FileAccess.get_file_as_bytes(path).is_empty():
		_fail("temporary publication file is empty")
		return false
	return true


func _validate_restoration_temporary_file(path: String) -> bool:
	return _validate_temporary_path(path)


func _validate_temporary_path(path: String) -> bool:
	var output_dir: String = _publication_output_dir()
	if output_dir.is_empty():
		return false
	var normalized_path: String = path.simplify_path()
	if not _is_path_within(normalized_path, output_dir) or not normalized_path.get_file().begins_with(TEMPORARY_FILE_PREFIX):
		_fail("temporary publication file is outside approved output directory")
		return false
	if _path_entry_kind(normalized_path) != "regular":
		_fail("temporary publication file is not a regular non-symlink file")
		return false
	var canonical_path: String = _canonicalize_path(normalized_path)
	if canonical_path.is_empty() or canonical_path != normalized_path:
		_fail("temporary publication file has an unexpected physical target")
		return false
	return true


func _verify_published_leaf(path: String, description: String) -> bool:
	if not _validate_publication_leaf(path):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_fail("%s is empty" % description)
		return false
	return true


func _publication_output_dir() -> String:
	if _output_dir_global.is_empty():
		_fail("output directory is unavailable")
		return ""
	var resolved_output_dir: String = _resolve_output_dir(_output_dir_global)
	if resolved_output_dir.is_empty():
		return ""
	if resolved_output_dir != _output_dir_global.simplify_path():
		_fail("output directory changed physical location")
		return ""
	return resolved_output_dir


func _allocate_temporary_path(published_name: String) -> String:
	var output_dir: String = _publication_output_dir()
	if output_dir.is_empty():
		return ""
	if not FileAccess.file_exists(MKTEMP_COMMAND):
		_fail("temporary file command is unavailable")
		return ""
	_temporary_sequence += 1
	var template_name: String = "%s.%s.%d.XXXXXX" % [TEMPORARY_FILE_PREFIX, published_name, _temporary_sequence]
	var template_path: String = output_dir.path_join(template_name).simplify_path()
	if not _is_path_within(template_path, output_dir):
		_fail("temporary publication file escaped output directory")
		return ""
	var command_output: Array[String] = []
	var command_status: int = OS.execute(MKTEMP_COMMAND, PackedStringArray(["-q", template_path]), command_output, true, false)
	if command_status != OK or command_output.size() != 1:
		_fail("could not allocate unique temporary publication file")
		return ""
	var temporary_path: String = command_output[0].strip_edges().simplify_path()
	if not _is_path_within(temporary_path, output_dir) or not temporary_path.get_file().begins_with(TEMPORARY_FILE_PREFIX):
		_cleanup_temporary_file(temporary_path)
		_fail("temporary publication file escaped output directory")
		return ""
	if _path_entry_kind(temporary_path) != "regular":
		_cleanup_temporary_file(temporary_path)
		_fail("temporary publication file was not atomically reserved")
		return ""
	var canonical_path: String = _canonicalize_path(temporary_path)
	if canonical_path.is_empty() or canonical_path != temporary_path:
		_cleanup_temporary_file(temporary_path)
		_fail("temporary publication file has an unexpected physical target")
		return ""
	return temporary_path


func _path_entry_kind(path: String) -> String:
	var symlink_status: int = _native_test_flag("-L", path)
	if symlink_status < 0:
		return "error"
	if symlink_status == OK:
		return "symlink"
	var exists_status: int = _native_test_flag("-e", path)
	if exists_status < 0:
		return "error"
	if exists_status != OK:
		return "missing"
	var directory_status: int = _native_test_flag("-d", path)
	if directory_status < 0:
		return "error"
	if directory_status == OK:
		return "directory"
	var regular_status: int = _native_test_flag("-f", path)
	if regular_status < 0:
		return "error"
	if regular_status == OK:
		return "regular"
	return "non_regular"


func _native_test_flag(flag: String, path: String) -> int:
	if not FileAccess.file_exists(TEST_COMMAND):
		_fail("native path test command is unavailable")
		return -1
	var command_output: Array[String] = []
	var command_status: int = OS.execute(TEST_COMMAND, PackedStringArray([flag, path]), command_output, true, false)
	if command_status != OK and command_status != 1:
		_fail("native path test failed flag=%s error=%d" % [flag, command_status])
		return -1
	return command_status


func _cleanup_temporary_file(path: String) -> void:
	if path.is_empty():
		return
	var remove_error: Error = DirAccess.remove_absolute(path)
	if remove_error != OK and _path_entry_kind(path) != "missing":
		_fail("could not remove temporary publication file error=%d" % remove_error)


func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_last_failure_reason = reason
	print("FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE FAIL reason=%s" % reason)
	if is_inside_tree():
		get_tree().quit(1)
