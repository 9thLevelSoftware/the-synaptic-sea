extends SceneTree

const EXPECTED_FLOOR_COLLISIONS := {
	"res://scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn": Vector3(4.0, 0.25, 4.0),
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn": Vector3(4.0, 0.25, 4.0),
	"res://scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn": Vector3(8.0, 0.25, 4.0),
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn": Vector3(4.0, 0.25, 8.0),
}

func _initialize() -> void:
	var failures: Array[String] = []
	for scene_path in EXPECTED_FLOOR_COLLISIONS.keys():
		var packed: PackedScene = load(scene_path)
		if packed == null:
			failures.append("could not load %s" % scene_path)
			continue
		var instance: Node = packed.instantiate()
		var collision_shape: CollisionShape3D = _find_collision_shape(instance)
		if collision_shape == null or not (collision_shape.shape is BoxShape3D):
			failures.append("missing BoxShape3D in %s" % scene_path)
			instance.free()
			continue
		var box: BoxShape3D = collision_shape.shape as BoxShape3D
		var expected: Vector3 = EXPECTED_FLOOR_COLLISIONS[scene_path]
		if not _vectors_close(box.size, expected):
			failures.append("%s collision size expected=%s actual=%s" % [scene_path, str(expected), str(box.size)])
		instance.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=%d" % EXPECTED_FLOOR_COLLISIONS.size())
	quit(0)

func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found: CollisionShape3D = _find_collision_shape(child)
		if found != null:
			return found
	return null

func _vectors_close(actual: Vector3, expected: Vector3) -> bool:
	return actual.distance_to(expected) < 0.001
