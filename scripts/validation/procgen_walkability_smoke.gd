extends SceneTree

# End-to-end walkability smoke: generates ship from seed, bakes nav mesh,
# walks NavigationAgent3D from start through objectives to goal.
# This validates Phase 1: "rooms connect, geometry loads, player can walk through."

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const WALK_SPEED: float = 6.0
const TIMEOUT_FRAMES: int = 1500
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]


class PathWalker:
	extends Node3D

	var agent: NavigationAgent3D
	var waypoints: Array[Vector3] = []
	var current_waypoint: int = 0
	var walk_speed: float = WALK_SPEED
	var timeout_frames: int = TIMEOUT_FRAMES
	var frame_count: int = 0
	var finished: bool = false
	var seed_label: String = ""

	func _ready() -> void:
		set_physics_process(true)

	func _physics_process(delta: float) -> void:
		if finished:
			return
		frame_count += 1
		if frame_count < 2:
			return
		if agent == null:
			_fail("no-agent")
			return

		if current_waypoint >= waypoints.size():
			finished = true
			print("WALKABILITY PASS %s frames=%d waypoints=%d" % [seed_label, frame_count, waypoints.size()])
			get_tree().quit(0)
			return

		var target: Vector3 = waypoints[current_waypoint]
		var dist: float = global_position.distance_to(target)
		if dist <= 1.0:
			current_waypoint += 1
			if current_waypoint < waypoints.size():
				agent.target_position = waypoints[current_waypoint]
			return

		var next_pos: Vector3 = agent.get_next_path_position()
		var step: Vector3 = next_pos - global_position
		if step.length_squared() > 0.000001:
			global_position = global_position.move_toward(next_pos, walk_speed * delta)

		if frame_count >= timeout_frames:
			_fail("timeout at waypoint %d/%d dist=%.2f" % [current_waypoint, waypoints.size(), dist])

	func _fail(reason: String) -> void:
		finished = true
		push_error("WALKABILITY FAIL %s frames=%d waypoint=%d/%d reason=%s" % [
			seed_label, frame_count, current_waypoint, waypoints.size(), reason])
		get_tree().quit(1)


func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var seeds: Array[int] = [42, 999]

	# Test one combination to keep the smoke fast
	var template_id: String = templates[0]
	var seed_val: int = seeds[0]
	var label: String = "%s_seed_%d" % [template_id, seed_val]

	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		seed_val)
	var layout: Dictionary = generator.generate(bp, {"template": template_id})
	if layout.is_empty():
		push_error("WALKABILITY FAIL %s layout empty" % label)
		quit(1)
		return

	var rooms: Array = layout.get("rooms", [])
	var gameplay: Dictionary = slice_builder.build(layout)
	var start_room_id: String = str(gameplay.get("start_room", ""))
	var goal_room_id: String = str(gameplay.get("goal_room", ""))

	if start_room_id.is_empty() or goal_room_id.is_empty():
		push_error("WALKABILITY FAIL %s missing start/goal room" % label)
		quit(1)
		return

	# Build waypoints: start center -> each objective -> goal center
	var waypoints: Array[Vector3] = []
	for obj in gameplay.get("objectives", []):
		var room_id: String = str(obj.get("room_id", ""))
		var center: Vector3 = _room_center(rooms, room_id)
		if center != Vector3.INF:
			waypoints.append(center)

	var goal_center: Vector3 = _room_center(rooms, goal_room_id)
	if goal_center == Vector3.INF:
		push_error("WALKABILITY FAIL %s goal room center not found" % label)
		quit(1)
		return
	waypoints.append(goal_center)

	if waypoints.is_empty():
		push_error("WALKABILITY FAIL %s no walkable waypoints" % label)
		quit(1)
		return

	var start_center: Vector3 = _room_center(rooms, start_room_id)
	if start_center == Vector3.INF:
		push_error("WALKABILITY FAIL %s start room center not found" % label)
		quit(1)
		return

	# Build nav mesh from floor cells
	var tree_root: Node = get_root()
	var ship_root: Node3D = Node3D.new()
	ship_root.name = "WalkabilityTestShip"
	tree_root.add_child(ship_root)

	var nav_region: NavigationRegion3D = _build_navigation_region(rooms, ship_root)
	if nav_region == null:
		push_error("WALKABILITY FAIL %s could not build nav mesh" % label)
		quit(1)
		return

	# Add vertical links if any
	_add_vertical_links(layout, ship_root)

	# Spawn walker at start
	var walker: PathWalker = PathWalker.new()
	walker.name = "PathWalker"
	walker.position = start_center
	walker.waypoints = waypoints
	walker.seed_label = label
	walker.timeout_frames = TIMEOUT_FRAMES
	walker.walk_speed = WALK_SPEED
	ship_root.add_child(walker)

	var agent: NavigationAgent3D = NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	agent.path_desired_distance = 0.35
	agent.target_desired_distance = 1.0
	agent.target_position = waypoints[0]
	walker.agent = agent
	walker.add_child(agent)

	print("WALKABILITY start room=%s goal=%s waypoints=%d" % [start_room_id, goal_room_id, waypoints.size()])


func _room_center(rooms: Array, room_id: String) -> Vector3:
	for room in rooms:
		if str(room.get("id", "")) != room_id:
			continue
		var total: Vector3 = Vector3.ZERO
		var count: int = 0
		for placement in room.get("structural_placements", []):
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in FLOOR_MODULES:
				continue
			var pos: Array = placement.get("position", [0, 0, 0])
			if pos.size() < 3:
				continue
			total += Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
			count += 1
		if count == 0:
			return Vector3.INF
		return total / float(count)
	return Vector3.INF


func _build_navigation_region(rooms: Array, ship_root: Node3D) -> NavigationRegion3D:
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var floor_count: int = 0
	for room in rooms:
		for placement in room.get("structural_placements", []):
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in FLOOR_MODULES:
				continue
			var pos: Array = placement.get("position", [0, 0, 0])
			if pos.size() < 3:
				continue
			var center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
			var half: float = CELL_SIZE * 0.5
			source.add_faces(PackedVector3Array([
				center + Vector3(-half, 0, -half),
				center + Vector3(half, 0, -half),
				center + Vector3(half, 0, half),
				center + Vector3(-half, 0, -half),
				center + Vector3(half, 0, half),
				center + Vector3(-half, 0, half),
			]), Transform3D())
			floor_count += 1

	if floor_count == 0:
		push_error("WALKABILITY FAIL 0 floor cells")
		return null

	var nav_mesh: NavigationMesh = NavigationMesh.new()
	NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, source)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "WalkabilityNavRegion"
	nav_region.navigation_mesh = nav_mesh
	ship_root.add_child(nav_region)
	print("Nav mesh: %d floor cells -> %d polygons" % [floor_count, nav_mesh.get_polygon_count()])
	return nav_region


func _add_vertical_links(layout: Dictionary, ship_root: Node3D) -> void:
	var links: Array = layout.get("vertical_connections", [])
	for link in links:
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var from_pos: Vector3 = _link_endpoint_pos(link, "from_cell", "from_room", layout)
		var to_pos: Vector3 = _link_endpoint_pos(link, "to_cell", "to_room", layout)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var nav_link: NavigationLink3D = NavigationLink3D.new()
		nav_link.bidirectional = true
		nav_link.start_position = from_pos
		nav_link.end_position = to_pos
		ship_root.add_child(nav_link)


func _link_endpoint_pos(link: Dictionary, cell_key: String, room_key: String, layout: Dictionary) -> Vector3:
	var cell: Array = link.get(cell_key, [])
	var room_id: String = str(link.get(room_key, ""))
	if cell.size() < 2 or room_id.is_empty():
		return Vector3.INF
	for room in layout.get("rooms", []):
		if str(room.get("id", "")) != room_id:
			continue
		for placement in room.get("structural_placements", []):
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in FLOOR_MODULES:
				continue
			var placement_name: String = str(placement.get("name", ""))
			# Match cell coordinates in placement name
			var target_x: int = int(cell[0])
			var target_z: int = int(cell[1])
			var parts: PackedStringArray = placement_name.split("_")
			for i in range(parts.size()):
				if String(parts[i]).begins_with("x") and i + 1 < parts.size() and String(parts[i + 1]).begins_with("z"):
					var x_str: String = String(parts[i]).substr(1)
					var z_str: String = String(parts[i + 1]).substr(1)
					if x_str.is_valid_int() and z_str.is_valid_int():
						if int(x_str) == target_x and int(z_str) == target_z:
							var pos: Array = placement.get("position", [0, 0, 0])
							return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
	return Vector3.INF
