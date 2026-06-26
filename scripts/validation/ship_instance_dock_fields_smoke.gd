extends SceneTree

## ShipInstance.ship_root aliases scene_root, and interior_aabb() encloses the
## scene_root's geometry in world space.

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""
	var root := Node3D.new()
	root.position = Vector3(5, 0, 0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()   # 1x1x1 box centered at local origin
	root.add_child(mesh)
	get_root().add_child(root)   # in-tree so global transforms resolve

	var inst = ShipInstanceScript.create("s", "", null, null, null)
	inst.ship_root = root        # alias setter -> scene_root
	if inst.scene_root != root:
		ok = false; msg = "ship_root setter did not write scene_root"
	if ok and inst.ship_root != root:
		ok = false; msg = "ship_root getter did not read scene_root"

	if ok:
		var box: AABB = inst.interior_aabb()
		# The box (≈ [-0.5,0.5]^3) offset by +5 X must contain (5,0,0) and not (50,0,0).
		if not box.grow(0.01).has_point(Vector3(5, 0, 0)):
			ok = false; msg = "interior_aabb does not contain ship center"
		elif box.has_point(Vector3(50, 0, 0)):
			ok = false; msg = "interior_aabb wrongly contains a far point"

	root.queue_free()
	if ok:
		print("SHIP INSTANCE DOCK FIELDS PASS alias=true aabb=true")
		quit(0)
	else:
		push_error("SHIP INSTANCE DOCK FIELDS FAIL reason=%s" % msg)
		quit(1)
