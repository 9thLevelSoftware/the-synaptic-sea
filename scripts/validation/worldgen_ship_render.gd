extends SceneTree
## Renders ships from worldgen v2 through GeneratedShipLoader with
## proper 3D isometric camera + ceiling fade. Captures viewport PNGs.

const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

var _frames: int = 0
var _ship_root: Node3D
var _camera_placed: bool = false
var _out_path: String = ""
var _ceiling_controller: Node


func _initialize() -> void:
	if not ClassDB.class_exists("DerelictGenerator"):
		push_error("PREVIEW FAIL: DerelictGenerator not available")
		quit(1)
		return

	# Read seed/archetype from CLI args
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_val: int = 3
	var archetype: String = "frigate"
	for i in range(args.size()):
		if args[i] == "--seed" and i + 1 < args.size():
			seed_val = int(args[i + 1])
		elif args[i] == "--archetype" and i + 1 < args.size():
			archetype = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]

	if _out_path.is_empty():
		_out_path = "/tmp/worldgen-ship.png"

	print("Generating: seed=", seed_val, " archetype=", archetype)

	var archetype_map := {0: "shuttle", 1: "corvette", 2: "freighter", 3: "frigate"}
	var intactness_map := {0: 9500, 1: 6000, 2: 2000, 3: 6000}
	var arch_id: int = 3
	for k in archetype_map:
		if archetype_map[k] == archetype:
			arch_id = k
			break

	var params := {
		"archetype_id": archetype,
		"intactness_override": int(intactness_map[arch_id]),
	}

	var gen = ClassDB.instantiate("DerelictGenerator")
	var layout_text: String = str(gen.export_layout_json(seed_val, params, "ship_structural_v0"))
	var layout: Variant = JSON.parse_string(layout_text)
	if not (layout is Dictionary):
		push_error("PREVIEW FAIL: layout parse failed")
		quit(1)
		return
	var layout_doc: Dictionary = (layout as Dictionary).duplicate(true)

	var gameplay_text: String = str(gen.export_gameplay_slice_json(seed_val, params))
	var gp: Variant = JSON.parse_string(gameplay_text)
	var gameplay_doc: Dictionary = {}
	if gp is Dictionary:
		gameplay_doc = (gp as Dictionary).duplicate(true)

	var kit_doc: Dictionary = {}
	if FileAccess.file_exists(KIT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
		if parsed is Dictionary:
			kit_doc = (parsed as Dictionary).duplicate(true)

	# Fix prototype
	if not (layout_doc.get("prototype", {}) is Dictionary):
		layout_doc["prototype"] = {
			"start_room": gameplay_doc.get("start_room", ""),
			"goal_room": gameplay_doc.get("goal_room", ""),
		}

	var rooms: Array = layout_doc.get("rooms", [])
	var placements: Array = (layout_doc.get("structural_plan", {}) as Dictionary).get("placements", [])
	print("rooms: ", rooms.size(), " placements: ", placements.size())

	var loader_script = preload("res://scripts/procgen/generated_ship_loader.gd")
	_ship_root = loader_script.new()
	root.add_child(_ship_root)

	var success: bool = _ship_root.load_from_documents(layout_doc, kit_doc, gameplay_doc, false)
	if not success:
		push_error("PREVIEW FAIL: load_from_documents returned false")
		quit(1)
		return

	print("SHIP LOADED")

	# Lighting + environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.4
	root.add_child(light)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.35, 0.4)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	root.add_child(env)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 3 and not _camera_placed:
		_camera_placed = true

		# Ceiling fade controller
		var controller_script = load("res://scripts/procgen/ceiling_fade_controller.gd")
		if controller_script != null:
			_ceiling_controller = controller_script.new()
			_ceiling_controller.name = "CeilingFadeController"
			root.add_child(_ceiling_controller)
			# Spawn a player proxy at the loader root for fade distance calc
			var proxy := Node3D.new()
			proxy.global_position = _ship_root.global_position
			root.add_child(proxy)
			_ceiling_controller.configure(_ship_root, proxy)

		# Camera: isometric, looking down at the ship
		var min_pos := Vector3(INF, INF, INF)
		var max_pos := Vector3(-INF, -INF, -INF)
		for child in _ship_root.get_children():
			if child is Node3D:
				for sub in (child as Node3D).get_children():
					if sub is Node3D:
						var gp: Vector3 = (sub as Node3D).global_position
						min_pos = min_pos.min(gp)
						max_pos = max_pos.max(gp)
		var center := (min_pos + max_pos) * 0.5
		var extent_x: float = max_pos.x - min_pos.x
		var extent_z: float = max_pos.z - min_pos.z
		print("ship bounds: ", min_pos, " to ", max_pos)

		var cam_dist: float = max(extent_x, extent_z) * 0.9 + 20.0
		var cam_pos := Vector3(
			center.x + cam_dist * cos(deg_to_rad(35.0)) * cos(deg_to_rad(45.0)),
			center.y + cam_dist * sin(deg_to_rad(35.0)),
			center.z + cam_dist * cos(deg_to_rad(35.0)) * sin(deg_to_rad(45.0))
		)
		var camera := Camera3D.new()
		camera.look_at_from_position(cam_pos, center)
		camera.fov = 40
		root.add_child(camera)

	if _frames == 30:
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(_out_path)
			print("VIEWPORT SAVED to ", _out_path, " (", img.get_width(), "x", img.get_height(), ")")
		quit(0)
	return false
