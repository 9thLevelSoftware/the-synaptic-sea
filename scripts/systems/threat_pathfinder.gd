extends RefCounted
class_name ThreatPathfinder

## Pure A* over ShipNavGraph (ADR-0049). Returns world-space waypoints.
## Never touches the scene tree.

const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")

const MAX_EXPANSIONS: int = 4096

## Find a path from world start to world goal. Empty array if unreachable.
static func find_path(graph, start_world: Vector3, goal_world: Vector3) -> Array:
	if graph == null or graph.node_count() == 0:
		return []
	var start_id: String = graph.nearest_node(start_world)
	var goal_id: String = graph.nearest_node(goal_world)
	if start_id.is_empty() or goal_id.is_empty():
		return []
	if start_id == goal_id:
		return [graph.get_node_pos(goal_id)]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_id: 0.0}
	# open set as array of {id, f}; linear scan is fine for ship-scale graphs
	var open: Array = [{"id": start_id, "f": _heuristic(graph, start_id, goal_id)}]
	var closed: Dictionary = {}
	var expansions: int = 0
	while not open.is_empty() and expansions < MAX_EXPANSIONS:
		expansions += 1
		var best_i: int = 0
		var best_f: float = float((open[0] as Dictionary).get("f", INF))
		for i in range(1, open.size()):
			var f: float = float((open[i] as Dictionary).get("f", INF))
			if f < best_f:
				best_f = f
				best_i = i
		var current: String = str((open[best_i] as Dictionary).get("id", ""))
		open.remove_at(best_i)
		if current == goal_id:
			return _reconstruct(graph, came_from, current)
		if closed.has(current):
			continue
		closed[current] = true
		for neigh in graph.neighbors(current):
			if not (neigh is Dictionary):
				continue
			var nid: String = str((neigh as Dictionary).get("to", ""))
			var step: float = float((neigh as Dictionary).get("cost", 1.0))
			if nid.is_empty() or closed.has(nid):
				continue
			var tent: float = float(g_score.get(current, INF)) + step
			if tent < float(g_score.get(nid, INF)):
				came_from[nid] = current
				g_score[nid] = tent
				var f2: float = tent + _heuristic(graph, nid, goal_id)
				open.append({"id": nid, "f": f2})
	return []

## Farthest reachable node position from `from_world` (for FLEE).
static func farthest_point(graph, from_world: Vector3, avoid_world: Vector3) -> Vector3:
	if graph == null or graph.node_count() == 0:
		return from_world
	var start_id: String = graph.nearest_node(from_world)
	if start_id.is_empty():
		return from_world
	# Dijkstra distances from start; pick max distance, break ties by distance from avoid.
	var dist: Dictionary = {start_id: 0.0}
	var open: Array = [start_id]
	var visited: Dictionary = {}
	while not open.is_empty():
		var cur: String = str(open.pop_front())
		if visited.has(cur):
			continue
		visited[cur] = true
		for neigh in graph.neighbors(cur):
			if not (neigh is Dictionary):
				continue
			var nid: String = str((neigh as Dictionary).get("to", ""))
			var step: float = float((neigh as Dictionary).get("cost", 1.0))
			if nid.is_empty():
				continue
			var tent: float = float(dist.get(cur, INF)) + step
			if tent < float(dist.get(nid, INF)):
				dist[nid] = tent
				open.append(nid)
	var best_id: String = start_id
	var best_score: float = -1.0
	for nid in dist:
		var d_path: float = float(dist[nid])
		var p: Vector3 = graph.get_node_pos(str(nid))
		var d_avoid: float = p.distance_to(avoid_world)
		var score: float = d_path * 0.35 + d_avoid
		if score > best_score:
			best_score = score
			best_id = str(nid)
	return graph.get_node_pos(best_id)

## Advance along waypoints by `speed * delta`. Mutates path_index.
## Returns new world position.
static func step_along_path(path: Array, path_index: int, current: Vector3, speed: float, delta: float) -> Dictionary:
	var idx: int = path_index
	var pos: Vector3 = current
	var remaining: float = maxf(0.0, speed) * maxf(0.0, delta)
	if path.is_empty() or remaining <= 0.0:
		return {"position": pos, "path_index": idx, "arrived": path.is_empty()}
	while remaining > 0.0 and idx < path.size():
		var wp: Vector3 = _as_vec3(path[idx], pos)
		var dist: float = pos.distance_to(wp)
		if dist <= 0.05:
			pos = wp
			idx += 1
			continue
		if remaining >= dist:
			pos = wp
			remaining -= dist
			idx += 1
		else:
			pos = pos.move_toward(wp, remaining)
			remaining = 0.0
	return {
		"position": pos,
		"path_index": idx,
		"arrived": idx >= path.size(),
	}

static func _as_vec3(v: Variant, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v as Vector3
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback

static func _heuristic(graph, a: String, b: String) -> float:
	var pa: Vector3 = graph.get_node_pos(a)
	var pb: Vector3 = graph.get_node_pos(b)
	if pa == Vector3.INF or pb == Vector3.INF:
		return 0.0
	return pa.distance_to(pb) / maxf(0.1, float(graph.cell_size))

static func _reconstruct(graph, came_from: Dictionary, current: String) -> Array:
	var chain: Array = [current]
	while came_from.has(current):
		current = str(came_from[current])
		chain.push_front(current)
	var waypoints: Array = []
	for id in chain:
		var p: Vector3 = graph.get_node_pos(str(id))
		if p != Vector3.INF:
			waypoints.append(p)
	return waypoints
