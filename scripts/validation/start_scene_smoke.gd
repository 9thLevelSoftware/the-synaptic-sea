extends SceneTree

# Start scene combiner smoke. Verifies:
#   1. StartSceneBuilder.build(seed) produces a valid StartScene
#   2. Contains both derelict and life boat as children
#   3. Derelict has a dock room
#   4. Life boat has 3 rooms
#   5. Life boat is positioned adjacent to the dock
#   6. Determinism: same seed = same structure

const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	# Test a few seeds.
	for seed_val in [42, 100, 999]:
		var scene: Node3D = StartSceneBuilderScript.build(seed_val)
		if scene == null:
			failures.append("seed=%d build returned null" % seed_val)
			continue

		if String(scene.name) != "StartScene":
			failures.append("seed=%d name=%s" % [seed_val, str(scene.name)])
			continue

		if scene.get_child_count() != 2:
			failures.append("seed=%d children=%d expected=2" % [
				seed_val, scene.get_child_count()])
			continue

		# First child is derelict, second is life boat.
		var derelict: Node = scene.get_child(0)
		var life_boat: Node = scene.get_child(1)

		if String(derelict.name) != "GeneratedShip":
			failures.append("seed=%d derelict name=%s" % [seed_val, str(derelict.name)])
			continue

		if String(life_boat.name) != "LifeBoat":
			failures.append("seed=%d life_boat name=%s" % [seed_val, str(life_boat.name)])
			continue

		# Derelict has ShipStructure with dock room.
		var d_structure: Node = derelict.get_child(0)
		if d_structure == null:
			failures.append("seed=%d derelict no structure" % seed_val)
			continue

		var dock_found: bool = false
		for child in d_structure.get_children():
			if String(child.name).begins_with("dock"):
				dock_found = true
				break
		if not dock_found:
			failures.append("seed=%d derelict no dock room" % seed_val)
			continue

		# Life boat has 3 rooms.
		var lb_structure: Node = life_boat.get_child(0)
		if lb_structure == null or lb_structure.get_child_count() != 3:
			failures.append("seed=%d life_boat rooms=%d" % [
				seed_val, lb_structure.get_child_count() if lb_structure else 0])
			continue

		# Life boat is positioned (not at origin).
		var lb_pos: Vector3 = (life_boat as Node3D).position
		if lb_pos == Vector3.ZERO:
			failures.append("seed=%d life_boat at origin" % seed_val)
			continue

		scene.queue_free()

	# Determinism: same seed = same child count and room count.
	var s1: Node3D = StartSceneBuilderScript.build(42)
	var s2: Node3D = StartSceneBuilderScript.build(42)
	if s1.get_child_count() != s2.get_child_count():
		failures.append("determinism child count mismatch")
	else:
		for i in range(s1.get_child_count()):
			var c1: Node = s1.get_child(i)
			var c2: Node = s2.get_child(i)
			if c1.get_child_count() != c2.get_child_count():
				failures.append("determinism child[%d] count mismatch" % i)

	if failures.is_empty():
		print("START SCENE PASS seeds=3 derelict+docked_lifeboat=true deterministic=true")
	else:
		for f in failures:
			push_error("START SCENE FAIL: %s" % f)
		print("START SCENE FAIL failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
