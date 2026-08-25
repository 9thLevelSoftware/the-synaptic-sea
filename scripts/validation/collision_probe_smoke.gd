extends SceneTree

## Headless collision proof for the loaded worldgen ship.
## Marker: COLLISION PROBE PASS

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const BLOCKED_COST: float = 1.0e9
const CELL_SIZE: float = 4.0

var loader: Node3D
var finished: bool = false


func _initialize() -> void:
	var export_dir: String = OS.get_environment("WORLDGEN_EXPORT_DIR")
	if export_dir.is_empty():
		export_dir = "D:/world_gen/target/export"
	var layout_path: String = export_dir.path_join("layout.json")
	var gameplay_path: String = export_dir.path_join("gameplay_slice.json")
	if not FileAccess.file_exists(layout_path) or not FileAccess.file_exists(gameplay_path):
		_fail("worldgen export missing layout or gameplay slice")
		return
	loader = LoaderScript.new()
	get_root().add_child(loader)
	if not loader.load_from_paths(layout_path, "res://data/kits/ship_structural_v0.json", gameplay_path, true):
		_fail("GeneratedShipLoader rejected worldgen export")
		return
	physics_frame.connect(_probe)


func _probe() -> void:
	if finished:
		return
	var layout: Dictionary = loader.layout_doc
	var plan_variant: Variant = layout.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		_fail("loaded layout has no structural_plan")
		return
	var shape_error: String = _validate_wrapper_shapes(loader.structural_root)
	if not shape_error.is_empty():
		_fail(shape_error)
		return
	var state: PhysicsDirectSpaceState3D = loader.get_world_3d().direct_space_state
	var solid_checked: int = 0
	var passable_checked: int = 0
	var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
	if not (edges_variant is Dictionary):
		_fail("structural_plan.edges is not a Dictionary")
		return
	for edge_variant in (edges_variant as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var source_variant: Variant = edge.get("source_cells", [])
		if not (source_variant is Array) or (source_variant as Array).size() < 2:
			continue
		var first: Dictionary = _read_cell((source_variant as Array)[0], int(edge.get("deck", -1)))
		var second: Dictionary = _read_cell((source_variant as Array)[1], int(edge.get("deck", -1)))
		if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
			continue
		if int(first["deck"]) != int(second["deck"]):
			continue
		var from_pos: Vector3 = _cell_world(first)
		var to_pos: Vector3 = _cell_world(second)
		var direction: Vector3 = (to_pos - from_pos).normalized()
		if direction.length_squared() < 0.5:
			continue
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
		if kind == "OPEN" and not bool(edge.get("wrapper_required", false)):
			continue
		if kind == "SOLID":
			solid_checked += 1
			if not _ray_hits(state, from_pos + Vector3.UP * 1.5 + direction * 1.0, to_pos + Vector3.UP * 1.5 - direction * 1.0):
				_fail("SOLID edge was not hit: %s" % str(edge.get("edge_key", edge.get("key", ""))))
				return
		elif kind == "OPEN" or kind == "DOOR":
			passable_checked += 1
			var tangent_unit: Vector3 = Vector3.BACK if absf(direction.x) > absf(direction.z) else Vector3.RIGHT
			var clear_lane_found: bool = false
			for lane_offset in [0.0, -0.5, 0.5, -1.0, 1.0, -1.5, 1.5]:
				var lane_offset_vector: Vector3 = tangent_unit * float(lane_offset)
				var lane_hit: Dictionary = _ray_cast(state, from_pos + lane_offset_vector + Vector3.UP * 1.0 + direction * 1.0, to_pos + lane_offset_vector + Vector3.UP * 1.0 - direction * 1.0)
				if lane_hit.is_empty():
					clear_lane_found = true
					break
			if not clear_lane_found:
				_fail("%s edge blocked below aperture: %s" % [kind, str(edge.get("edge_key", edge.get("key", "")))])
				return
	if solid_checked <= 0 or passable_checked <= 0:
		_fail("insufficient physical edge coverage solid=%d passable=%d" % [solid_checked, passable_checked])
		return
	finished = true
	print("COLLISION PROBE PASS walls=true doors=true aperture=true solid_edges=%d passable_edges=%d thickness=0.2 hatch_skipped=true" % [solid_checked, passable_checked])
	loader.free()
	quit(0)


func _validate_wrapper_shapes(root: Node) -> String:
	if root == null:
		return "structural root missing"
	var seen: Dictionary = {}
	for child in root.get_children():
		if not (child is Node3D) or not child.has_meta("module_kind"):
			continue
		var module_id: String = str(child.get_meta("module_kind", ""))
		if seen.has(module_id) or module_id == "bulkhead_portal_2x1":
			continue
		seen[module_id] = true
		var sizes: Array[Vector3] = _collision_box_sizes(child)
		var expected: Array[Vector3] = _expected_sizes(module_id)
		if expected.is_empty():
			continue
		if sizes.size() != expected.size():
			return "wrapper shape count mismatch module=%s expected=%d actual=%d" % [module_id, expected.size(), sizes.size()]
		for expected_size in expected:
			var matched: bool = false
			for actual_size in sizes:
				if actual_size.is_equal_approx(expected_size):
					matched = true
					break
			if not matched:
				return "wrapper shape mismatch module=%s expected=%s actual=%s" % [module_id, str(expected_size), str(sizes)]
	return ""


func _expected_sizes(module_id: String) -> Array[Vector3]:
	match module_id:
		"wall_straight_1x1", "wall_end_cap":
			return [Vector3(4.0, 3.0, 0.2)]
		"wall_inner_corner":
			return [Vector3(4.0, 3.0, 0.2), Vector3(0.2, 3.0, 4.0)]
		"wall_outer_corner":
			return [Vector3(4.0, 3.0, 0.2), Vector3(0.2, 3.0, 4.0)]
		"wall_t_junction":
			return [Vector3(4.0, 3.0, 0.2), Vector3(0.2, 3.0, 4.0), Vector3(0.2, 3.0, 4.0)]
		"doorway_frame_blocked_1x1":
			return [Vector3(4.0, 3.2, 0.2)]
		"doorway_frame_open_1x1":
			return [Vector3(1.4, 3.2, 0.2), Vector3(1.4, 3.2, 0.2), Vector3(4.0, 1.0, 0.2)]
	return []


func _collision_box_sizes(node: Node) -> Array[Vector3]:
	var sizes: Array[Vector3] = []
	if node is CollisionShape3D:
		var shape: Shape3D = (node as CollisionShape3D).shape
		if shape is BoxShape3D:
			sizes.append((shape as BoxShape3D).size)
	for child in node.get_children():
		sizes.append_array(_collision_box_sizes(child))
	return sizes


func _cell_world(cell: Dictionary) -> Vector3:
	return Vector3(float(cell["x"]) * CELL_SIZE, float(cell["deck"]) * CELL_SIZE, float(cell["z"]) * CELL_SIZE)


func _read_cell(value: Variant, default_deck: int) -> Dictionary:
	if value is Array:
		var values: Array = value
		if values.size() < 2:
			return {"ok": false}
		var deck: int = int(values[2]) if values.size() >= 3 else default_deck
		return {"ok": deck >= 0, "x": int(values[0]), "z": int(values[1]), "deck": deck}
	if value is String:
		var text: String = str(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() < 2:
			parts = text.split(" ", false)
		if parts.size() < 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
			return {"ok": false}
		var deck: int = int(parts[2].strip_edges()) if parts.size() >= 3 and parts[2].strip_edges().is_valid_int() else default_deck
		return {"ok": deck >= 0, "x": int(parts[0]), "z": int(parts[1]), "deck": deck}
	return {"ok": false}


func _ray_hits(state: PhysicsDirectSpaceState3D, from_pos: Vector3, to_pos: Vector3) -> bool:
	return not _ray_cast(state, from_pos, to_pos).is_empty()


func _ray_cast(state: PhysicsDirectSpaceState3D, from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from_pos
	query.to = to_pos
	query.collision_mask = 1
	query.collide_with_areas = false
	return state.intersect_ray(query)


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COLLISION PROBE FAIL reason=%s" % reason)
	if loader != null and is_instance_valid(loader):
		loader.free()
	quit(1)
