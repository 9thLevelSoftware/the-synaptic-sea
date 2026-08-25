extends RefCounted
class_name ShipNavGraph

## Pure walkable-cell graph built from a ship layout (ADR-0049).
## Nodes are floor cell centers; edges are 4-connected (same deck) plus optional
## vertical edges when cells stack. Dynamic blockers raise edge cost or cut edges.
## Never touches the scene tree.

const DEFAULT_CELL_SIZE: float = 4.0
const DEFAULT_DECK_HEIGHT: float = 4.0
const BLOCKED_COST: float = 1.0e9
const FIRE_COST_MULT: float = 6.0

const FLOOR_MODULE_PREFIXES: Array[String] = [
	"floor_", "corridor_floor", "ramp_",
]

var cell_size: float = DEFAULT_CELL_SIZE
var deck_height: float = DEFAULT_DECK_HEIGHT
## node_id -> { "pos": Vector3, "room_id": String, "key": String }
var nodes: Dictionary = {}
## undirected edge key "a|b" -> cost (float)
var edges: Dictionary = {}
## base edges frozen after build (for re-applying dynamic costs)
var _base_edges: Dictionary = {}
var dirty: bool = true

func clear() -> void:
	nodes.clear()
	edges.clear()
	_base_edges.clear()
	dirty = true

## Build graph from a layout.json-shaped dictionary (rooms + structural_placements).
func build_from_layout(layout: Dictionary) -> int:
	clear()
	cell_size = maxf(0.1, float(layout.get("cell_size", DEFAULT_CELL_SIZE)))
	deck_height = maxf(0.1, float(layout.get("deck_height", DEFAULT_DECK_HEIGHT)))
	var rooms_v: Variant = layout.get("rooms", [])
	if not (rooms_v is Array):
		return 0
	for room_variant in (rooms_v as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		var placements_v: Variant = room.get("structural_placements", [])
		if not (placements_v is Array):
			continue
		for placement_variant in (placements_v as Array):
			if not (placement_variant is Dictionary):
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if not _is_floor_module(module_id):
				continue
			var pos: Vector3 = _read_world_position(placement)
			if pos == Vector3.INF:
				continue
			# Snap to cell grid so neighbors match cleanly.
			var key: String = _key_for_pos(pos)
			if nodes.has(key):
				continue
			nodes[key] = {
				"pos": _snap_pos(pos),
				"room_id": room_id,
				"key": key,
			}
	var structural_plan_variant: Variant = layout.get("structural_plan", null)
	if structural_plan_variant is Dictionary and not (structural_plan_variant as Dictionary).is_empty():
		_connect_structural_edges(structural_plan_variant as Dictionary)
		_connect_vertical_neighbors()
	else:
		_connect_orthogonal_neighbors()
	_base_edges = edges.duplicate(true)
	dirty = false
	return nodes.size()

func node_count() -> int:
	return nodes.size()

func edge_count() -> int:
	return edges.size()

func has_node(node_id: String) -> bool:
	return nodes.has(node_id)

func get_node_pos(node_id: String) -> Vector3:
	if not nodes.has(node_id):
		return Vector3.INF
	return (nodes[node_id] as Dictionary).get("pos", Vector3.INF) as Vector3

func get_node_room(node_id: String) -> String:
	if not nodes.has(node_id):
		return ""
	return str((nodes[node_id] as Dictionary).get("room_id", ""))

## Nearest graph node to a world position (empty string if graph empty).
func nearest_node(world_pos: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for key in nodes:
		var p: Vector3 = get_node_pos(str(key))
		var d: float = p.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = str(key)
	return best

func neighbors(node_id: String) -> Array:
	var out: Array = []
	if not nodes.has(node_id):
		return out
	for edge_key in edges:
		var cost: float = float(edges[edge_key])
		if cost >= BLOCKED_COST:
			continue
		var parts: PackedStringArray = str(edge_key).split("|")
		if parts.size() != 2:
			continue
		if parts[0] == node_id:
			out.append({"to": parts[1], "cost": cost})
		elif parts[1] == node_id:
			out.append({"to": parts[0], "cost": cost})
	return out

func edge_cost(a: String, b: String) -> float:
	var k: String = _edge_key(a, b)
	if not edges.has(k):
		return BLOCKED_COST
	return float(edges[k])

func set_edge_blocked(a: String, b: String, blocked: bool = true) -> void:
	var k: String = _edge_key(a, b)
	if not _base_edges.has(k) and not edges.has(k):
		return
	if blocked:
		edges[k] = BLOCKED_COST
	else:
		edges[k] = float(_base_edges.get(k, 1.0))
	dirty = true

func set_edge_cost_multiplier(a: String, b: String, mult: float) -> void:
	var k: String = _edge_key(a, b)
	if not _base_edges.has(k):
		return
	var base: float = float(_base_edges[k])
	edges[k] = base * maxf(0.0, mult)
	dirty = true

## Reset dynamic costs to the static base graph.
func reset_dynamic_costs() -> void:
	edges = _base_edges.duplicate(true)
	dirty = true

## Apply fire cost: any edge touching a node near a fire compartment room gets mult.
## fire_rooms: Dictionary room_id -> intensity (or Array of room_ids).
func apply_fire_costs(fire_rooms: Dictionary) -> void:
	if fire_rooms.is_empty():
		return
	for edge_key in _base_edges:
		var parts: PackedStringArray = str(edge_key).split("|")
		if parts.size() != 2:
			continue
		var ra: String = get_node_room(parts[0])
		var rb: String = get_node_room(parts[1])
		var intensity: float = maxf(float(fire_rooms.get(ra, 0.0)), float(fire_rooms.get(rb, 0.0)))
		if intensity <= 0.0:
			continue
		var base: float = float(_base_edges[edge_key])
		edges[edge_key] = base * FIRE_COST_MULT * maxf(1.0, intensity)
	dirty = true

## Block edges whose endpoints straddle a bulkhead pair (sealed hatch).
## Compartment matching uses room_role substring or room_id prefix heuristics when
## room_id contains the compartment name; also accepts exact room_id lists.
func block_bulkhead(compartment_a: String, compartment_b: String) -> void:
	if compartment_a.is_empty() or compartment_b.is_empty():
		return
	for edge_key in _base_edges:
		var parts: PackedStringArray = str(edge_key).split("|")
		if parts.size() != 2:
			continue
		var ra: String = get_node_room(parts[0]).to_lower()
		var rb: String = get_node_room(parts[1]).to_lower()
		var ca: String = compartment_a.to_lower()
		var cb: String = compartment_b.to_lower()
		var a_side: bool = ra.find(ca) >= 0 or rb.find(ca) >= 0
		var b_side: bool = ra.find(cb) >= 0 or rb.find(cb) >= 0
		# Cross edge: one endpoint matches A family, other matches B family.
		var a_on_0: bool = ra.find(ca) >= 0
		var a_on_1: bool = rb.find(ca) >= 0
		var b_on_0: bool = ra.find(cb) >= 0
		var b_on_1: bool = rb.find(cb) >= 0
		if (a_on_0 and b_on_1) or (b_on_0 and a_on_1):
			edges[edge_key] = BLOCKED_COST
	dirty = true

func mark_dirty() -> void:
	dirty = true

func get_summary() -> Dictionary:
	return {
		"node_count": nodes.size(),
		"edge_count": edges.size(),
		"cell_size": cell_size,
		"dirty": dirty,
	}

func _is_floor_module(module_id: String) -> bool:
	if module_id.is_empty():
		return false
	for prefix in FLOOR_MODULE_PREFIXES:
		if module_id.begins_with(prefix) or module_id.find(prefix) >= 0:
			return true
	return false

func _read_world_position(placement: Dictionary) -> Vector3:
	var raw: Variant = placement.get("world_position", placement.get("position", null))
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.INF

func _snap_pos(pos: Vector3) -> Vector3:
	var gx: float = roundf(pos.x / cell_size) * cell_size
	var gy: float = roundf(pos.y / deck_height) * deck_height
	var gz: float = roundf(pos.z / cell_size) * cell_size
	return Vector3(gx, gy, gz)

func _key_for_pos(pos: Vector3) -> String:
	var s: Vector3 = _snap_pos(pos)
	return "%d:%d:%d" % [int(round(s.x / cell_size)), int(round(s.y / deck_height)), int(round(s.z / cell_size))]

func _edge_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _connect_orthogonal_neighbors() -> void:
	var keys: Array = nodes.keys()
	keys.sort()
	for i in range(keys.size()):
		var ka: String = str(keys[i])
		var pa: Vector3 = get_node_pos(ka)
		for j in range(i + 1, keys.size()):
			var kb: String = str(keys[j])
			var pb: Vector3 = get_node_pos(kb)
			var dx: float = absf(pa.x - pb.x)
			var dy: float = absf(pa.y - pb.y)
			var dz: float = absf(pa.z - pb.z)
			# Same deck 4-connected.
			if dy < 0.01:
				var ortho: bool = (absf(dx - cell_size) < 0.01 and dz < 0.01) \
					or (absf(dz - cell_size) < 0.01 and dx < 0.01)
				if ortho:
					edges[_edge_key(ka, kb)] = 1.0
			# Vertical stack (elevators / multi-deck shafts).
			elif absf(dy - deck_height) < 0.01 and dx < 0.01 and dz < 0.01:
				edges[_edge_key(ka, kb)] = 1.25
			# Ramp-like diagonal: one cell step in XZ and one deck step.
			elif absf(dy - deck_height) < 0.01:
				var step_xz: bool = (absf(dx - cell_size) < 0.01 and dz < 0.01) \
					or (absf(dz - cell_size) < 0.01 and dx < 0.01) \
					or (absf(dx - cell_size) < 0.01 and absf(dz - cell_size) < 0.01)
				if step_xz:
					edges[_edge_key(ka, kb)] = 1.5

func _connect_vertical_neighbors() -> void:
	var keys: Array = nodes.keys()
	keys.sort()
	for i in range(keys.size()):
		var ka: String = str(keys[i])
		var pa: Vector3 = get_node_pos(ka)
		for j in range(i + 1, keys.size()):
			var kb: String = str(keys[j])
			var pb: Vector3 = get_node_pos(kb)
			var dx: float = absf(pa.x - pb.x)
			var dy: float = absf(pa.y - pb.y)
			var dz: float = absf(pa.z - pb.z)
			if absf(dy - deck_height) >= 0.01:
				continue
			if dx < 0.01 and dz < 0.01:
				edges[_edge_key(ka, kb)] = 1.25
			elif (absf(dx - cell_size) < 0.01 and dz < 0.01) \
					or (absf(dz - cell_size) < 0.01 and dx < 0.01) \
					or (absf(dx - cell_size) < 0.01 and absf(dz - cell_size) < 0.01):
				edges[_edge_key(ka, kb)] = 1.5

func _connect_structural_edges(structural_plan: Dictionary) -> void:
	var edges_variant: Variant = structural_plan.get("edges", null)
	if edges_variant is Dictionary:
		for edge_key_variant in (edges_variant as Dictionary).keys():
			var edge_variant: Variant = (edges_variant as Dictionary)[edge_key_variant]
			if edge_variant is Dictionary:
				_connect_structural_edge(edge_variant as Dictionary)
	elif edges_variant is Array:
		for edge_variant in edges_variant as Array:
			if edge_variant is Dictionary:
				_connect_structural_edge(edge_variant as Dictionary)

func _connect_structural_edge(edge: Dictionary) -> void:
	var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
	if kind == "SOLID":
		return
	var source_cells_variant: Variant = edge.get("source_cells", [])
	if not (source_cells_variant is Array) or (source_cells_variant as Array).size() < 2:
		return
	var first: Dictionary = _read_structural_cell((source_cells_variant as Array)[0], int(edge.get("deck", -1)))
	var second: Dictionary = _read_structural_cell((source_cells_variant as Array)[1], int(edge.get("deck", -1)))
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return
	if int(first.get("deck", -1)) != int(second.get("deck", -1)):
		return
	var first_key: String = _key_for_cell(int(first["deck"]), first["cell"])
	var second_key: String = _key_for_cell(int(second["deck"]), second["cell"])
	if not nodes.has(first_key) or not nodes.has(second_key) or first_key == second_key:
		return
	if kind == "OPEN" or kind == "DOOR" or kind == "HATCH" or kind == "BREACH":
		edges[_edge_key(first_key, second_key)] = 1.0
	elif kind == "LOCKED":
		edges[_edge_key(first_key, second_key)] = BLOCKED_COST

func _read_structural_cell(value: Variant, default_deck: int) -> Dictionary:
	if value is Array:
		var values: Array = value
		if values.size() < 2:
			return {"ok": false}
		var x: Variant = values[0]
		var z: Variant = values[1]
		if not _is_integer_value(x) or not _is_integer_value(z):
			return {"ok": false}
		var deck: int = default_deck
		if values.size() >= 3 and _is_integer_value(values[2]):
			deck = int(values[2])
		if deck < 0:
			return {"ok": false}
		return {"ok": true, "cell": Vector2i(int(x), int(z)), "deck": deck}
	if value is String:
		var text: String = str(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() < 2:
			parts = text.split(" ", false)
		if parts.size() < 2:
			return {"ok": false}
		var x_text: String = parts[0].strip_edges()
		var z_text: String = parts[1].strip_edges()
		if not x_text.is_valid_int() or not z_text.is_valid_int():
			return {"ok": false}
		var deck: int = default_deck
		if parts.size() >= 3 and parts[2].strip_edges().is_valid_int():
			deck = int(parts[2].strip_edges())
		if deck < 0:
			return {"ok": false}
		return {"ok": true, "cell": Vector2i(int(x_text), int(z_text)), "deck": deck}
	return {"ok": false}

func _key_for_cell(deck: int, cell: Vector2i) -> String:
	return "%d:%d:%d" % [cell.x, deck, cell.y]

func _is_integer_value(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value)))) or (typeof(value) == TYPE_STRING and str(value).is_valid_int())
