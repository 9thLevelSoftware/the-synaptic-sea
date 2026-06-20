extends SceneTree

# Generates ship scenes and saves them as .tscn files for visual inspection.

const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

const OUTPUT_DIR: String = "res://scenes/generated/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	# Start scenes for different seeds.
	for seed_val in [42, 999, 7777]:
		var scene: Node3D = StartSceneBuilderScript.build(seed_val)
		if scene == null:
			push_error("Failed seed %d" % seed_val)
			continue
		_add_camera(scene)
		_save(scene, "start_scene_seed_%d.tscn" % seed_val)

	# Standalone life boat.
	var lb: Node3D = LifeBoatBuilderScript.build()
	if lb != null:
		_add_camera(lb)
		_save(lb, "life_boat.tscn")

	# Standalone derelict.
	var file := FileAccess.open("res://data/procgen/archetypes/derelict.json", FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var archetype: Dictionary = json.data
	var bp_data: Dictionary = archetype.get("blueprint", {})
	bp_data["seed_value"] = 42
	var bp = ShipBlueprintScript.from_dict(bp_data)
	var gen: ShipGeneratorScript = ShipGeneratorScript.new()
	var derelict: Node3D = gen.generate(bp, archetype)
	if derelict != null:
		_add_camera(derelict)
		_save(derelict, "derelict_seed_42.tscn")

	print("Done. Scenes saved to %s" % OUTPUT_DIR)
	quit(0)


func _add_camera(root: Node3D) -> void:
	var aabb: AABB = _compute_aabb(root)
	var center: Vector3 = aabb.get_center()
	var extent: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))

	var cam: Camera3D = Camera3D.new()
	cam.name = "ViewCamera"
	cam.position = center + Vector3(extent * 0.4, extent * 1.0, extent * 0.4)
	cam.look_at(center)
	root.add_child(cam)

	# Add a directional light so things are visible.
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "Sun"
	light.position = center + Vector3(10, 20, 10)
	light.look_at(center)
	light.light_energy = 1.0
	root.add_child(light)


func _compute_aabb(root: Node3D) -> AABB:
	var min_p: Vector3 = Vector3(INF, INF, INF)
	var max_p: Vector3 = Vector3(-INF, -INF, -INF)
	_walk(root, Transform3D.IDENTITY, min_p, max_p)
	if min_p.x == INF:
		return AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	return AABB(min_p, max_p - min_p)


func _walk(node: Node, xform: Transform3D, min_p: Vector3, max_p: Vector3) -> void:
	if node is Node3D:
		var wp: Vector3 = xform * (node as Node3D).position
		min_p.x = min(min_p.x, wp.x); min_p.y = min(min_p.y, wp.y); min_p.z = min(min_p.z, wp.z)
		max_p.x = max(max_p.x, wp.x); max_p.y = max(max_p.y, wp.y); max_p.z = max(max_p.z, wp.z)
		var nx: Transform3D = xform * (node as Node3D).transform
		for c in node.get_children():
			_walk(c, nx, min_p, max_p)


func _save(root: Node3D, filename: String) -> void:
	get_root().add_child(root)
	var path: String = OUTPUT_DIR + filename
	var packed: PackedScene = PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("Pack failed for %s: %d" % [filename, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Save failed for %s: %d" % [filename, err])
		return
	print("Saved: %s" % path)
