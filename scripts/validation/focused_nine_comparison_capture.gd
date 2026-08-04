extends Node3D

const CAMERA_SIZE := 18.0
const CAPTURE_WIDTH: int = 1600
const CAPTURE_HEIGHT: int = 900
const STAGED_ROOT := "res://assets/_staging/focused_nine/"
const CURRENT_RUNTIME_ROOT := "res://assets/imported/structural/ship_structural_v0/"
const FIRST_FRAME_NAME := "focused-nine-comparison00000000.png"
const STABLE_OUTPUT_NAME := "focused-nine-comparison.png"
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
	_output_dir_global = _resolve_output_dir(str(parsed["output_dir"]))
	if _output_dir_global.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(_output_dir_global) != OK:
		_fail("could not create output directory")
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

	if not _populate_comparison(baseline, improved):
		return
	call_deferred("_capture_after_frames")


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {
		"output_dir": "",
		"baseline_label": "Baseline",
		"improved_label": "Improved",
	}
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if token == "--":
			index += 1
			continue
		if token == "--output-dir" or token == "--baseline-label" or token == "--improved-label":
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
	if candidate != project_root and not candidate.begins_with(project_root + "/"):
		_fail("output directory must be inside project root")
		return ""
	return candidate


func _populate_comparison(baseline: Node3D, improved: Node3D) -> bool:
	for index in BASELINE_GLB_PATHS.size():
		var baseline_visual: Node3D = _load_glb(BASELINE_GLB_PATHS[index], false)
		if baseline_visual == null:
			return false
		baseline_visual.name = "RuntimeGLB_%02d" % index
		baseline_visual.position = BASELINE_LAYOUT[index]
		baseline.add_child(baseline_visual)

	var stand_in_supply: Node3D = ReadabilityPropFactoryScript.create_objective_prop(1, "recover_supplies")
	stand_in_supply.position = Vector3(-3.0, 0.0, 3.0)
	baseline.add_child(stand_in_supply)
	var stand_in_breaker: Node3D = ReadabilityPropFactoryScript.create_objective_prop(2, "restore_systems")
	stand_in_breaker.position = Vector3(3.0, 0.0, 3.0)
	baseline.add_child(stand_in_breaker)
	var stand_in_blocked: Node3D = ReadabilityPropFactoryScript.create_blocked_biomatter()
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

	var first_frame_path: String = _output_dir_global.path_join(FIRST_FRAME_NAME)
	var save_error: Error = image.save_png(first_frame_path)
	if save_error != OK:
		_fail("could not save first frame error=%d" % save_error)
		return
	var frame_bytes: PackedByteArray = FileAccess.get_file_as_bytes(first_frame_path)
	if frame_bytes.is_empty():
		_fail("first frame is empty")
		return

	var stable_path: String = _output_dir_global.path_join(STABLE_OUTPUT_NAME)
	var copy_error: Error = DirAccess.copy_absolute(first_frame_path, stable_path)
	if copy_error != OK:
		_fail("could not copy stable comparison frame error=%d" % copy_error)
		return
	var stable_bytes: PackedByteArray = FileAccess.get_file_as_bytes(stable_path)
	if stable_bytes.is_empty():
		_fail("stable comparison frame is empty")
		return
	print("FOCUSED_NINE_COMPARISON_CAPTURE PASS output=%s" % stable_path)
	_finished = true
	get_tree().quit(0)


func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	print("FOCUSED_NINE_COMPARISON_CAPTURE FAIL reason=%s" % reason)
	get_tree().quit(1)
