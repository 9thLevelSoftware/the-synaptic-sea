extends SceneTree

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Build a real lifeboat structure and place its root off-origin.
	var root: Node3D = LifeBoatBuilderScript.build()
	root.position = Vector3(-35.0, 0.0, 0.0)
	get_root().add_child(root)   # in-tree so global_transform is valid

	var inst = ShipInstanceScript.create("lb", "", null, null, root)
	var aabb: AABB = inst.interior_aabb()

	# Must be a real, non-degenerate volume (the 5a bug returned a zero-size AABB here).
	if aabb.size.x <= 0.1 or aabb.size.z <= 0.1:
		ok = false; msg = "AABB degenerate: %s" % str(aabb)

	# Must be centered near the placed world position (-35 on X), not at origin.
	if ok and absf(aabb.get_center().x - (-35.0)) > 20.0:
		ok = false; msg = "AABB not at world position: center=%s" % str(aabb.get_center())

	# A point inside the placed hull is contained; a far point is not.
	if ok and not aabb.grow(0.001).has_point(Vector3(-35.0, 0.5, 0.0)):
		ok = false; msg = "expected interior point not contained: %s" % str(aabb)
	if ok and aabb.has_point(Vector3(100.0, 0.0, 0.0)):
		ok = false; msg = "far point wrongly contained"

	root.free()

	if ok:
		print("INTERIOR AABB PASS nondegenerate=true positioned=true contains=true")
		quit(0)
	else:
		push_error("INTERIOR AABB FAIL reason=%s" % msg)
		quit(1)
