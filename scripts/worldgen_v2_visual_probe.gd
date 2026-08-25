extends SceneTree
## Visual probe: load a worldgen-exported ship through GeneratedShipLoader
## and screenshot it from the game's isometric camera angle.
##   godot --path D:/the-synaptic-sea --script D:/world_gen/scripts/worldgen_v2_visual_probe.gd
## Env: WORLDGEN_EXPORT_DIR (default D:/world_gen/target/export)
##      WORLDGEN_KIT_PATH (default res://data/kits/ship_structural_v0.json)
##      WORLDGEN_SHOT (default D:/world_gen/target/worldgen_in_synaptic_sea.png)

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

var _frames := 0
var _loaded := false
var _cam: Camera3D

func _initialize() -> void:
	var export_dir := OS.get_environment("WORLDGEN_EXPORT_DIR")
	if export_dir.is_empty():
		export_dir = "D:/world_gen/target/export"
	var kit_path := OS.get_environment("WORLDGEN_KIT_PATH")
	if kit_path.is_empty():
		kit_path = "res://data/kits/ship_structural_v0.json"
	print("VISUAL PROBE INPUT export_dir=%s kit=%s" % [export_dir, kit_path])
	var loader: Node3D = LoaderScript.new()
	root.add_child(loader)
	var ok: bool = loader.load_from_paths(
		export_dir + "/layout.json",
		kit_path,
		export_dir + "/gameplay_slice.json",
		true)
	if not ok:
		push_error("VISUAL PROBE FAIL: loader rejected layout")
		quit(1)
		return
	_loaded = true

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_cam)
	_cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 140, 0)
	fill.light_energy = 0.5
	root.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.045, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)

func _process(_delta: float) -> bool:
	if not _loaded:
		return false
	_frames += 1
	if _frames == 20:
		var aabb := AABB()
		var first := true
		var stack: Array[Node] = [root as Node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D:
				var p: Vector3 = (n as Node3D).global_position
				if first:
					aabb = AABB(p, Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(p)
		var center := aabb.get_center()
		var extent: float = max(aabb.size.x, aabb.size.z)
		print("PROBE DEBUG center=%s extent=%.1f" % [center, extent])
		_cam.size = extent * 0.95 + 20.0
		_cam.position = center + Vector3(60, 70, 60)
		_cam.look_at(center, Vector3.UP)
	if _frames >= 45:
		var shot := OS.get_environment("WORLDGEN_SHOT")
		if shot.is_empty():
			shot = "D:/world_gen/target/worldgen_in_synaptic_sea.png"
		root.get_viewport().get_texture().get_image().save_png(shot)
		print("VISUAL PROBE PASS saved %s" % shot)
		quit(0)
		return true
	return false
