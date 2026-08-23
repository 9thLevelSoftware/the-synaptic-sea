extends RefCounted
class_name WalkabilityContract

## Player-capsule and compiler-edge walkability numbers (REQ-WALK-001).
## Enclosure flood is non-SOLID; standing-play is OPEN/DOOR/HATCH only.

const CompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")

const PLAYER_RADIUS_M: float = 0.35
const PLAYER_HEIGHT_M: float = 1.6
const CLEARANCE_MARGIN_M: float = 0.10
const STANDING_OPENING_WIDTH_M: float = 0.80
const STANDING_OPENING_HEIGHT_M: float = 1.70
const SLAB_THICKNESS_M: float = 0.20
const DOOR_OPENING_WIDTH_M: float = 1.20
const CAPSULE_FLOOR_OFFSET_M: float = 0.12
const WALL_HEIGHT_M: float = 3.0
const DOOR_HEIGHT_M: float = 3.2
const WALL_HALF_SPAN_M: float = 2.0
const HEADER_CLEARANCE_M: float = 0.10
const SLAB_INTERIOR_T_EPS: float = 0.05
## Live wrapper proxies (REQ-DECAY-002). Inner post faces at ±0.6 m = opening 1.20 m.
const DOOR_POST_WIDTH_M: float = 1.4
const DOOR_POST_OFFSET_X_M: float = 1.3
const DOOR_HEADER_HEIGHT_M: float = 1.0
const DOOR_HEADER_BOTTOM_Y_M: float = 2.2

const STANDING_KINDS: Array[String] = ["OPEN", "DOOR", "HATCH"]


static func enclosure_passable(kind: String) -> bool:
	return kind.to_upper() != "SOLID"


static func standing_passable(kind: String) -> bool:
	return STANDING_KINDS.has(kind.to_upper())


static func edge_kind(edge: Dictionary) -> String:
	return str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()


static func occupancy_cell_key(record: Dictionary, occupancy_key: String) -> String:
	var declared: String = str(record.get("cell_key", occupancy_key))
	return declared if not declared.is_empty() else str(occupancy_key)


static func occupancy_deck(record: Dictionary) -> int:
	return int(record.get("deck", 0))


static func occupancy_cell(record: Dictionary) -> Vector2i:
	return _read_cell_xz(record.get("cell", null))


static func occupancy_world_position(record: Dictionary) -> Vector3:
	var raw: Variant = record.get("position", record.get("world_position", null))
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return CompilerScript.cell_world_position(occupancy_deck(record), occupancy_cell(record))


static func occupancy_room_id(record: Dictionary) -> String:
	return str(record.get("room_id", ""))


static func build_adjacency(
		occupancy: Dictionary,
		edges: Dictionary,
		topology: Dictionary,
		standing: bool) -> Dictionary:
	var adjacency: Dictionary = {}
	for occupancy_key_variant in occupancy.keys():
		adjacency[str(occupancy_key_variant)] = []
	for edge_variant in edges.values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = edge_kind(edge)
		if standing:
			if not standing_passable(kind):
				continue
		elif not enclosure_passable(kind):
			continue
		var pair: PackedStringArray = _occupied_edge_keys(edge, occupancy, topology)
		if pair.size() != 2:
			continue
		_link(adjacency, pair[0], pair[1])
	_add_vertical_links(adjacency, occupancy, topology)
	if standing:
		_overlay_blocked_links(adjacency, occupancy, topology)
	return adjacency


static func flood_visited(adjacency: Dictionary, start_key: String) -> Dictionary:
	var visited: Dictionary = {}
	if start_key.is_empty() or not adjacency.has(start_key):
		return visited
	var queue: Array[String] = [start_key]
	visited[start_key] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_variant in (adjacency.get(current, []) as Array):
			var neighbor: String = str(neighbor_variant)
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited


static func reachable(adjacency: Dictionary, start_key: String, goal_key: String) -> bool:
	if start_key == goal_key and adjacency.has(start_key):
		return true
	return flood_visited(adjacency, start_key).has(goal_key)


static func rooms_reachable(
		adjacency: Dictionary,
		occupancy: Dictionary,
		start_room: String,
		goal_room: String) -> bool:
	var start_cells: Array[String] = room_cell_keys(occupancy, start_room)
	var goal_lookup: Dictionary = {}
	for goal_key in room_cell_keys(occupancy, goal_room):
		goal_lookup[goal_key] = true
	if start_cells.is_empty() or goal_lookup.is_empty():
		return false
	for start_key in start_cells:
		var visited: Dictionary = flood_visited(adjacency, start_key)
		for goal_key in goal_lookup.keys():
			if visited.has(str(goal_key)):
				return true
	return false


static func standing_path_keys(
		adjacency: Dictionary,
		occupancy: Dictionary,
		start_room: String,
		goal_room: String) -> Array[String]:
	var start_cells: Array[String] = room_cell_keys(occupancy, start_room)
	var goal_lookup: Dictionary = {}
	for goal_key in room_cell_keys(occupancy, goal_room):
		goal_lookup[goal_key] = true
	if start_cells.is_empty() or goal_lookup.is_empty():
		return []
	for start_key in start_cells:
		var came_from: Dictionary = {start_key: start_key}
		var queue: Array[String] = [start_key]
		var found: String = ""
		while not queue.is_empty():
			var current: String = queue.pop_front()
			if goal_lookup.has(current):
				found = current
				break
			for neighbor_variant in (adjacency.get(current, []) as Array):
				var neighbor: String = str(neighbor_variant)
				if came_from.has(neighbor):
					continue
				came_from[neighbor] = current
				queue.append(neighbor)
		if found.is_empty():
			continue
		var path: Array[String] = []
		var cursor: String = found
		while true:
			path.push_front(cursor)
			if cursor == start_key:
				break
			cursor = str(came_from.get(cursor, ""))
			if cursor.is_empty():
				return []
		return path
	return []


static func room_cell_keys(occupancy: Dictionary, room_id: String) -> Array[String]:
	var cells: Array[String] = []
	if room_id.is_empty():
		return cells
	for occupancy_key_variant in occupancy.keys():
		var occupancy_key: String = str(occupancy_key_variant)
		var record_variant: Variant = occupancy[occupancy_key_variant]
		if not (record_variant is Dictionary):
			continue
		if occupancy_room_id(record_variant as Dictionary) == room_id:
			cells.append(occupancy_key)
	return cells


static func floor_cell_keys(plan: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var floors_variant: Variant = plan.get("floor_placements", [])
	if not (floors_variant is Array):
		return keys
	for floor_variant in (floors_variant as Array):
		if not (floor_variant is Dictionary):
			continue
		var cell_key_value: String = str((floor_variant as Dictionary).get("cell_key", ""))
		if not cell_key_value.is_empty():
			keys[cell_key_value] = true
	return keys


static func capsule_hits_solid_slab(edge: Dictionary, occupancy: Dictionary) -> bool:
	return _capsule_enters_extruded_slab(edge, occupancy, SLAB_THICKNESS_M, Vector3.INF)


## Fail-closed fixture: a zero-thickness plane at the edge must not count as a wall hit.
static func capsule_hits_zero_thickness_fixture(edge: Dictionary, occupancy: Dictionary) -> bool:
	return _capsule_enters_extruded_slab(edge, occupancy, 0.0, Vector3.INF)


## Fail-closed fixture: a 0.20 m AABB at the source cell center must not count as the wall.
static func capsule_hits_cell_center_aabb_fixture(edge: Dictionary, occupancy: Dictionary) -> bool:
	var sweep: Dictionary = _capsule_sweep_segment(edge, occupancy)
	if not bool(sweep.get("ok", false)):
		return false
	return _capsule_enters_extruded_slab(edge, occupancy, SLAB_THICKNESS_M, sweep["from"] as Vector3)


static func capsule_passes_door_opening(edge: Dictionary, occupancy: Dictionary) -> bool:
	var sweep: Dictionary = _capsule_sweep_segment(edge, occupancy)
	if not bool(sweep.get("ok", false)):
		return false
	var from_local: Vector3 = _world_to_local(
		sweep["from"] as Vector3, sweep["origin"] as Vector3, float(sweep["yaw"]))
	var to_local: Vector3 = _world_to_local(
		sweep["to"] as Vector3, sweep["origin"] as Vector3, float(sweep["yaw"]))
	var half_w: float = DOOR_OPENING_WIDTH_M * 0.5
	var half_t: float = SLAB_THICKNESS_M * 0.5
	var header_min_y: float = STANDING_OPENING_HEIGHT_M + HEADER_CLEARANCE_M
	var boxes: Array[Dictionary] = [
		{"min": Vector3(-WALL_HALF_SPAN_M, 0.0, -half_t),
			"max": Vector3(-half_w, DOOR_HEIGHT_M, half_t)},
		{"min": Vector3(half_w, 0.0, -half_t),
			"max": Vector3(WALL_HALF_SPAN_M, DOOR_HEIGHT_M, half_t)},
		{"min": Vector3(-WALL_HALF_SPAN_M, header_min_y, -half_t),
			"max": Vector3(WALL_HALF_SPAN_M, DOOR_HEIGHT_M, half_t)},
	]
	if edge_kind(edge) == "LOCKED":
		boxes.append({
			"min": Vector3(-half_w, 0.0, -half_t),
			"max": Vector3(half_w, header_min_y, half_t),
		})
	for box_variant in boxes:
		var box: Dictionary = box_variant
		if _horizontal_capsule_hits_aabb_local(
			from_local,
			to_local,
			box["min"] as Vector3,
			box["max"] as Vector3):
			return false
	if edge_kind(edge) == "LOCKED":
		return false
	return _segment_crosses_opening_plane(from_local, to_local, half_w, STANDING_OPENING_HEIGHT_M)


static func standing_void_reason(
		plan: Dictionary,
		occupancy: Dictionary,
		path_keys: Array[String],
		topology: Dictionary = {}) -> String:
	var floors: Dictionary = floor_cell_keys(plan)
	for path_key in path_keys:
		if not occupancy.has(path_key):
			return path_key
		if not floors.has(path_key):
			return path_key
		var record_variant: Variant = occupancy[path_key]
		if not (record_variant is Dictionary):
			return path_key
		var record: Dictionary = record_variant
		var deck: int = occupancy_deck(record)
		var cell: Vector2i = occupancy_cell(record)
		for direction in CompilerScript.DIRECTIONS.keys():
			var neighbor: Vector2i = cell + (CompilerScript.DIRECTIONS[direction] as Vector2i)
			var neighbor_key: String = CompilerScript.cell_key(deck, neighbor)
			if occupancy.has(neighbor_key):
				continue
			if _standing_edge_between(plan, path_key, neighbor_key, deck, topology):
				return neighbor_key
	return ""


static func _standing_edge_between(
		plan: Dictionary,
		first_key: String,
		second_key: String,
		deck: int,
		topology: Dictionary = {}) -> bool:
	var edges_variant: Variant = plan.get("edges", {})
	if not (edges_variant is Dictionary):
		return false
	for edge_variant in (edges_variant as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if not standing_passable(edge_kind(edge)):
			continue
		if int(edge.get("deck", deck)) != deck:
			continue
		var cells: Array = _flood_endpoint_cells(edge, topology)
		if cells.size() < 2:
			continue
		var a: Dictionary = _cell_key_from_value(cells[0], deck)
		var b: Dictionary = _cell_key_from_value(cells[1], deck)
		if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
			continue
		var a_key: String = str(a["key"])
		var b_key: String = str(b["key"])
		if (a_key == first_key and b_key == second_key) or (a_key == second_key and b_key == first_key):
			return true
	return false


static func _occupied_edge_keys(edge: Dictionary, occupancy: Dictionary, topology: Dictionary = {}) -> PackedStringArray:
	var deck: int = int(edge.get("deck", -1))
	var cells: Array = _flood_endpoint_cells(edge, topology)
	if cells.size() < 2:
		return PackedStringArray()
	var first: Dictionary = _cell_key_from_value(cells[0], deck)
	var second: Dictionary = _cell_key_from_value(cells[1], deck)
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return PackedStringArray()
	var first_key: String = str(first["key"])
	var second_key: String = str(second["key"])
	if not occupancy.has(first_key) or not occupancy.has(second_key):
		return PackedStringArray()
	return PackedStringArray([first_key, second_key])


static func _flood_endpoint_cells(edge: Dictionary, topology: Dictionary) -> Array:
	var lf: Variant = edge.get("logical_from_cell", null)
	var lt: Variant = edge.get("logical_to_cell", null)
	if lf != null and lt != null:
		return [lf, lt]
	if bool(edge.get("logical_boundary", false)) or bool(edge.get("portal", false)):
		var portals_v: Variant = topology.get("portals", [])
		if portals_v is Array:
			var edge_key_value: String = str(edge.get("key", edge.get("edge_key", "")))
			var edge_cell: Variant = edge.get("cell", null)
			var direction: String = str(edge.get("direction", ""))
			for portal_v in (portals_v as Array):
				if not (portal_v is Dictionary):
					continue
				var portal: Dictionary = portal_v
				if not bool(portal.get("logical_boundary", false)):
					continue
				if not edge_key_value.is_empty() and str(portal.get("edge_key", "")) == edge_key_value:
					return [portal.get("from_cell", null), portal.get("to_cell", null)]
				var portal_dir: String = str(portal.get("edge_direction", portal.get("direction", "")))
				if portal_dir == direction:
					var pec: Vector2i = _read_cell_xz(portal.get("edge_cell", null))
					var ecell: Vector2i = _read_cell_xz(edge_cell)
					if pec != Vector2i(-99999, -99999) and pec == ecell:
						return [portal.get("from_cell", null), portal.get("to_cell", null)]
	var source_cells: Variant = edge.get("source_cells", [])
	if source_cells is Array:
		return source_cells as Array
	return []


static func _overlay_blocked_links(adjacency: Dictionary, occupancy: Dictionary, topology: Dictionary) -> void:
	var blocked_v: Variant = topology.get("blocked_links", [])
	if not (blocked_v is Array):
		return
	var room_decks: Dictionary = _room_decks(topology)
	for link_v in (blocked_v as Array):
		if not (link_v is Dictionary):
			continue
		var link: Dictionary = link_v
		var from_deck: int = int(room_decks.get(str(link.get("from_room", "")), int(link.get("from_deck", 0))))
		var to_deck: int = int(room_decks.get(str(link.get("to_room", "")), int(link.get("to_deck", 0))))
		var a: Dictionary = _cell_key_from_value(link.get("from_cell", null), from_deck)
		var b: Dictionary = _cell_key_from_value(link.get("to_cell", null), to_deck)
		if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
			continue
		_unlink(adjacency, str(a["key"]), str(b["key"]))


static func _add_vertical_links(adjacency: Dictionary, occupancy: Dictionary, topology: Dictionary) -> void:
	var vertical_variant: Variant = topology.get("vertical_connections", [])
	if not (vertical_variant is Array):
		return
	var room_decks: Dictionary = _room_decks(topology)
	for link_variant in (vertical_variant as Array):
		if not (link_variant is Dictionary):
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_deck: int = int(room_decks.get(from_room, int(link.get("from_deck", -1))))
		var to_deck: int = int(room_decks.get(to_room, int(link.get("to_deck", -1))))
		var from_info: Dictionary = _cell_key_from_value(link.get("from_cell", null), from_deck)
		var to_info: Dictionary = _cell_key_from_value(link.get("to_cell", null), to_deck)
		if not bool(from_info.get("ok", false)) or not bool(to_info.get("ok", false)):
			continue
		var from_key: String = str(from_info["key"])
		var to_key: String = str(to_info["key"])
		if occupancy.has(from_key) and occupancy.has(to_key):
			_link(adjacency, from_key, to_key)


static func _link(adjacency: Dictionary, a: String, b: String) -> void:
	if not adjacency.has(a) or not adjacency.has(b) or a == b:
		return
	(adjacency[a] as Array).append(b)
	(adjacency[b] as Array).append(a)


static func _unlink(adjacency: Dictionary, a: String, b: String) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	if adjacency.has(a):
		(adjacency[a] as Array).erase(b)
	if adjacency.has(b):
		(adjacency[b] as Array).erase(a)


static func _capsule_sweep_segment(edge: Dictionary, occupancy: Dictionary) -> Dictionary:
	var source_cells: Variant = edge.get("source_cells", [])
	if not (source_cells is Array) or (source_cells as Array).size() < 2:
		return {"ok": false}
	var deck: int = int(edge.get("deck", 0))
	var from_pos: Vector3 = _cell_world_from_value((source_cells as Array)[0], deck, occupancy)
	var to_pos: Vector3 = _cell_world_from_value((source_cells as Array)[1], deck, occupancy)
	if from_pos == Vector3.INF or to_pos == Vector3.INF:
		return {"ok": false}
	from_pos.y += CAPSULE_FLOOR_OFFSET_M
	to_pos.y += CAPSULE_FLOOR_OFFSET_M
	var origin: Vector3 = _edge_origin(edge)
	var yaw: float = float(edge.get("yaw_degrees", 0.0))
	return {"ok": true, "from": from_pos, "to": to_pos, "origin": origin, "yaw": yaw}


static func _cell_world_from_value(value: Variant, default_deck: int, occupancy: Dictionary) -> Vector3:
	var info: Dictionary = _cell_key_from_value(value, default_deck)
	if not bool(info.get("ok", false)):
		return Vector3.INF
	var key: String = str(info["key"])
	if occupancy.has(key) and occupancy[key] is Dictionary:
		return occupancy_world_position(occupancy[key] as Dictionary)
	return CompilerScript.cell_world_position(int(info["deck"]), info["cell"])


static func _edge_origin(edge: Dictionary) -> Vector3:
	var raw: Variant = edge.get("position", null)
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	var deck: int = int(edge.get("deck", 0))
	var cell: Vector2i = _read_cell_xz(edge.get("cell", null))
	var direction: String = str(edge.get("direction", "south"))
	return CompilerScript.edge_world_position(deck, cell, direction)


static func _capsule_enters_extruded_slab(
		edge: Dictionary,
		occupancy: Dictionary,
		thickness_m: float,
		origin_override: Vector3) -> bool:
	var sweep: Dictionary = _capsule_sweep_segment(edge, occupancy)
	if not bool(sweep.get("ok", false)):
		return false
	var origin: Vector3 = origin_override
	if origin == Vector3.INF:
		origin = sweep["origin"] as Vector3
	var from_local: Vector3 = _world_to_local(sweep["from"] as Vector3, origin, float(sweep["yaw"]))
	var to_local: Vector3 = _world_to_local(sweep["to"] as Vector3, origin, float(sweep["yaw"]))
	var slab: Dictionary = _slab_local_box(WALL_HEIGHT_M, thickness_m)
	if not _capsule_y_overlaps_aabb(from_local, to_local, slab["min"] as Vector3, slab["max"] as Vector3):
		return false
	var interval: Vector2 = _segment_aabb2_interval(
		Vector2(from_local.x, from_local.z),
		Vector2(to_local.x, to_local.z),
		Vector2((slab["min"] as Vector3).x, (slab["min"] as Vector3).z),
		Vector2((slab["max"] as Vector3).x, (slab["max"] as Vector3).z))
	if interval.x > interval.y:
		return false
	var path_len: float = Vector2(from_local.x, from_local.z).distance_to(Vector2(to_local.x, to_local.z))
	var overlap_m: float = (interval.y - interval.x) * path_len
	var min_overlap: float = thickness_m * 0.5 if thickness_m > 0.0 else 0.05
	if overlap_m < min_overlap:
		return false
	return interval.x < (1.0 - SLAB_INTERIOR_T_EPS) and interval.y > SLAB_INTERIOR_T_EPS


static func _slab_local_box(height_m: float, thickness_m: float = SLAB_THICKNESS_M) -> Dictionary:
	var half_t: float = thickness_m * 0.5
	return {
		"min": Vector3(-WALL_HALF_SPAN_M, 0.0, -half_t),
		"max": Vector3(WALL_HALF_SPAN_M, height_m, half_t),
	}


static func _horizontal_capsule_hits_local_box(
		from_world: Vector3,
		to_world: Vector3,
		origin: Vector3,
		yaw_degrees: float,
		box_min: Vector3,
		box_max: Vector3) -> bool:
	var from_local: Vector3 = _world_to_local(from_world, origin, yaw_degrees)
	var to_local: Vector3 = _world_to_local(to_world, origin, yaw_degrees)
	return _horizontal_capsule_hits_aabb_local(from_local, to_local, box_min, box_max)


static func _capsule_y_overlaps_aabb(
		from_local: Vector3,
		to_local: Vector3,
		box_min: Vector3,
		box_max: Vector3) -> bool:
	var cap_y0: float = minf(from_local.y, to_local.y)
	var cap_y1: float = cap_y0 + PLAYER_HEIGHT_M
	return cap_y1 > box_min.y and cap_y0 < box_max.y


static func _horizontal_capsule_hits_aabb_local(
		from_local: Vector3,
		to_local: Vector3,
		box_min: Vector3,
		box_max: Vector3) -> bool:
	if not _capsule_y_overlaps_aabb(from_local, to_local, box_min, box_max):
		return false
	var expanded_min := Vector2(box_min.x - PLAYER_RADIUS_M, box_min.z - PLAYER_RADIUS_M)
	var expanded_max := Vector2(box_max.x + PLAYER_RADIUS_M, box_max.z + PLAYER_RADIUS_M)
	return _segment_hits_aabb2(
		Vector2(from_local.x, from_local.z),
		Vector2(to_local.x, to_local.z),
		expanded_min,
		expanded_max)


static func _segment_crosses_opening_plane(
		from_local: Vector3,
		to_local: Vector3,
		half_w: float,
		opening_top: float) -> bool:
	var z0: float = from_local.z
	var z1: float = to_local.z
	if (z0 < 0.0 and z1 < 0.0) or (z0 > 0.0 and z1 > 0.0):
		return false
	var denom: float = z1 - z0
	var t: float = 0.5 if is_zero_approx(denom) else (-z0 / denom)
	if t < 0.0 or t > 1.0:
		return false
	var hit: Vector3 = from_local.lerp(to_local, t)
	if absf(hit.x) > half_w - PLAYER_RADIUS_M:
		return false
	# Named opening is measured from floor Y=0; floor-plate offset is not counted.
	var height_from_floor: float = hit.y - CAPSULE_FLOOR_OFFSET_M + PLAYER_HEIGHT_M
	return hit.y >= 0.0 and height_from_floor <= opening_top + 0.0001


static func _world_to_local(world: Vector3, origin: Vector3, yaw_degrees: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw_degrees), 0.0))
	return basis.inverse() * (world - origin)


static func _segment_hits_aabb2(p0: Vector2, p1: Vector2, box_min: Vector2, box_max: Vector2) -> bool:
	var interval: Vector2 = _segment_aabb2_interval(p0, p1, box_min, box_max)
	return interval.x <= interval.y


static func _segment_aabb2_interval(p0: Vector2, p1: Vector2, box_min: Vector2, box_max: Vector2) -> Vector2:
	var dir: Vector2 = p1 - p0
	var t_min: float = 0.0
	var t_max: float = 1.0
	for axis in range(2):
		var origin_a: float = p0.x if axis == 0 else p0.y
		var dir_a: float = dir.x if axis == 0 else dir.y
		var min_a: float = box_min.x if axis == 0 else box_min.y
		var max_a: float = box_max.x if axis == 0 else box_max.y
		if is_zero_approx(dir_a):
			if origin_a < min_a or origin_a > max_a:
				return Vector2(1.0, 0.0)
			continue
		var t1: float = (min_a - origin_a) / dir_a
		var t2: float = (max_a - origin_a) / dir_a
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return Vector2(1.0, 0.0)
	return Vector2(t_min, t_max)


static func _point_in_aabb2(point: Vector2, box_min: Vector2, box_max: Vector2) -> bool:
	return point.x >= box_min.x and point.x <= box_max.x and point.y >= box_min.y and point.y <= box_max.y


static func _cell_key_from_value(value: Variant, default_deck: int) -> Dictionary:
	var cell: Vector2i = _read_cell_xz(value)
	var deck: int = default_deck
	if value is Array and (value as Array).size() >= 3:
		deck = int((value as Array)[2])
	if deck < 0:
		return {"ok": false}
	if cell == Vector2i(-99999, -99999):
		return {"ok": false}
	return {"ok": true, "key": CompilerScript.cell_key(deck, cell), "cell": cell, "deck": deck}


static func _read_cell_xz(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	if value is String:
		var text: String = str(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var pieces: PackedStringArray = text.split(",")
		if pieces.size() >= 2:
			return Vector2i(int(pieces[0].strip_edges()), int(pieces[1].strip_edges()))
	return Vector2i(-99999, -99999)


static func _room_decks(topology: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rooms_variant: Variant = topology.get("rooms", [])
	if not (rooms_variant is Array):
		return out
	for room_variant in (rooms_variant as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		if not room_id.is_empty():
			out[room_id] = int(room.get("deck", 0))
	return out
