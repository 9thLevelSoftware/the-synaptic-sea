extends Node3D
class_name GeneratedShipLoader

const GameplayObjectiveVolumeScript := preload("res://scripts/procgen/gameplay_objective_volume.gd")

signal ship_loaded(summary: Dictionary)
signal load_failed(reason: String)

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const OBJECTIVE_TRIGGER_RADIUS: float = 1.5
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

var layout_doc: Dictionary = {}
var kit_doc: Dictionary = {}
var gameplay_doc: Dictionary = {}
var objective_specs: Array = []
var loot_container_specs: Array = []
var objective_volumes: Array = []
var landmark_nodes: Array[Node3D] = []
var blocked_route_nodes: Array[Node3D] = []
var visible_vertical_transition_nodes: Array[Node3D] = []
var breach_zone_markers: Array[Vector3] = []
var fire_zone_markers: Array[Vector3] = []
var fire_zone_specs: Array = []
var arc_zone_markers: Array[Vector3] = []
var arc_zone_specs: Array = []
var start_position: Vector3 = Vector3.INF
var goal_position: Vector3 = Vector3.INF
var structural_root: Node3D
var objective_root: Node3D


func clear_loaded_ship() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	layout_doc = {}
	kit_doc = {}
	gameplay_doc = {}
	objective_specs = []
	loot_container_specs = []
	objective_volumes = []
	landmark_nodes = []
	blocked_route_nodes = []
	visible_vertical_transition_nodes = []
	breach_zone_markers = []
	fire_zone_markers = []
	fire_zone_specs = []
	arc_zone_markers = []
	arc_zone_specs = []
	start_position = Vector3.INF
	goal_position = Vector3.INF
	structural_root = null
	objective_root = null


func load_from_paths(layout_path: String, kit_path: String, gameplay_slice_path: String) -> bool:
	clear_loaded_ship()

	var layout_abs: String = _resolve_path(layout_path)
	var kit_abs: String = _resolve_path(kit_path)
	var gameplay_slice_abs: String = _resolve_path(gameplay_slice_path)

	if not FileAccess.file_exists(layout_abs):
		return _fail_load("layout not found: %s" % layout_abs)
	if not FileAccess.file_exists(kit_abs):
		return _fail_load("kit not found: %s" % kit_abs)
	if not FileAccess.file_exists(gameplay_slice_abs):
		return _fail_load("gameplay slice not found: %s" % gameplay_slice_abs)

	layout_doc = _load_json_dict(layout_abs, "layout")
	if layout_doc.is_empty():
		return _fail_load("layout JSON is invalid: %s" % layout_abs)
	kit_doc = _load_json_dict(kit_abs, "kit")
	if kit_doc.is_empty():
		return _fail_load("kit JSON is invalid: %s" % kit_abs)
	gameplay_doc = _load_json_dict(gameplay_slice_abs, "gameplay slice")
	if gameplay_doc.is_empty():
		return _fail_load("gameplay slice JSON is invalid: %s" % gameplay_slice_abs)

	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return _fail_load("layout missing rooms array: %s" % layout_abs)
	var rooms: Array = rooms_variant

	var prototype_variant: Variant = layout_doc.get("prototype", {})
	if typeof(prototype_variant) != TYPE_DICTIONARY:
		return _fail_load("layout missing prototype object: %s" % layout_abs)
	var prototype: Dictionary = prototype_variant

	var start_room_id: String = str(gameplay_doc.get("start_room", prototype.get("start_room", "")))
	var goal_room_id: String = str(gameplay_doc.get("goal_room", prototype.get("goal_room", "")))
	if start_room_id.is_empty():
		return _fail_load("gameplay slice missing start_room: %s" % gameplay_slice_abs)
	if goal_room_id.is_empty():
		return _fail_load("gameplay slice missing goal_room: %s" % gameplay_slice_abs)

	var module_to_scene: Dictionary = _build_module_scene_map(kit_doc, kit_abs)
	if module_to_scene.is_empty():
		return _fail_load("kit contains no usable module wrapper scenes: %s" % kit_abs)

	objective_specs = _build_objective_specs(layout_doc, gameplay_doc, gameplay_slice_abs)
	if objective_specs.is_empty():
		return _fail_load("gameplay slice contains no valid objectives: %s" % gameplay_slice_abs)

	loot_container_specs = _build_loot_container_specs(layout_doc, gameplay_doc)

	start_position = _room_center(rooms, start_room_id)
	goal_position = _room_center(rooms, goal_room_id)
	if start_position == Vector3.INF:
		return _fail_load("start room not found in layout: %s" % start_room_id)
	if goal_position == Vector3.INF:
		return _fail_load("goal room not found in layout: %s" % goal_room_id)

	structural_root = Node3D.new()
	structural_root.name = "StructuralRoot"
	add_child(structural_root)

	objective_root = Node3D.new()
	objective_root.name = "ObjectiveRoot"
	add_child(objective_root)

	var instantiated_count: int = _instance_structural_wrappers(layout_doc, module_to_scene, structural_root)
	if instantiated_count < 0:
		clear_loaded_ship()
		return _fail_load("failed to instantiate structural wrapper scenes")

	var nav_region: NavigationRegion3D = _build_navigation_region(rooms, structural_root)
	if nav_region == null:
		clear_loaded_ship()
		return _fail_load("no floor/corridor floor placements found for navigation mesh")

	var vertical_link_count: int = _add_vertical_links(layout_doc, structural_root)

	_add_coherence_runtime_nodes(layout_doc, structural_root)

	objective_volumes = []
	for objective_variant in objective_specs:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var world_position_variant: Variant = objective.get("position", Vector3.ZERO)
		var world_position: Vector3 = Vector3.ZERO
		if typeof(world_position_variant) == TYPE_VECTOR3:
			world_position = world_position_variant
		var volume = GameplayObjectiveVolumeScript.new()
		volume.configure(objective, world_position, OBJECTIVE_TRIGGER_RADIUS)
		objective_root.add_child(volume)
		objective_volumes.append(volume)

	emit_signal(
		"ship_loaded",
		{
			"layout_path": layout_abs,
			"kit_path": kit_abs,
			"gameplay_slice_path": gameplay_slice_abs,
			"instantiated_count": instantiated_count,
			"vertical_link_count": vertical_link_count,
			"objective_count": objective_specs.size(),
			"start_position": start_position,
			"goal_position": goal_position,
		}
	)
	return true


func _fail_load(reason: String) -> bool:
	push_error(reason)
	emit_signal("load_failed", reason)
	return false


func has_loaded_ship() -> bool:
	return structural_root != null and not objective_specs.is_empty() and start_position != Vector3.INF and goal_position != Vector3.INF


func get_start_transform() -> Transform3D:
	var spawn_position: Vector3 = start_position
	if spawn_position == Vector3.INF:
		spawn_position = Vector3.ZERO
	return Transform3D(Basis.IDENTITY, spawn_position)


func get_goal_position() -> Vector3:
	return goal_position


func get_objective_specs_copy() -> Array:
	return objective_specs.duplicate(true)


func get_loot_container_specs_copy() -> Array:
	return loot_container_specs.duplicate(true)


func count_collision_shapes() -> int:
	if structural_root == null:
		return 0
	return _count_collision_shapes_recursive(structural_root)


func _count_collision_shapes_recursive(node: Node) -> int:
	var count: int = 0
	if node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node
		if collision_shape.shape != null:
			count += 1
	for child in node.get_children():
		count += _count_collision_shapes_recursive(child)
	return count


func _resolve_path(raw_path: String) -> String:
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return ProjectSettings.globalize_path(raw_path)
	if raw_path.is_absolute_path():
		return raw_path
	if FileAccess.file_exists(raw_path) or DirAccess.open(raw_path) != null:
		return raw_path
	var cwd: String = OS.get_environment("PWD")
	if not cwd.is_empty():
		var cwd_path: String = cwd.path_join(raw_path)
		if FileAccess.file_exists(cwd_path) or DirAccess.open(cwd_path) != null:
			return cwd_path
	return ProjectSettings.globalize_path("res://%s" % raw_path)


func _load_json_dict(path: String, label: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s JSON is not an object: %s" % [label, path])
		return {}
	return parsed


func _build_module_scene_map(kit_doc: Dictionary, kit_path: String) -> Dictionary:
	var modules_variant: Variant = kit_doc.get("modules", [])
	if typeof(modules_variant) != TYPE_ARRAY:
		push_error("kit missing modules array: %s" % kit_path)
		return {}

	var module_to_scene: Dictionary = {}
	for module_variant in modules_variant:
		if typeof(module_variant) != TYPE_DICTIONARY:
			continue
		var module: Dictionary = module_variant
		var module_id: String = str(module.get("module_id", ""))
		var scene_path: String = str(module.get("godot_wrapper_scene", ""))
		if module_id.is_empty() or scene_path.is_empty():
			continue
		module_to_scene[module_id] = scene_path
	return module_to_scene


func _build_objective_specs(layout_doc: Dictionary, gameplay_doc: Dictionary, gameplay_slice_path: String) -> Array:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		push_error("layout missing rooms array: %s" % gameplay_slice_path)
		return []
	var rooms: Array = rooms_variant

	var objectives_variant: Variant = gameplay_doc.get("objectives", [])
	if typeof(objectives_variant) != TYPE_ARRAY:
		push_error("gameplay slice missing objectives array: %s" % gameplay_slice_path)
		return []
	var objectives: Array = objectives_variant
	if objectives.is_empty():
		push_error("gameplay slice contains no objectives: %s" % gameplay_slice_path)
		return []

	var expected_sequence: int = 1
	var objective_specs: Array = []
	for objective_variant in objectives:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			push_error("gameplay slice objective is not an object: %s" % gameplay_slice_path)
			return []
		var objective: Dictionary = objective_variant
		var objective_id: String = str(objective.get("id", ""))
		if objective_id.is_empty():
			push_error("gameplay slice objective missing id: %s" % gameplay_slice_path)
			return []
		var sequence: int = int(objective.get("sequence", 0))
		if sequence != expected_sequence:
			push_error(
				"gameplay slice objective sequence mismatch: expected=%d got=%d objective=%s"
				% [expected_sequence, sequence, objective_id]
			)
			return []
		expected_sequence += 1

		var room_id: String = str(objective.get("room_id", ""))
		if room_id.is_empty():
			push_error("gameplay slice objective missing room_id: %s" % objective_id)
			return []
		var room: Dictionary = _find_room(rooms, room_id)
		if room.is_empty():
			push_error("objective room not found in layout: %s" % room_id)
			return []

		var approach_variant: Variant = objective.get("approach_cell", [])
		if typeof(approach_variant) != TYPE_ARRAY:
			push_error("objective missing approach_cell: %s" % objective_id)
			return []
		var approach_cell: Array = approach_variant
		if approach_cell.size() < 3:
			push_error("objective approach_cell is incomplete: %s" % objective_id)
			return []

		var target_position: Vector3 = _room_cell_world(room, approach_cell)
		if target_position == Vector3.INF:
			push_error(
				"no floor position for approach cell objective=%s room=%s cell=%s"
				% [objective_id, room_id, str(approach_cell)]
			)
			return []

		var kind: String = str(objective.get("kind", "single"))
		var step_specs: Array = []
		if kind == "repair_junction":
			var steps_variant: Variant = objective.get("steps", [])
			if typeof(steps_variant) != TYPE_ARRAY or steps_variant.size() < 2:
				push_error("repair_junction objective requires at least 2 steps: %s" % objective_id)
				return []
			var seen_step_ids: Dictionary = {}
			for step_variant in steps_variant:
				if typeof(step_variant) != TYPE_DICTIONARY:
					push_error("repair_junction step is not an object: %s" % objective_id)
					return []
				var step: Dictionary = step_variant
				var step_id: String = str(step.get("step_id", ""))
				if step_id.is_empty():
					push_error("repair_junction step missing step_id: %s" % objective_id)
					return []
				if seen_step_ids.has(step_id):
					push_error("repair_junction duplicate step_id '%s' in objective %s" % [step_id, objective_id])
					return []
				seen_step_ids[step_id] = true
				var step_approach: Array = approach_cell.duplicate()
				var step_approach_variant: Variant = step.get("approach_cell", [])
				if typeof(step_approach_variant) == TYPE_ARRAY and step_approach_variant.size() >= 3:
					step_approach = step_approach_variant
				var step_position: Vector3 = _room_cell_world(room, step_approach)
				if step_position == Vector3.INF:
					push_error(
						"no floor position for step approach cell objective=%s step=%s cell=%s"
						% [objective_id, step_id, str(step_approach)]
					)
					return []
				step_specs.append({
					"step_id": step_id,
					"approach_cell": step_approach,
					"position": step_position,
				})

		objective_specs.append(
			{
				"id": objective_id,
				"sequence": sequence,
				"type": str(objective.get("type", "unknown")),
				"kind": kind,
				"room_id": room_id,
				"position": target_position,
				"radius": OBJECTIVE_TRIGGER_RADIUS,
				"steps": step_specs,
			}
		)

	return objective_specs


func _build_loot_container_specs(layout_doc: Dictionary, gameplay_doc: Dictionary) -> Array:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return []
	var rooms: Array = rooms_variant
	var containers_variant: Variant = gameplay_doc.get("loot_containers", [])
	if typeof(containers_variant) != TYPE_ARRAY:
		return []
	var out: Array = []
	for c_variant in (containers_variant as Array):
		if typeof(c_variant) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_variant
		var cid: String = str(c.get("id", ""))
		var room_id: String = str(c.get("room_id", ""))
		if cid.is_empty() or room_id.is_empty():
			continue
		var room: Dictionary = _find_room(rooms, room_id)
		if room.is_empty():
			continue
		var approach_variant: Variant = c.get("approach_cell", [])
		if typeof(approach_variant) != TYPE_ARRAY or (approach_variant as Array).size() < 3:
			continue
		var pos: Vector3 = _room_cell_world(room, approach_variant as Array)
		if pos == Vector3.INF:
			continue
		out.append({
			"id": cid,
			"kind": str(c.get("kind", "generic_crate")),
			"room_id": room_id,
			"loot_table": str(c.get("loot_table", "generic_crate")),
			"position": pos,
		})
	return out


func _find_room(rooms: Array, room_id: String) -> Dictionary:
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) == room_id:
			return room
	return {}


func _cell_name_candidates(cell: Array) -> Array:
	if cell.size() < 3:
		return []
	var x: int = int(cell[0])
	var z: int = int(cell[1])
	var deck: int = int(cell[2])
	var candidates: Array = []
	if deck == 0:
		candidates.append("floor_cell_x%d_z%d" % [x, z])
		candidates.append("floor_cell_d0_x%d_z%d" % [x, z])
	else:
		candidates.append("floor_cell_d%d_x%d_z%d" % [deck, x, z])
	return candidates


func _room_cell_world(room: Dictionary, cell: Array) -> Vector3:
	var candidates: Array = _cell_name_candidates(cell)
	if candidates.is_empty():
		return Vector3.INF

	var placements_variant: Variant = room.get("structural_placements", [])
	if typeof(placements_variant) != TYPE_ARRAY:
		return Vector3.INF
	var placements: Array = placements_variant
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_variant
		var name: String = str(placement.get("name", ""))
		if not candidates.has(name):
			continue
		var pos: Array = _read_placement_position(placement)
		if pos.size() < 3:
			return Vector3.INF
		return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
	return Vector3.INF


func _instance_structural_wrappers(layout_doc: Dictionary, module_to_scene: Dictionary, ship_root: Node3D) -> int:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return -1
	var rooms: Array = rooms_variant
	var count: int = 0
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			var scene_path: String = str(module_to_scene.get(module_id, ""))
			if scene_path.is_empty():
				continue
			if not ResourceLoader.exists(scene_path):
				push_error("wrapper scene missing for module %s: %s" % [module_id, scene_path])
				return -1
			var scene: Resource = load(scene_path)
			if scene == null:
				push_error("could not load wrapper scene for module %s: %s" % [module_id, scene_path])
				return -1
			if not (scene is PackedScene):
				push_error("wrapper scene is not PackedScene for module %s: %s" % [module_id, scene_path])
				return -1
			var instance: Node = (scene as PackedScene).instantiate()
			if not (instance is Node3D):
				push_error("wrapper instance is not Node3D for module %s: %s" % [module_id, scene_path])
				return -1
			var placement_pos: Array = _read_placement_position(placement)
			if placement_pos.size() < 3:
				continue
			var wrapper: Node3D = instance as Node3D
			wrapper.position = Vector3(float(placement_pos[0]), float(placement_pos[1]), float(placement_pos[2]))
			wrapper.rotation_degrees.y = float(placement.get("yaw_degrees", 0.0))
			wrapper.name = "%s_%s" % [room_id, str(placement.get("name", module_id))]
			ship_root.add_child(wrapper)
			count += 1
	return count


func _parse_prefixed_int(value: String, prefix: String) -> int:
	if not value.begins_with(prefix):
		return -2147483648
	var number_text: String = value.substr(prefix.length())
	if not number_text.is_valid_int():
		return -2147483648
	return int(number_text)


func _cell_signature_from_placement_name(placement_name: String) -> Array:
	var parts: PackedStringArray = placement_name.split("_")
	if parts.size() < 4:
		return []
	if parts[0] != "floor":
		return []
	var index: int = 2
	var deck: int = 0
	if index < parts.size() and String(parts[index]).begins_with("d"):
		deck = _parse_prefixed_int(String(parts[index]), "d")
		if deck == -2147483648:
			return []
		index += 1
	if index + 1 >= parts.size():
		return []
	var x: int = _parse_prefixed_int(String(parts[index]), "x")
	var z: int = _parse_prefixed_int(String(parts[index + 1]), "z")
	if x == -2147483648 or z == -2147483648:
		return []
	return [x, z, deck]


func _placement_matches_endpoint_cell(placement: Dictionary, endpoint: Array) -> bool:
	if endpoint.size() < 2:
		return false
	var module_id: String = str(placement.get("module_id", placement.get("module", "")))
	if not FLOOR_MODULES.has(module_id):
		return false
	var signature: Array = _cell_signature_from_placement_name(str(placement.get("name", "")))
	if signature.size() != 3:
		return false
	var endpoint_deck: int = 0
	if endpoint.size() >= 3:
		endpoint_deck = int(endpoint[2])
	return int(signature[0]) == int(endpoint[0]) and int(signature[1]) == int(endpoint[1]) and int(signature[2]) == endpoint_deck


func _cell_world_from_link_endpoint(link_doc: Dictionary, cell_key: String, room_key: String, layout_doc: Dictionary) -> Vector3:
	var endpoint_variant: Variant = link_doc.get(cell_key, [])
	if typeof(endpoint_variant) != TYPE_ARRAY:
		return Vector3.INF
	var endpoint: Array = endpoint_variant
	var room_id: String = str(link_doc.get(room_key, ""))
	if room_id.is_empty():
		return Vector3.INF
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	for room_variant in rooms_variant:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) != room_id:
			continue
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			return Vector3.INF
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			if not _placement_matches_endpoint_cell(placement, endpoint):
				continue
			var pos: Array = _read_placement_position(placement)
			if pos.size() < 3:
				return Vector3.INF
			return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
	return Vector3.INF


func _add_vertical_links(layout_doc: Dictionary, ship_root: Node3D) -> int:
	var links_variant: Variant = layout_doc.get("vertical_connections", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return 0
	var count: int = 0
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link_doc: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			push_warning("Skipping unresolved vertical link %s" % str(link_doc.get("id", count)))
			continue
		var nav_link: NavigationLink3D = NavigationLink3D.new()
		nav_link.name = "VerticalLink_%s" % str(link_doc.get("id", count))
		nav_link.bidirectional = true
		nav_link.start_position = from_pos
		nav_link.end_position = to_pos
		ship_root.add_child(nav_link)
		count += 1
	return count


func _build_navigation_region(rooms: Array, ship_root: Node3D) -> NavigationRegion3D:
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var floor_cell_count: int = 0
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			continue
		for placement_variant in placements_variant:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not FLOOR_MODULES.has(module_id):
				continue
			var pos: Array = _read_placement_position(placement)
			if pos.size() < 3:
				continue
			var cell_center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
			var half: float = CELL_SIZE * 0.5
			var faces: PackedVector3Array = PackedVector3Array([
				cell_center + Vector3(-half, 0.0, -half),
				cell_center + Vector3(half, 0.0, -half),
				cell_center + Vector3(half, 0.0, half),
				cell_center + Vector3(-half, 0.0, -half),
				cell_center + Vector3(half, 0.0, half),
				cell_center + Vector3(-half, 0.0, half),
			])
			source.add_faces(faces, Transform3D())
			floor_cell_count += 1

	if floor_cell_count == 0:
		push_error("no floor/corridor floor placements found for navigation mesh")
		return null

	var nav_mesh: NavigationMesh = NavigationMesh.new()
	NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, source)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "GameplayNavigationRegion"
	nav_region.navigation_mesh = nav_mesh
	ship_root.add_child(nav_region)
	return nav_region


func _read_placement_position(placement: Dictionary) -> Array:
	# Accept either `position` (legacy / seed-17 fixtures) or `world_position`
	# (golden coherent fixture). Return [] unless the value is an Array with
	# at least 3 numeric-ish values.
	if typeof(placement) != TYPE_DICTIONARY:
		return []
	var raw: Variant = placement.get("position", null)
	if raw == null:
		raw = placement.get("world_position", null)
	if typeof(raw) != TYPE_ARRAY:
		return []
	var arr: Array = raw
	if arr.size() < 3:
		return []
	for i in range(3):
		var v: Variant = arr[i]
		var t: int = typeof(v)
		if t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_STRING:
			return []
		if t == TYPE_STRING and not String(v).is_valid_float():
			return []
	return arr


func _room_center(rooms: Array, room_id: String) -> Vector3:
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) != room_id:
			continue
		var placements_variant: Variant = room.get("structural_placements", [])
		if typeof(placements_variant) != TYPE_ARRAY:
			break
		var placements: Array = placements_variant
		var total: Vector3 = Vector3.ZERO
		var count: int = 0
		for placement_variant in placements:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not FLOOR_MODULES.has(module_id):
				continue
			var pos: Array = _read_placement_position(placement)
			if pos.size() < 3:
				continue
			total += Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
			count += 1
		if count == 0:
			var origin_variant: Variant = room.get("origin", [0.0, 0.0, 0.0])
			if typeof(origin_variant) == TYPE_ARRAY:
				var origin: Array = origin_variant
				if origin.size() >= 3:
					return Vector3(float(origin[0]), float(origin[1]) + FLOOR_Y_OFFSET, float(origin[2]))
			return Vector3.INF
		return total / float(count)
	return Vector3.INF


# --- Public metadata accessors -------------------------------------------------
# These are read-only views onto the loaded layout_doc. They are intentionally
# defensive: bad inputs (missing key, wrong type, unknown room) return safe
# defaults instead of raising. They never mutate the loader state.


func get_room_center(room_id: String) -> Vector3:
	if room_id.is_empty():
		return Vector3.INF
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	return _room_center(rooms_variant, room_id)


func get_room_role(room_id: String) -> String:
	if room_id.is_empty():
		return ""
	var room: Dictionary = _find_room_in_layout(room_id)
	if room.is_empty():
		return ""
	return str(room.get("room_role", ""))


func get_room_deck(room_id: String) -> int:
	if room_id.is_empty():
		return -1
	var room: Dictionary = _find_room_in_layout(room_id)
	if room.is_empty():
		return -1
	return int(room.get("deck", -1))


func get_critical_path() -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = layout_doc.get("critical_path", [])
	if typeof(raw) != TYPE_ARRAY:
		raw = gameplay_doc.get("critical_path", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in (raw as Array):
		out.append(str(entry))
	return out


func get_room_links() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("room_links", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for link in (raw as Array):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		out.append((link as Dictionary).duplicate(true))
	return out


func get_blocked_links() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("blocked_links", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for link in (raw as Array):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		out.append((link as Dictionary).duplicate(true))
	return out


func get_landmark_specs() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("landmarks", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for landmark in (raw as Array):
		if typeof(landmark) != TYPE_DICTIONARY:
			continue
		out.append((landmark as Dictionary).duplicate(true))
	return out


func get_landmark_nodes() -> Array[Node3D]:
	return landmark_nodes.duplicate()


func get_blocked_route_nodes() -> Array[Node3D]:
	return blocked_route_nodes.duplicate()


func get_visible_vertical_transition_nodes() -> Array[Node3D]:
	return visible_vertical_transition_nodes.duplicate()


func get_breach_zone_markers() -> Array[Vector3]:
	return breach_zone_markers.duplicate()


func get_fire_zone_markers() -> Array[Vector3]:
	return fire_zone_markers.duplicate()


func _add_fire_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("fire_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		fire_zone_markers.append((from_pos + to_pos) * 0.5)
		fire_zone_specs.append(_normalize_zone_spec(zone))


# REQ-013 / ADR-0005: electrical-arc zone loader. Mirrors
# REQ-013 / ADR-0005 zone key normalization. The ADR names the shared
# zone identifier `zone_id` (docs/game/adr/0005-multi-hazard-architecture.md:63-68)
# so every hazard zone spec exposes a uniform `zone_id` key. The Alpha
# hand-authored layout fixtures use `id` (consistent with the
# `blocked_routes` and `vertical_connections` array entries) so we
# copy `id` -> `zone_id` here when the source spec only carries `id`.
# This preserves the existing fixture contract while aligning the
# loader output with the ADR-0005 HazardStateContract zone key.
# Existing spec fields (to_room, from_room, kind, rationale, etc.) are
# left untouched so consumer code that reads them keeps working.
func _normalize_zone_spec(zone: Dictionary) -> Dictionary:
	var out: Dictionary = zone.duplicate(true)
	if not out.has("zone_id") and out.has("id"):
		var id_value: Variant = out["id"]
		if id_value is String or id_value is StringName:
			var zone_id: String = str(id_value)
			if not zone_id.is_empty():
				out["zone_id"] = zone_id
	return out


# _add_fire_zone_markers() but only emits positions / specs for the
# hand-authored Alpha template markers. No fallback is injected because
# arc placement is template-specific (per hazard_type_3.md).
func _add_arc_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("arc_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		arc_zone_markers.append((from_pos + to_pos) * 0.5)
		arc_zone_specs.append(_normalize_zone_spec(zone))


func get_fire_zone_specs() -> Array:
	return fire_zone_specs.duplicate(true)


# REQ-013 / ADR-0005: electrical-arc zone contract. Mirror of the
# fire-zone accessors above: a list of world-space arc-zone midpoints
# resolved from the layout's `arc_zones` array, plus the full marker
# dictionaries for callers that need the to_room/cell context.
func get_arc_zone_markers() -> Array[Vector3]:
	return arc_zone_markers.duplicate()


func get_arc_zone_specs() -> Array:
	return arc_zone_specs.duplicate(true)


func _find_room_in_layout(room_id: String) -> Dictionary:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return {}
	return _find_room(rooms_variant, room_id)


# --- Coherence runtime marker nodes --------------------------------------------
# Build visual + (optionally) collidable marker nodes for landmarks, blocked
# routes, and visible vertical transitions. These are added under
# `structural_root` so they live in the same world transform as the structural
# wrappers. Marker names follow the convention
# `Landmark_<id>` / `BlockedRoute_<id>` / `VisibleVerticalTransition_<id>` so
# downstream capture/proof code can locate them by name.

const _LANDMARK_COLOR: Color = Color(0.15, 0.65, 1.0, 1.0)
const _BLOCKED_ROUTE_COLOR: Color = Color(0.85, 0.2, 0.18, 1.0)
const _VERTICAL_TRANSITION_COLOR: Color = Color(0.9, 0.68, 0.25, 1.0)
const _LANDMARK_SIZE: Vector3 = Vector3(0.8, 2.4, 0.8)
const _BLOCKED_ROUTE_SIZE: Vector3 = Vector3(3.8, 2.0, 0.45)
const _VERTICAL_TRANSITION_SIZE: Vector3 = Vector3(4.0, 0.45, 5.5)


func _add_coherence_runtime_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	_add_landmark_nodes(layout_doc, ship_root)
	_add_blocked_route_nodes(layout_doc, ship_root)
	_add_visible_vertical_transition_nodes(layout_doc, ship_root)
	_add_breach_zone_markers(layout_doc, ship_root)
	_add_fire_zone_markers(layout_doc, ship_root)
	_add_arc_zone_markers(layout_doc, ship_root)


func _add_landmark_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var landmarks_variant: Variant = layout_doc.get("landmarks", [])
	if typeof(landmarks_variant) != TYPE_ARRAY:
		return
	for landmark_variant in landmarks_variant:
		if typeof(landmark_variant) != TYPE_DICTIONARY:
			continue
		var landmark: Dictionary = landmark_variant
		var pos: Vector3 = _vec3_from_array(landmark.get("position", []), Vector3.INF)
		if pos == Vector3.INF:
			continue
		var node: Node3D = _make_marker_node(
			"Landmark_%s" % str(landmark.get("id", landmark_nodes.size())),
			pos,
			_LANDMARK_COLOR,
			_LANDMARK_SIZE,
			true
		)
		ship_root.add_child(node)
		landmark_nodes.append(node)


func _add_blocked_route_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("blocked_links", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		# Cell positions are the precise source of truth, but a coherent
		# fixture may declare blocked links at cells whose structural
		# placements live in another room. Fall back to the room center so
		# the marker still appears at a meaningful position rather than
		# being silently dropped.
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(link, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(link, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node(
			"BlockedRoute_%s" % str(link.get("id", blocked_route_nodes.size())),
			mid,
			_BLOCKED_ROUTE_COLOR,
			_BLOCKED_ROUTE_SIZE,
			true
		)
		ship_root.add_child(node)
		# `look_at` in Godot 4.6.2 prints "Node not inside tree" even after
		# `add_child` in headless script contexts (the deferred enter-tree
		# notification has not yet fired). Use `look_at_from_position` with
		# the current global transform so we get the same visual orientation
		# without the warning. Guard against coincident endpoints (zero-length
		# direction) which would print a transform error.
		if (to_pos - mid).length_squared() > 0.0001:
			node.look_at_from_position(mid, to_pos, Vector3.UP)
		blocked_route_nodes.append(node)


func _add_visible_vertical_transition_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("vertical_connections", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node(
			"VisibleVerticalTransition_%s" % str(link.get("id", visible_vertical_transition_nodes.size())),
			mid,
			_VERTICAL_TRANSITION_COLOR,
			_VERTICAL_TRANSITION_SIZE,
			true
		)
		ship_root.add_child(node)
		if (to_pos - mid).length_squared() > 0.0001:
			var up_vector: Vector3 = Vector3.UP
			# Vertical transitions often run purely along world Y; using
			# Vector3.UP as the up reference would make target/up colinear
			# and produce a warning. Pick a horizontal up reference so the
			# transition marker still orients to the ramp direction.
			if absf((to_pos - mid).normalized().dot(Vector3.UP)) > 0.999:
				up_vector = Vector3.FORWARD
			node.look_at_from_position(mid, to_pos, up_vector)
		visible_vertical_transition_nodes.append(node)


func _add_breach_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("breach_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		breach_zone_markers.append((from_pos + to_pos) * 0.5)


func _room_center_for_blocked_link(link: Dictionary, room_key: String, layout_doc: Dictionary) -> Vector3:
	# Fallback when `_cell_world_from_link_endpoint` cannot resolve the cell:
	# a coherent fixture may declare a blocked link at a cell that is the
	# "open end" of one of its rooms (e.g. a z-side cell with no floor
	# placement). Returning the room center keeps the marker inside the room
	# it belongs to so the visual still anchors correctly.
	var room_id: String = str(link.get(room_key, ""))
	if room_id.is_empty():
		return Vector3.INF
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	return _room_center(rooms_variant, room_id)


func _make_marker_node(node_name: String, world_position: Vector3, color: Color, size: Vector3, collidable: bool) -> Node3D:
	# Build the marker using local `position` (not `global_position`) and a
	# pre-computed basis. The caller is going to add this node as a child of
	# `structural_root`, which is at world origin, so local == world space.
	# Using local position + pre-baked basis avoids Godot 4.6.2 warnings about
	# `get_global_transform` / `look_at` on nodes that are not inside the tree.
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.position = world_position
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	mesh_instance.material_override = material
	mesh_instance.position.y = size.y * 0.5
	root.add_child(mesh_instance)
	if collidable:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "CollisionRoot"
		body.collision_layer = 1
		body.collision_mask = 1
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		shape_node.position.y = size.y * 0.5
		body.add_child(shape_node)
		root.add_child(body)
	return root


func _vec3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() < 3:
		return fallback
	var v0: Variant = array[0]
	var v1: Variant = array[1]
	var v2: Variant = array[2]
	var t0: int = typeof(v0)
	var t1: int = typeof(v1)
	var t2: int = typeof(v2)
	if t0 != TYPE_INT and t0 != TYPE_FLOAT:
		return fallback
	if t1 != TYPE_INT and t1 != TYPE_FLOAT:
		return fallback
	if t2 != TYPE_INT and t2 != TYPE_FLOAT:
		return fallback
	return Vector3(float(v0), float(v1), float(v2))
