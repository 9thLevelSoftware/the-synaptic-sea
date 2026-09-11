extends SceneTree
## Renders any layout + gameplay slice with the production GeneratedShipLoader and the locked-iso camera (ceilings
## hidden, like the Unity ScreenshotRunner) for side-by-side comparison with the Unity port. Needs a window:
##   Godot_v4.7.1-stable_win64.exe --path . --script res://scripts/validation/parity_fixtures/capture_loader_screenshot.gd -- \
##     --layout <res:// or absolute> --slice <res:// or absolute> --stem <name> --out <dir> [--away]

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const KIT := "res://data/kits/ship_structural_v0.json"

var _frames := 0
var _camera: Camera3D
var _center := Vector3.ZERO
var _overview_size := 22.0
var _out_dir := ""
var _stem := ""
var _loader: Node3D


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = _arg(args, "--out", "user://")
	_stem = _arg(args, "--stem", "layout")
	var layout := _arg(args, "--layout", "res://data/procgen/golden/coherent_ship_001/layout.json")
	var slice := _arg(args, "--slice", layout.get_base_dir().path_join("gameplay_slice.json"))
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var world := Node3D.new()
	get_root().add_child(world)
	var loader: Node3D = LoaderScript.new()
	world.add_child(loader)
	if not loader.load_from_paths(layout, KIT, slice, args.has("--away")):
		push_error("LOADER SCREENSHOT FAIL load")
		quit(1)
		return
	_loader = loader
	process_frame.connect(_on_frame)


func _setup_camera() -> void:
	var aabb := AABB()
	var first := true
	for node in _loader.find_children("*", "Node3D", true, false):
		var n3 := node as Node3D
		if n3.name.begins_with("Ceiling_"):
			n3.visible = false
	for node in _loader.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	_center = Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
	_overview_size = maxf(aabb.size.x, aabb.size.z) * 1.15
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 22.0
	_loader.get_parent().add_child(_camera)
	_camera.global_position = _center + Vector3(16.0, 18.0, 16.0)
	_camera.look_at(_center, Vector3.UP)
	_camera.current = true


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		_setup_camera()
	elif _frames == 8:
		_save("%s_godot_iso_gameplay.png" % _stem)
		_camera.size = _overview_size
	elif _frames == 14:
		_save("%s_godot_iso_overview.png" % _stem)
		print("LOADER SCREENSHOT PASS out=%s" % _out_dir)
		quit(0)


func _save(file_name: String) -> void:
	var image := get_root().get_texture().get_image()
	image.save_png(_out_dir.path_join(file_name))
