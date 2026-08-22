extends SceneTree
## SceneTree-based capture: generates ship with ithappy kit and captures
## screenshots from isometric and top-down angles.

const SEED := 17
const CAPTURE_DIR := "user://ithappy_captures"

func _init() -> void:
	if not DirAccess.dir_exists_absolute(CAPTURE_DIR):
		DirAccess.make_dir_absolute(CAPTURE_DIR)

	# Generate ship
	var ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
	var generator: RefCounted = ShipGeneratorScript.new()
	var blueprint = preload("res://scripts/procgen/ship_blueprint.gd").new(0, 1, SEED)
	var layout_gen = generator.layout_generator

	var layout: Dictionary = layout_gen.generate(blueprint)
	if layout.is_empty():
		print("CAPTURE FAIL: empty layout")
		quit(1)
		return

	var compiler = preload("res://scripts/procgen/structural_edge_compiler.gd").new()
	layout["structural_plan"] = compiler.compile(layout)

	var temp_dir := "user://procgen_ithappy_vis"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_absolute(temp_dir)

	var layout_path := temp_dir + "/layout.json"
	var kit_path := "res://data/kits/ithappy_scifi_v0.json"
	var gameplay_path := temp_dir + "/gameplay_slice.json"

	var f := FileAccess.open(layout_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout, "  "))
	f.close()

	var gameplay_builder = preload("res://scripts/procgen/gameplay_slice_builder.gd").new()
	var gameplay: Dictionary = gameplay_builder.build(layout)
	f = FileAccess.open(gameplay_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(gameplay, "  "))
	f.close()

	var loader = preload("res://scripts/procgen/generated_ship_loader.gd").new()
	if not loader.load_from_paths(layout_path, kit_path, gameplay_path):
		print("CAPTURE FAIL: loader returned false")
		quit(1)
		return

	loader.name = "GeneratedShip"
	root.add_child(loader)

	# Wait for scene to settle
	await create_timer(1.0).timeout

	# Isometric capture — use look_at_from_position to avoid tree errors
	var cam_iso := Camera3D.new()
	cam_iso.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam_iso.size = 22.0
	cam_iso.current = true
	root.add_child(cam_iso)
	cam_iso.global_position = Vector3(16, 18, 16)
	cam_iso.look_at_from_position(Vector3(16, 18, 16), Vector3.ZERO, Vector3.UP)

	await create_timer(0.5).timeout

	var viewport := root.get_viewport()
	var image := viewport.get_texture().get_image()
	if image:
		var path_iso := CAPTURE_DIR + "/isometric_seed_%d.png" % SEED
		image.save_png(path_iso)
		print("CAPTURE_SAVED isometric -> %s" % ProjectSettings.globalize_path(path_iso))
	else:
		print("CAPTURE WARN: null image for isometric")

	cam_iso.queue_free()
	await create_timer(0.2).timeout

	# Top-down capture
	var cam_top := Camera3D.new()
	cam_top.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam_top.size = 24.0
	cam_top.current = true
	root.add_child(cam_top)
	cam_top.global_position = Vector3(0, 30, 0.01)
	cam_top.look_at_from_position(Vector3(0, 30, 0.01), Vector3.ZERO, Vector3.UP)

	await create_timer(0.5).timeout

	image = viewport.get_texture().get_image()
	if image:
		var path_top := CAPTURE_DIR + "/topdown_seed_%d.png" % SEED
		image.save_png(path_top)
		print("CAPTURE_SAVED topdown -> %s" % ProjectSettings.globalize_path(path_top))
	else:
		print("CAPTURE WARN: null image for topdown")

	print("ITHAPPY_VISUAL_CAPTURE_COMPLETE")
	quit(0)
