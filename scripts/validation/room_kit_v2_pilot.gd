extends Node3D
## Staged diagnostic room only. This is not a generated or boarded ship.
## Loads the actual selected GLBs; never fabricates a missing candidate.
const STRUCTURAL_IDS := ["floor_1x1", "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1"]
const PROP_IDS := ["fabrication_station_derelict_v1", "coolant_pump_skid_derelict_v1", "suit_service_stand_derelict_v1"]
const ASSET_IDS := STRUCTURAL_IDS + PROP_IDS
var auto_capture: bool = true
var _owned: Array[Node3D] = []
var _paths: Dictionary = {}
var _baseline: bool = false
var _output: String = "res://artifacts/room_kit_v2/pilot-room"

func _ready() -> void:
	var camera: Camera3D = $Camera3D
	camera.look_at_from_position(Vector3(16,18,16), Vector3.ZERO, Vector3.UP)
	if auto_capture:
		call_deferred("_capture")

func _load_visual(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 32 or bytes.slice(0,4).get_string_from_ascii() != "glTF":
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return document.generate_scene(state) as Node3D

func build_preview(paths: Dictionary, baseline: bool = false) -> bool:
	# Preflight every selected model before attaching anything to the scene.
	var loaded: Dictionary = {}
	var required: Array = STRUCTURAL_IDS + ([PROP_IDS[0]] if baseline else PROP_IDS)
	for asset_id in required:
		var model := _load_visual(str(paths.get(asset_id,"")))
		if model == null:
			for previous in loaded.values():
				previous.free()
			print("ROOM_KIT_PILOT_INPUT_REJECTED "+str(asset_id))
			return false
		loaded[asset_id] = model
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
	_paths = paths.duplicate()
	_baseline = baseline
	# Nine 4m cells with an intentionally roofless diagnostic view.
	for x in [-4.0,0.0,4.0]:
		for z in [-4.0,0.0,4.0]:
			_instance(loaded, "floor_1x1", Vector3(x,0,z))
	for x in [-4.0,4.0]:
		_instance(loaded, "wall_straight_1x1", Vector3(x,0,-6))
	for z in [-4.0,0.0]:
		_instance(loaded, "wall_straight_1x1", Vector3(-6,0,z), PI/2.0)
	_instance(loaded, "doorway_frame_open_1x1", Vector3(0,0,-6))
	_instance(loaded, "pillar_support_1x1", Vector3(-6,0,4))
	var floor_top: float = _max_visual_y(loaded["floor_1x1"],Transform3D.IDENTITY)
	_instance(loaded, "fabrication_station_derelict_v1", Vector3(-3,floor_top,-3))
	if not baseline:
		_instance(loaded, "coolant_pump_skid_derelict_v1", Vector3(3,floor_top,-3))
		_instance(loaded, "suit_service_stand_derelict_v1", Vector3(-3,floor_top,3), PI/2.0)
	for original in loaded.values():
		original.free()
	return true

func _instance(loaded: Dictionary, asset_id: String, pose: Vector3, yaw: float = 0.0) -> void:
	var node: Node3D = loaded[asset_id].duplicate()
	node.name = "%s_%d" % [asset_id,_owned.size()]
	node.position = pose
	node.rotation.y = yaw
	node.set_meta("pilot_asset_id",asset_id)
	$Models.add_child(node)
	_owned.append(node)

func _max_visual_y(node: Node3D, parent_transform: Transform3D) -> float:
	var combined: Transform3D = parent_transform * node.transform
	var height: float = -INF
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.get_aabb()
		for corner in range(8):
			height = maxf(height,(combined * box.get_endpoint(corner)).y)
	for child in node.get_children():
		if child is Node3D:
			height = maxf(height,_max_visual_y(child,combined))
	return height

func selected_paths(stage: String, baseline: bool, baseline_shell: bool) -> Dictionary:
	var paths: Dictionary = {}
	for asset_id in STRUCTURAL_IDS:
		var source_root := "res://assets/imported/structural/ship_structural_v0" if baseline or baseline_shell else stage+"/structural"
		paths[asset_id] = source_root+"/%s/%s.glb" % [asset_id,asset_id]
	for asset_id in PROP_IDS:
		paths[asset_id] = ("res://assets/imported/props/dressing" if baseline else stage+"/props")+"/"+asset_id+".glb"
	return paths

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("real viewport capture requires non-headless Godot")
		return
	var args := OS.get_cmdline_user_args()
	var stage := "res://assets/_staging/room_kit_v2"
	_baseline = "--baseline" in args
	var baseline_shell: bool = "--baseline-shell" in args
	for i in range(args.size()-1):
		if args[i] == "--output-dir":
			_output = args[i+1]
		if args[i] == "--stage-root":
			stage = args[i+1]
	var paths: Dictionary = selected_paths(stage,_baseline,baseline_shell)
	if not build_preview(paths,_baseline):
		_fail("selected source missing; no fallback allowed")
		return
	var output_absolute := ProjectSettings.globalize_path(_output)
	if DirAccess.make_dir_recursive_absolute(output_absolute) != OK:
		_fail("cannot create output directory")
		return
	var window := get_window()
	window.content_scale_size = Vector2i(1600,900)
	window.size = Vector2i(1600,900)
	var camera: Camera3D = $Camera3D
	var cases: Array[Dictionary] = [
		{"name":"pilot-room-iso", "position":Vector3(16,18,16),"target":Vector3.ZERO,"size":22.0,"resolution":Vector2i(1600,900)},
		{"name":"pilot-room-top", "position":Vector3(0,30,0.01),"target":Vector3.ZERO,"size":22.0,"resolution":Vector2i(1600,900)},
		{"name":"pilot-station-detail", "position":Vector3(1,3,1),"target":Vector3(-3,0.8,-3),"size":5.0,"resolution":Vector2i(1600,900)},
		{"name":"pilot-room-iso-720", "position":Vector3(16,18,16),"target":Vector3.ZERO,"size":22.0,"resolution":Vector2i(1280,720)},
	]
	var captures: Array[Dictionary] = []
	for spec in cases:
		window.content_scale_size = spec["resolution"]
		window.size = spec["resolution"]
		camera.size = float(spec["size"])
		camera.look_at_from_position(spec["position"],spec["target"],Vector3.UP)
		for frame in range(8):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != spec["resolution"]:
			_fail("empty or wrong-sized real viewport: "+str(spec["name"]))
			return
		var destination := output_absolute.path_join(str(spec["name"])+".png")
		if image.save_png(destination) != OK:
			_fail("PNG publication failed")
			return
		captures.append({"image":destination,"sha256":FileAccess.get_sha256(destination),"width":image.get_width(),"height":image.get_height(),"camera_transform":str(camera.transform),"projection":"orthographic","camera_size":camera.size})
	var inputs: Dictionary = {}
	for asset_id in (STRUCTURAL_IDS + ([PROP_IDS[0]] if _baseline else PROP_IDS)):
		inputs[asset_id] = {"path":_paths[asset_id],"sha256":FileAccess.get_sha256(_paths[asset_id])}
	var receipt := FileAccess.open(output_absolute.path_join("capture.json"),FileAccess.WRITE)
	if receipt == null:
		_fail("receipt publication failed")
		return
	receipt.store_string(JSON.stringify({"kind":"manual_diagnostic_pilot_not_procgen_proof","baseline":_baseline,"unchanged_baseline_shell":_baseline or baseline_shell,"structural_candidate_acceptance":false,"inputs":inputs,"instances":_owned.size(),"captures":captures,"runtime_promotion":false},"  ")+"\n")
	receipt.close()
	print("ROOM_KIT_PILOT_CAPTURE_PASS captures=%d baseline=%s output=%s" % [captures.size(),str(_baseline),output_absolute])
	get_tree().quit(0)

func _fail(reason: String) -> void:
	print("ROOM_KIT_PILOT_CAPTURE_FAIL "+reason)
	get_tree().quit(1)
