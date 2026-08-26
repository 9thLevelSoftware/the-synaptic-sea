extends SceneTree
## Live preview: generates a ship through the worldgen v2 Rust pipeline,
## loads it via GeneratedShipLoader, captures a viewport screenshot.

const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const SEED: int = 42
const SIZE: int = 1  # SMALL (corvette)
const CONDITION: int = 1  # DAMAGED

var _frames := 0
var _loader: Node3D
var _camera_placed := false


func _initialize() -> void:
	if not ClassDB.class_exists("DerelictGenerator"):
		push_error("PREVIEW FAIL: DerelictGenerator not available")
		quit(1)
		return

	var gen = ClassDB.instantiate("DerelictGenerator")
	print("worldgen version: ", gen.generator_version())

	var archetype_map := {0: "shuttle", 1: "corvette", 2: "freighter"}
	var intactness_map := {0: 9500, 1: 6000, 2: 2000}
	var params := {
		"archetype_id": str(archetype_map[SIZE]),
		"intactness_override": int(intactness_map[CONDITION]),
	}

	var layout_text: String = str(gen.export_layout_json(SEED, params, "ship_structural_v0"))
	var layout: Variant = JSON.parse_string(layout_text)
	if not (layout is Dictionary):
		push_error("PREVIEW FAIL: layout parse failed")
		quit(1)
		return
	var layout_doc: Dictionary = (layout as Dictionary).duplicate(true)

	var gameplay_text: String = str(gen.export_gameplay_slice_json(SEED, params))
	var gameplay_doc: Dictionary = {}
	var gp: Variant = JSON.parse_string(gameplay_text)
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
	# Bypass validation
	layout_doc["structural_plan_validated"] = true
	layout_doc.erase("critical_path")

	# Strip ceilings so isometric camera sees into the ship (Zomboid-style)
	# Can't empty the array (validator rejects it), so hide after loading.

	print("rooms: ", (layout_doc.get("rooms", []) as Array).size())
	print("placements: ", ((layout_doc.get("structural_plan", {}) as Dictionary).get("placements", []) as Array).size())

	var loader_script = preload("res://scripts/procgen/generated_ship_loader.gd")
	_loader = loader_script.new()
	root.add_child(_loader)

	var success: bool = _loader.load_from_documents(layout_doc, kit_doc, gameplay_doc, false)
	if not success:
		push_error("PREVIEW FAIL: load_from_documents returned false")
		quit(1)
		return

	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.2
	root.add_child(light)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.3, 0.35)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	root.add_child(env)

	print("SHIP LOADED — waiting for tree settle...")


func _process(_delta: float) -> bool:
	_frames += 1

	# Frame 3: place camera INSIDE the ship at floor level
	if _frames == 3 and not _camera_placed:
		_camera_placed = true

		# Hide all ceiling nodes (Zomboid-style: see into rooms from isometric)
		for child in _loader.get_children():
			if child is Node3D:
				for sub in (child as Node3D).get_children():
					if sub is Node3D and (sub as Node3D).name.begins_with("Ceiling_"):
						(sub as Node3D).visible = false

		var min_pos := Vector3(INF, INF, INF)
		var max_pos := Vector3(-INF, -INF, -INF)
		for child in _loader.get_children():
			if child is Node3D:
				for sub in (child as Node3D).get_children():
					if sub is Node3D:
						var gp: Vector3 = (sub as Node3D).global_position
						min_pos = min_pos.min(gp)
						max_pos = max_pos.max(gp)
		var center := (min_pos + max_pos) * 0.5
		print("ship bounds: min=", min_pos, " max=", max_pos, " center=", center)

		# Isometric camera: 35° elevation, looking down at the ship center
		var elevation_angle: float = 35.0  # degrees from horizontal
		var azimuth_angle: float = 45.0    # degrees from +X axis
		var rad_elev: float = deg_to_rad(elevation_angle)
		var rad_azim: float = deg_to_rad(azimuth_angle)
		var cam_dist: float = 120.0  # far enough to see most of the ship
		var cam_pos := Vector3(
			center.x + cam_dist * cos(rad_elev) * cos(rad_azim),
			center.y + cam_dist * sin(rad_elev),
			center.z + cam_dist * cos(rad_elev) * sin(rad_azim)
		)
		var camera := Camera3D.new()
		camera.look_at_from_position(cam_pos, center)
		camera.fov = 35  # narrow FOV for isometric feel
		root.add_child(camera)
		print("isometric camera at ", cam_pos, " looking at ", center)

	# Frame 30: capture viewport
	if _frames == 30:
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("/tmp/worldgen-v2-viewport.png")
			print("VIEWPORT SAVED to /tmp/worldgen-v2-viewport.png (", img.get_width(), "x", img.get_height(), ")")
		else:
			print("WARNING: viewport image was null")
		quit(0)
	return false
