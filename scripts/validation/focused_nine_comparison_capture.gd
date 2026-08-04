extends Node3D

# Capture CLI:
#   godot --path . --editor --scene res://scenes/validation/focused_nine_comparison_harness.tscn -- \
#     --output-dir DIR [--baseline-label LABEL] [--improved-label LABEL]
# ``--output-dir`` is required; labels default to ``Baseline`` and ``Improved``.
#
# Trusted-workspace boundary for the full capture run: same-user concurrent
# filesystem mutation/rebinding of project/output paths is outside this capture
# boundary. The checks below are defense-in-depth only; Godot filesystem APIs
# cannot pin the paths for the complete capture/publication window.
const TRUST_BOUNDARY_DOCUMENTATION := "same-user concurrent filesystem mutation/rebinding of project/output paths is outside the capture's trusted-workspace boundary for its full run; staging/root path checks and leaf constraints remain defense-in-depth but cannot pin Godot filesystem operations."

const CAMERA_SIZE := 18.0
const CAPTURE_WIDTH: int = 1600
const CAPTURE_HEIGHT: int = 900
const STAGED_ROOT := "res://assets/_staging/focused_nine/"
const CURRENT_RUNTIME_ROOT := "res://assets/imported/structural/ship_structural_v0/"
const APPROVED_OUTPUT_ROOT := "res://artifacts/validation-previews/focused-nine"
const REALPATH_COMMAND := "/bin/realpath"
const TEST_COMMAND := "/bin/test"
const MKTEMP_COMMAND := "/usr/bin/mktemp"
const FIRST_FRAME_NAME := "focused-nine-comparison00000000.png"
const STABLE_OUTPUT_NAME := "focused-nine-comparison.png"
const TEMPORARY_FILE_PREFIX := ".focused-nine-comparison"
const ReadabilityPropFactoryScript: GDScript = preload("res://scripts/procgen/readability_prop_factory.gd")

const BASELINE_GLB_PATHS: Array[String] = [
	"res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb",
	"res://assets/imported/structural/ship_structural_v0/wall_straight_1x1/wall_straight_1x1.glb",
	"res://assets/imported/structural/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1.glb",
	"res://assets/imported/structural/ship_structural_v0/pillar_support_1x1/pillar_support_1x1.glb",
	"res://assets/imported/structural/ship_structural_v0/ramp_up_1x2/ramp_up_1x2.glb",
	"res://assets/imported/structural/ship_structural_v0/ceiling_cap_1x1/ceiling_cap_1x1.glb",
]

const IMPROVED_GLB_PATHS: Array[String] = [
	"res://assets/_staging/focused_nine/structural/floor_1x1/floor_1x1.glb",
	"res://assets/_staging/focused_nine/structural/wall_straight_1x1/wall_straight_1x1.glb",
	"res://assets/_staging/focused_nine/structural/doorway_frame_open_1x1/doorway_frame_open_1x1.glb",
	"res://assets/_staging/focused_nine/structural/pillar_support_1x1/pillar_support_1x1.glb",
	"res://assets/_staging/focused_nine/structural/ramp_up_1x2/ramp_up_1x2.glb",
	"res://assets/_staging/focused_nine/structural/ceiling_cap_1x1/ceiling_cap_1x1.glb",
	"res://assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb",
	"res://assets/_staging/focused_nine/props/hull_breach_seal_point.glb",
	"res://assets/_staging/focused_nine/props/fire_suppression_station.glb",
]

const BASELINE_LAYOUT: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-2.0, 0.0, -2.0),
	Vector3(2.0, 0.0, -2.0),
	Vector3(-2.0, 0.0, 2.0),
	Vector3(2.0, 0.0, 2.0),
	Vector3(0.0, 0.0, 3.5),
]

const IMPROVED_LAYOUT: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-2.0, 0.0, -2.0),
	Vector3(2.0, 0.0, -2.0),
	Vector3(-2.0, 0.0, 2.0),
	Vector3(2.0, 0.0, 2.0),
	Vector3(0.0, 0.0, 3.5),
	Vector3(0.0, 0.0, -3.5),
	Vector3(-3.0, 0.0, 2.5),
	Vector3(3.0, 0.0, 2.5),
]

var _finished: bool = false
var _output_dir_global: String = ""
var _baseline_label: String = "Baseline"
var _improved_label: String = "Improved"
var _temporary_sequence: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("non_headless_capture_required")
		return

	var parsed: Dictionary = _parse_user_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	_baseline_label = str(parsed["baseline_label"])
	_improved_label = str(parsed["improved_label"])
	_output_dir_global = _prepare_output_dir(str(parsed["output_dir"]))
	if _output_dir_global.is_empty():
		return
	DisplayServer.window_set_size(Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT))
	get_viewport().size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)

	var camera: Camera3D = get_node_or_null("ValidationCamera") as Camera3D
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, CAMERA_SIZE):
		_fail("camera contract mismatch")
		return
	var baseline: Node3D = get_node_or_null("Baseline") as Node3D
	var improved: Node3D = get_node_or_null("Improved") as Node3D
	if baseline == null or improved == null:
		_fail("comparison roots are missing")
		return
	baseline.set_meta("comparison_label", _baseline_label)
	improved.set_meta("comparison_label", _improved_label)

	# full real GLTF render/copy/PASS marker acceptance is intentionally deferred to Task 8 after all nine GLBs are staged.
	if not _populate_comparison(baseline, improved):
		return
	call_deferred("_capture_after_frames")


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {
		"output_dir": "",
		"baseline_label": "Baseline",
		"improved_label": "Improved",
	}
	var seen_options: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if token == "--":
			return {"error": "unexpected argument --"}
		if token == "--output-dir" or token == "--baseline-label" or token == "--improved-label":
			if seen_options.has(token):
				return {"error": "duplicate option %s" % token}
			seen_options[token] = true
			if index + 1 >= args.size() or str(args[index + 1]).begins_with("--"):
				return {"error": "missing value for %s" % token}
			var value: String = str(args[index + 1]).strip_edges()
			if value.is_empty():
				return {"error": "empty value for %s" % token}
			if token == "--output-dir":
				result["output_dir"] = value
			elif token == "--baseline-label":
				result["baseline_label"] = value
			else:
				result["improved_label"] = value
			index += 2
			continue
		return {"error": "unknown argument %s" % token}
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
	if project_physical.is_empty():
		return ""
	var approved_physical: String = _canonicalize_path(approved_root)
	if approved_physical.is_empty():
		return ""
	if not _is_path_within(approved_physical, project_physical):
		_fail("approved focused-nine subtree is outside physical project root")
		return ""

	var candidate_physical: String = _canonicalize_path(candidate)
	if candidate_physical.is_empty():
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
	# Re-canonicalize after creation so a symlink introduced in the output chain cannot be accepted.
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
	for component: String in missing_components:
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
	var command_status: int = OS.execute(
		REALPATH_COMMAND,
		PackedStringArray([path]),
		command_output,
		true,
		true,
	)
	if command_status != OK or command_output.size() != 1:
		_fail("could not canonicalize path with realpath")
		return ""
	var canonical_path: String = command_output[0].strip_edges()
	if canonical_path.is_empty() or not canonical_path.is_absolute_path():
		_fail("realpath returned an invalid canonical path")
		return ""
	return canonical_path.simplify_path()


func _populate_comparison(baseline: Node3D, improved: Node3D) -> bool:
	for index in BASELINE_GLB_PATHS.size():
		var baseline_visual: Node3D = _load_glb(BASELINE_GLB_PATHS[index], false)
		if baseline_visual == null:
			return false
		baseline_visual.name = "RuntimeGLB_%02d" % index
		baseline_visual.position = BASELINE_LAYOUT[index]
		baseline.add_child(baseline_visual)

	var stand_in_supply: Node3D = ReadabilityPropFactoryScript.create_objective_prop(1, "recover_supplies")
	_disable_local_lights(stand_in_supply)
	stand_in_supply.position = Vector3(-3.0, 0.0, 3.0)
	baseline.add_child(stand_in_supply)
	var stand_in_breaker: Node3D = ReadabilityPropFactoryScript.create_objective_prop(2, "restore_systems")
	_disable_local_lights(stand_in_breaker)
	stand_in_breaker.position = Vector3(3.0, 0.0, 3.0)
	baseline.add_child(stand_in_breaker)
	var stand_in_blocked: Node3D = ReadabilityPropFactoryScript.create_blocked_biomatter()
	_disable_local_lights(stand_in_blocked)
	stand_in_blocked.position = Vector3(0.0, 0.0, -3.5)
	baseline.add_child(stand_in_blocked)

	for index in IMPROVED_GLB_PATHS.size():
		var improved_visual: Node3D = _load_glb(IMPROVED_GLB_PATHS[index], true)
		if improved_visual == null:
			return false
		improved_visual.name = "StagedGLB_%02d" % index
		improved_visual.position = IMPROVED_LAYOUT[index]
		improved.add_child(improved_visual)
	return true


func _disable_local_lights(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Light3D:
			child.visible = false
		_disable_local_lights(child)


func _load_glb(path: String, staged: bool) -> Node3D:
	if staged and not path.begins_with(STAGED_ROOT):
		_fail("improved asset path is outside focused-nine staging: %s" % path)
		return null
	if not staged and not path.begins_with(CURRENT_RUNTIME_ROOT):
		_fail("baseline asset path is outside current runtime assets: %s" % path)
		return null
	if not FileAccess.file_exists(path):
		if staged:
			_fail("missing staged GLB: %s" % path)
		else:
			_fail("missing runtime GLB: %s" % path)
		return null

	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var append_error: Error = document.append_from_file(ProjectSettings.globalize_path(path), state)
	if append_error != OK:
		_fail("could not load GLB: %s error=%d" % [path, append_error])
		return null
	var generated: Node = document.generate_scene(state)
	if generated == null:
		_fail("could not generate GLB scene: %s" % path)
		return null
	var visual: Node3D = generated as Node3D
	if visual == null:
		generated.free()
		_fail("GLB scene root is not Node3D: %s" % path)
		return null
	return visual


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
	var root_texture: ViewportTexture = get_viewport().get_root().get_texture()
	if root_texture == null:
		_fail("viewport texture is unavailable")
		return
	var image: Image = get_viewport().get_root().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport image is empty")
		return
	if image.get_width() != CAPTURE_WIDTH or image.get_height() != CAPTURE_HEIGHT:
		_fail("capture resolution must be 1600x900")
		return

	if not _publish_capture_files(image):
		return
	print("FOCUSED_NINE_COMPARISON_CAPTURE PASS output=%s" % _output_dir_global.path_join(STABLE_OUTPUT_NAME))
	_finished = true
	get_tree().quit(0)


func _publish_capture_files(image: Image) -> bool:
	if _output_dir_global.is_empty():
		_fail("output directory is unavailable for publication")
		return false
	var first_frame_path: String = _output_dir_global.path_join(FIRST_FRAME_NAME)
	var stable_path: String = _output_dir_global.path_join(STABLE_OUTPUT_NAME)
	# Defense-in-depth preflight of both fixed leaves; it does not cover a same-user
	# filesystem rebind during a later Godot operation.
	var first_leaf_safe: bool = _validate_publication_leaf(first_frame_path)
	var stable_leaf_safe: bool = _validate_publication_leaf(stable_path)
	if not first_leaf_safe or not stable_leaf_safe:
		return false
	if not _publish_image_to_leaf(image, first_frame_path):
		return false
	return _copy_stable_frame(first_frame_path, stable_path)


func _publish_image_to_leaf(image: Image, leaf_path: String) -> bool:
	var temporary_path: String = _allocate_temporary_path(leaf_path.get_file())
	if temporary_path.is_empty():
		return false
	var save_error: Error = image.save_png(temporary_path)
	if save_error != OK:
		_cleanup_temporary_file(temporary_path)
		_fail("could not save temporary first frame error=%d" % save_error)
		return false
	if not _validate_temporary_file(temporary_path):
		_cleanup_temporary_file(temporary_path)
		return false
	# Defense-in-depth only: recheck immediately before rename. POSIX rename replaces
	# a destination symlink entry rather than following it, but Godot's path-based
	# operations still cannot close same-user rebind races outside the boundary.
	if not _validate_publication_leaf(leaf_path):
		_cleanup_temporary_file(temporary_path)
		return false
	var rename_error: Error = DirAccess.rename_absolute(temporary_path, leaf_path)
	if rename_error != OK:
		_cleanup_temporary_file(temporary_path)
		_fail("could not atomically publish first frame error=%d" % rename_error)
		return false
	return _verify_published_leaf(leaf_path, "first frame")


func _copy_stable_frame(first_frame_path: String, stable_path: String) -> bool:
	if not _validate_physical_output_file(first_frame_path, "first frame"):
		return false
	var frame_bytes: PackedByteArray = FileAccess.get_file_as_bytes(first_frame_path)
	if frame_bytes.is_empty():
		_fail("first frame is empty before stable publication")
		return false
	var temporary_path: String = _allocate_temporary_path(stable_path.get_file())
	if temporary_path.is_empty():
		return false
	var copy_error: Error = DirAccess.copy_absolute(first_frame_path, temporary_path)
	if copy_error != OK:
		_cleanup_temporary_file(temporary_path)
		_fail("could not copy stable comparison frame to temporary file error=%d" % copy_error)
		return false
	if not _validate_temporary_file(temporary_path):
		_cleanup_temporary_file(temporary_path)
		return false
	# Defense-in-depth only: recheck the stable leaf immediately before rename;
	# this remains within the same full-run trusted-workspace boundary.
	if not _validate_publication_leaf(stable_path):
		_cleanup_temporary_file(temporary_path)
		return false
	var rename_error: Error = DirAccess.rename_absolute(temporary_path, stable_path)
	if rename_error != OK:
		_cleanup_temporary_file(temporary_path)
		_fail("could not atomically publish stable comparison frame error=%d" % rename_error)
		return false
	if not _verify_published_leaf(stable_path, "stable comparison frame"):
		return false
	var stable_bytes: PackedByteArray = FileAccess.get_file_as_bytes(stable_path)
	if stable_bytes != frame_bytes:
		_fail("stable comparison frame differs from first frame")
		return false
	return true


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


func _validate_physical_output_file(path: String, description: String) -> bool:
	var output_dir: String = _publication_output_dir()
	if output_dir.is_empty():
		return false
	var normalized_path: String = path.simplify_path()
	if not _is_path_within(normalized_path, output_dir):
		_fail("%s is outside canonical output directory" % description)
		return false
	var entry_kind: String = _path_entry_kind(normalized_path)
	if entry_kind == "error":
		return false
	if entry_kind == "symlink":
		_fail("%s is a symlink" % description)
		return false
	if entry_kind != "regular":
		_fail("%s is not a regular file" % description)
		return false
	var canonical_path: String = _canonicalize_path(normalized_path)
	if canonical_path.is_empty():
		return false
	if canonical_path != normalized_path:
		_fail("%s has an unexpected physical target" % description)
		return false
	return true


func _validate_temporary_file(path: String) -> bool:
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
	if canonical_path.is_empty():
		return false
	if canonical_path != normalized_path:
		_fail("temporary publication file has an unexpected physical target")
		return false
	if FileAccess.get_file_as_bytes(normalized_path).is_empty():
		_fail("temporary publication file is empty")
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
	var command_status: int = OS.execute(
		MKTEMP_COMMAND,
		PackedStringArray(["-q", template_path]),
		command_output,
		true,
		false,
	)
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
	var command_status: int = OS.execute(
		TEST_COMMAND,
		PackedStringArray([flag, path]),
		command_output,
		true,
		false,
	)
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
	print("FOCUSED_NINE_COMPARISON_CAPTURE FAIL reason=%s" % reason)
	if is_inside_tree():
		get_tree().quit(1)
