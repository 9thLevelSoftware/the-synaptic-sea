extends RefCounted
class_name SeaGraph

## PKG-D6.2: pure strategic route graph over the Synaptic Sea marker field.
## Nodes are ship markers / hubs; edges carry travel cost (fuel + food) and biome band.
## Never touches the scene tree. Chart UI / travel controller consume summaries.

const MarkerGeneratorScript := preload("res://scripts/systems/marker_generator.gd")

const DEFAULT_FUEL_PER_UNIT: float = 0.08
const DEFAULT_FOOD_PER_UNIT: float = 0.03
const EXTRACTION_NODE_ID: String = "extraction"
const HUB_NODE_ID: String = "hub"

## node_id -> { id, kind, position:[x,y,z], biome_band, marker_id?, ship_type? }
var nodes: Dictionary = {}
## undirected edge key "a|b" -> { from, to, distance, fuel_cost, food_cost, biome_band }
var edges: Dictionary = {}
var world_seed: int = 0
var fuel_per_unit: float = DEFAULT_FUEL_PER_UNIT
var food_per_unit: float = DEFAULT_FOOD_PER_UNIT


func clear() -> void:
	nodes.clear()
	edges.clear()


func configure(config: Dictionary = {}) -> void:
	clear()
	world_seed = int(config.get("world_seed", 0))
	fuel_per_unit = maxf(0.0, float(config.get("fuel_per_unit", DEFAULT_FUEL_PER_UNIT)))
	food_per_unit = maxf(0.0, float(config.get("food_per_unit", DEFAULT_FOOD_PER_UNIT)))


## Build a strategic graph from hub + extraction + optional marker list.
## markers: Array of dicts or objects with marker_id, position (Vector3 or Array), ship_type, condition.
func build_from_markers(markers: Array, hub_position: Vector3 = Vector3.ZERO, extraction_position: Vector3 = Vector3(200, 0, 200)) -> int:
	clear()
	_add_node(HUB_NODE_ID, {
		"id": HUB_NODE_ID,
		"kind": "hub",
		"position": _pos_array(hub_position),
		"biome_band": 0,
	})
	_add_node(EXTRACTION_NODE_ID, {
		"id": EXTRACTION_NODE_ID,
		"kind": "extraction",
		"position": _pos_array(extraction_position),
		"biome_band": _biome_band_for_distance(hub_position.distance_to(extraction_position)),
	})
	for m in markers:
		var mid: String = ""
		var pos: Vector3 = Vector3.ZERO
		var ship_type: String = ""
		if typeof(m) == TYPE_DICTIONARY:
			var d: Dictionary = m
			mid = str(d.get("marker_id", d.get("id", "")))
			pos = _read_pos(d.get("position", Vector3.ZERO))
			ship_type = str(d.get("ship_type", ""))
		elif m != null:
			if m.get("marker_id") != null:
				mid = str(m.get("marker_id"))
			if m.get("position") != null:
				var p: Variant = m.get("position")
				if p is Vector3:
					pos = p as Vector3
				elif p is Array:
					pos = _read_pos(p)
			if m.get("ship_type") != null:
				ship_type = str(m.get("ship_type"))
		if mid.is_empty():
			continue
		var dist_hub: float = hub_position.distance_to(pos)
		_add_node(mid, {
			"id": mid,
			"kind": "marker",
			"position": _pos_array(pos),
			"biome_band": _biome_band_for_distance(dist_hub),
			"marker_id": mid,
			"ship_type": ship_type,
		})
	_connect_k_nearest(3)
	# Always ensure a path toward extraction: connect extraction to its nearest 2 nodes
	_connect_node_to_nearest(EXTRACTION_NODE_ID, 2)
	_connect_node_to_nearest(HUB_NODE_ID, 2)
	return nodes.size()


## Sample MarkerGenerator cells around the hub into a graph (deterministic).
func build_from_world_seed(p_world_seed: int, cell_radius: int = 1, hub_position: Vector3 = Vector3.ZERO) -> int:
	world_seed = p_world_seed
	var gen = MarkerGeneratorScript.new()
	var markers: Array = []
	for cx in range(-cell_radius, cell_radius + 1):
		for cy in range(-cell_radius, cell_radius + 1):
			var cell_markers: Array = gen.markers_for_cell(p_world_seed, Vector2i(cx, cy))
			for m in cell_markers:
				markers.append(m)
	var extract := Vector3(float(cell_radius + 1) * MarkerGeneratorScript.CELL_SIZE, 0.0, float(cell_radius + 1) * MarkerGeneratorScript.CELL_SIZE)
	return build_from_markers(markers, hub_position, extract)


func _add_node(id: String, data: Dictionary) -> void:
	nodes[id] = data.duplicate(true)


func _pos_array(pos: Vector3) -> Array:
	return [pos.x, pos.y, pos.z]


func _read_pos(v: Variant) -> Vector3:
	if v is Vector3:
		return v as Vector3
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func _node_pos(id: String) -> Vector3:
	if not nodes.has(id):
		return Vector3.INF
	return _read_pos((nodes[id] as Dictionary).get("position", []))


## Biome progression bands by distance from hub (0 near → 3 deep).
static func _biome_band_for_distance(distance: float) -> int:
	if distance < 40.0:
		return 0
	if distance < 100.0:
		return 1
	if distance < 200.0:
		return 2
	return 3


static func biome_band_name(band: int) -> String:
	match band:
		0:
			return "near_field"
		1:
			return "dead_fleet"
		2:
			return "breach_field"
		_:
			return "abyssal"


func _edge_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]


func _add_edge(a: String, b: String) -> void:
	if a == b or not nodes.has(a) or not nodes.has(b):
		return
	var key: String = _edge_key(a, b)
	if edges.has(key):
		return
	var pa: Vector3 = _node_pos(a)
	var pb: Vector3 = _node_pos(b)
	var dist: float = pa.distance_to(pb)
	var band_a: int = int((nodes[a] as Dictionary).get("biome_band", 0))
	var band_b: int = int((nodes[b] as Dictionary).get("biome_band", 0))
	var band: int = maxi(band_a, band_b)
	# Deeper bands cost more per unit
	var band_mult: float = 1.0 + 0.25 * float(band)
	edges[key] = {
		"from": a,
		"to": b,
		"distance": dist,
		"fuel_cost": dist * fuel_per_unit * band_mult,
		"food_cost": dist * food_per_unit * band_mult,
		"biome_band": band,
		"biome_name": biome_band_name(band),
	}


func _connect_k_nearest(k: int) -> void:
	var ids: Array = nodes.keys()
	for id in ids:
		_connect_node_to_nearest(str(id), k)


func _connect_node_to_nearest(id: String, k: int) -> void:
	if not nodes.has(id):
		return
	var origin: Vector3 = _node_pos(id)
	var scored: Array = []
	for other in nodes.keys():
		var oid: String = str(other)
		if oid == id:
			continue
		var d: float = origin.distance_to(_node_pos(oid))
		scored.append({"id": oid, "d": d})
	scored.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var n: int = mini(k, scored.size())
	for i in range(n):
		_add_edge(id, str(scored[i]["id"]))


func node_count() -> int:
	return nodes.size()


func edge_count() -> int:
	return edges.size()


func has_node(id: String) -> bool:
	return nodes.has(id)


func get_node(id: String) -> Dictionary:
	if not nodes.has(id):
		return {}
	return (nodes[id] as Dictionary).duplicate(true)


func get_edge(a: String, b: String) -> Dictionary:
	var key: String = _edge_key(a, b)
	if not edges.has(key):
		return {}
	return (edges[key] as Dictionary).duplicate(true)


func neighbors(id: String) -> Array:
	var out: Array = []
	for key in edges.keys():
		var e: Dictionary = edges[key]
		var a: String = str(e.get("from", ""))
		var b: String = str(e.get("to", ""))
		if a == id:
			out.append(b)
		elif b == id:
			out.append(a)
	out.sort()
	return out


## Dijkstra by fuel_cost. Returns { ok, path: Array[node_id], fuel, food, distance }.
func find_route(from_id: String, to_id: String) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"path": [],
		"fuel": 0.0,
		"food": 0.0,
		"distance": 0.0,
		"reason": "",
	}
	if not nodes.has(from_id) or not nodes.has(to_id):
		out["reason"] = "unknown_node"
		return out
	if from_id == to_id:
		out["ok"] = true
		out["path"] = [from_id]
		return out
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	for id in nodes.keys():
		dist[str(id)] = INF
	dist[from_id] = 0.0
	while true:
		var u: String = ""
		var best: float = INF
		for id in nodes.keys():
			var sid: String = str(id)
			if visited.has(sid):
				continue
			var d: float = float(dist.get(sid, INF))
			if d < best:
				best = d
				u = sid
		if u.is_empty() or best == INF:
			break
		if u == to_id:
			break
		visited[u] = true
		for v in neighbors(u):
			var e: Dictionary = get_edge(u, str(v))
			if e.is_empty():
				continue
			var alt: float = best + float(e.get("fuel_cost", 0.0))
			if alt < float(dist.get(str(v), INF)):
				dist[str(v)] = alt
				prev[str(v)] = u
	if float(dist.get(to_id, INF)) == INF:
		out["reason"] = "no_path"
		return out
	var path: Array = []
	var cur: String = to_id
	while cur != "":
		path.push_front(cur)
		if cur == from_id:
			break
		cur = str(prev.get(cur, ""))
		if path.size() > nodes.size() + 2:
			out["reason"] = "cycle"
			return out
	var fuel: float = 0.0
	var food: float = 0.0
	var distance: float = 0.0
	for i in range(path.size() - 1):
		var e2: Dictionary = get_edge(str(path[i]), str(path[i + 1]))
		fuel += float(e2.get("fuel_cost", 0.0))
		food += float(e2.get("food_cost", 0.0))
		distance += float(e2.get("distance", 0.0))
	out["ok"] = true
	out["path"] = path
	out["fuel"] = fuel
	out["food"] = food
	out["distance"] = distance
	return out


## Apply travel costs to a simple inventory/resources dict { fuel, food }.
## Returns { ok, fuel_left, food_left, reason }.
func apply_travel_cost(resources: Dictionary, route: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "fuel_left": 0.0, "food_left": 0.0, "reason": ""}
	if not bool(route.get("ok", false)):
		result["reason"] = "bad_route"
		return result
	var need_fuel: float = float(route.get("fuel", 0.0))
	var need_food: float = float(route.get("food", 0.0))
	var fuel: float = float(resources.get("fuel", 0.0))
	var food: float = float(resources.get("food", 0.0))
	if fuel < need_fuel:
		result["reason"] = "insufficient_fuel"
		result["fuel_left"] = fuel
		result["food_left"] = food
		return result
	if food < need_food:
		result["reason"] = "insufficient_food"
		result["fuel_left"] = fuel
		result["food_left"] = food
		return result
	resources["fuel"] = fuel - need_fuel
	resources["food"] = food - need_food
	result["ok"] = true
	result["fuel_left"] = float(resources["fuel"])
	result["food_left"] = float(resources["food"])
	return result


## Route toward extraction from hub (strategic goal).
func route_to_extraction(from_id: String = HUB_NODE_ID) -> Dictionary:
	return find_route(from_id, EXTRACTION_NODE_ID)


func get_summary() -> Dictionary:
	return {
		"schema": "sea_graph_v1",
		"world_seed": world_seed,
		"fuel_per_unit": fuel_per_unit,
		"food_per_unit": food_per_unit,
		"node_count": nodes.size(),
		"edge_count": edges.size(),
		"nodes": nodes.duplicate(true),
		"edges": edges.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	world_seed = int(summary.get("world_seed", world_seed))
	fuel_per_unit = maxf(0.0, float(summary.get("fuel_per_unit", fuel_per_unit)))
	food_per_unit = maxf(0.0, float(summary.get("food_per_unit", food_per_unit)))
	var n: Variant = summary.get("nodes", {})
	var e: Variant = summary.get("edges", {})
	if typeof(n) != TYPE_DICTIONARY or typeof(e) != TYPE_DICTIONARY:
		return false
	nodes = (n as Dictionary).duplicate(true)
	edges = (e as Dictionary).duplicate(true)
	return true
