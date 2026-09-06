extends RefCounted
class_name ShipNavGraph

## Pure walkable-cell graph built from a ship layout (ADR-0049, ADR-0054).
## Production graph is standing-play: compiler OPEN/DOOR/HATCH plus
## layout.vertical_connections, with LOCKED/BREACH present at BLOCKED_COST.
## Floor-module 4-connect is fallback only when structural_plan is absent.
## Never touches the scene tree.

const DEFAULT_CELL_SIZE: float = 4.0
const DEFAULT_DECK_HEIGHT: float = 4.0
const BLOCKED_COST: float = 1.0e9
const FIRE_COST_MULT: float = 6.0

const CANDIDATE_INTERNAL_PAIR: String = "internal_pair"
const CANDIDATE_VERTICAL_PAIR: String = "vertical_pair"
const CANDIDATE_EXTERNAL_ENDPOINT: String = "external_endpoint"
const CANDIDATE_UNRESOLVED: String = "unresolved"

const CANDIDATE_PROJECTION_KEYS: Array[String] = [
	"projection_edge_id", "topology_edge_id", "classification",
	"node_a", "node_b", "endpoint_node_id", "unresolved_reason",
	"baseline_topology_usable", "base_clear_excluding_target",
	"traversal_cost", "blocker_revision", "structural_module_id", "portal_id",
	"portal_is_open", "portal_is_unlocked", "portal_is_unsafe",
]

const CANDIDATE_ENDPOINT_KEYS: Array[String] = [
	"endpoint_id", "port_id", "ship_id", "target_module_id",
	"structural_edge_key", "portal_id", "threshold_node_id", "interior_node_id",
	"baseline_usable", "candidate_usable",
]

const CANDIDATE_CONNECTION_KEYS: Array[String] = ["connection_id", "host", "mobile"]
const CANDIDATE_CONNECTION_SIDE_KEYS: Array[String] = ["ship_id", "endpoint_id"]

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

## Build graph from a layout.json-shaped dictionary.
func build_from_layout(layout: Dictionary) -> int:
	clear()
	cell_size = maxf(0.1, float(layout.get("cell_size", DEFAULT_CELL_SIZE)))
	deck_height = maxf(0.1, float(layout.get("deck_height", DEFAULT_DECK_HEIGHT)))
	var plan_variant: Variant = layout.get("structural_plan", {})
	if plan_variant is Dictionary:
		var plan: Dictionary = plan_variant
		if not plan.is_empty() and plan.has("occupancy") and plan.has("edges"):
			return build_from_structural_plan(layout)
	return _build_from_floor_placements(layout)


func build_from_structural_plan(layout: Dictionary) -> int:
	var plan_variant: Variant = layout.get("structural_plan", {})
	if not (plan_variant is Dictionary):
		return 0
	var plan: Dictionary = plan_variant
	var occupancy_variant: Variant = plan.get("occupancy", {})
	var edges_variant: Variant = plan.get("edges", {})
	if not (occupancy_variant is Dictionary) or not (edges_variant is Dictionary):
		return 0
	var occupancy: Dictionary = occupancy_variant
	var plan_edges: Dictionary = edges_variant
	for occupancy_key_variant in occupancy.keys():
		var record_variant: Variant = occupancy[occupancy_key_variant]
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		var pos: Vector3 = _occupancy_world_position(record)
		var key: String = _key_for_pos(pos)
		if nodes.has(key):
			continue
		nodes[key] = {
			"pos": _snap_pos(pos),
			"room_id": str(record.get("room_id", "")),
			"key": key,
			"cell_key": str(record.get("cell_key", occupancy_key_variant)),
		}
	for edge_variant in plan_edges.values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
		if kind == "SOLID":
			continue
		var pair: PackedStringArray = _edge_node_keys(edge, occupancy, layout)
		if pair.size() != 2:
			continue
		var cost: float = standing_cost_for_kind(kind)
		_set_base_edge(pair[0], pair[1], cost)
	# Vertical hops first; blocked_links overlay last so a blocked
	# cross-deck room_link cannot be reopened at passable hatch cost.
	_add_vertical_connection_edges(layout, occupancy)
	_overlay_blocked_links(layout, occupancy)
	_base_edges = edges.duplicate(true)
	dirty = false
	return nodes.size()


static func standing_cost_for_kind(kind: String) -> float:
	var k: String = kind.to_upper()
	if k == "OPEN" or k == "DOOR":
		return 1.0
	if k == "HATCH":
		return 1.15
	return BLOCKED_COST


static func crouch_cost_for_kind(kind: String) -> float:
	var k: String = kind.to_upper()
	if k == "BREACH":
		return 1.75
	if k == "LOCKED" or k == "SOLID":
		return BLOCKED_COST
	return standing_cost_for_kind(k)


func _build_from_floor_placements(layout: Dictionary) -> int:
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

## Public cell → standing-node lookup. Occupancy records win; otherwise the
## snapped cell coordinate if that node exists.
func node_key_for_cell(value: Variant, fallback_deck: int, occupancy: Dictionary) -> String:
	return _node_key_from_cell(value, fallback_deck, occupancy)

func node_keys_for_edge(edge: Dictionary, occupancy: Dictionary, layout: Dictionary = {}) -> PackedStringArray:
	return _edge_node_keys(edge, occupancy, layout)

static func occupancy_key_for_cell(value: Variant, fallback_deck: int) -> String:
	var cell := Vector2i.ZERO
	var deck: int = fallback_deck
	if value is Vector2i:
		cell = value as Vector2i
	elif value is Array and (value as Array).size() >= 2:
		var values: Array = value
		cell = Vector2i(int(values[0]), int(values[1]))
		if values.size() >= 3:
			deck = int(values[2])
	else:
		return ""
	return "%d|%d|%d" % [deck, cell.x, cell.y]

func occupancy_has_cell(occupancy: Dictionary, value: Variant, fallback_deck: int) -> bool:
	var key: String = occupancy_key_for_cell(value, fallback_deck)
	return not key.is_empty() and occupancy.has(key)

func has_base_edge(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty() or a == b:
		return false
	return _base_edges.has(_edge_key(a, b))

func base_edge_cost(a: String, b: String) -> float:
	var k: String = _edge_key(a, b)
	if not _base_edges.has(k):
		return BLOCKED_COST
	return float(_base_edges[k])

## Undirected base hops as [a, b] pairs. Includes BLOCKED_COST edges.
func base_edge_pairs() -> Array:
	var out: Array = []
	for edge_key in _base_edges:
		var parts: PackedStringArray = str(edge_key).split("|")
		if parts.size() != 2:
			continue
		out.append(PackedStringArray([parts[0], parts[1]]))
	return out

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


## P17 foundation B: classify the exact authored topology without granting
## endpoint identity or scene authorization. The caller must build this graph
## from the same layout first so occupancy cells resolve to its copied nodes.
func classify_structural_projection(structural_plan: Dictionary, layout: Dictionary = {}) -> Dictionary:
	var occupancy_variant: Variant = structural_plan.get("occupancy", null)
	var plan_edges_variant: Variant = structural_plan.get("edges", null)
	if not (occupancy_variant is Dictionary) or not (plan_edges_variant is Dictionary):
		return {
			"ok": false,
			"reason": "invalid_candidate_projection",
			"rows": [],
		}
	var occupancy: Dictionary = occupancy_variant as Dictionary
	var plan_edges: Dictionary = plan_edges_variant as Dictionary
	var rows: Array[Dictionary] = []
	var plan_ids: Array = plan_edges.keys()
	for plan_id in plan_ids:
		if not (plan_id is String):
			return {"ok": false, "reason": "invalid_candidate_projection", "rows": []}
	plan_ids.sort()
	for topology_id_variant in plan_ids:
		var topology_id: String = str(topology_id_variant)
		var edge_variant: Variant = plan_edges[topology_id_variant]
		if not (topology_id_variant is String) or topology_id.is_empty() or not (edge_variant is Dictionary):
			rows.append(_candidate_unresolved_row(
				"plan:%s" % topology_id, topology_id, "invalid_edge_record", ""))
			continue
		var edge: Dictionary = edge_variant as Dictionary
		rows.append(_classify_plan_edge(topology_id, edge, occupancy, layout))
	var vertical_variant: Variant = layout.get(
		"vertical_connections", structural_plan.get("vertical_connections", []))
	if not (vertical_variant is Array):
		return {
			"ok": false,
			"reason": "invalid_candidate_projection",
			"rows": [],
		}
	var room_decks: Dictionary = _room_decks(layout)
	for vertical_value in vertical_variant as Array:
		rows.append(_classify_vertical_connection(vertical_value, occupancy, room_decks))
	return {
		"ok": true,
		"reason": "",
		"rows": rows,
	}


## Pure, deliberately untrusted candidate path evaluation. Success is never a
## live-scene authorization and the receiver and all input dictionaries remain
## unchanged.
func evaluate_edge_replacement_paths(
		request: Dictionary,
		edge_projection: Array[Dictionary],
		endpoints: Array[Dictionary],
		connections: Array[Dictionary]) -> Dictionary:
	var request_check: Dictionary = _validate_candidate_request(request)
	if not bool(request_check.get("ok", false)):
		return _candidate_denial(
			str(request_check.get("reason", "invalid_candidate_projection")),
			str(request.get("ship_id", "")),
			str(request.get("target_module_id", "")))
	var ship_id: String = str(request["ship_id"])
	var target_module_id: String = str(request["target_module_id"])
	var descriptor: Dictionary = request["original_descriptor"] as Dictionary
	var layer: String = str(descriptor.get("layout_layer", ""))
	if layer == "floor" or layer == "ceiling":
		return _candidate_denial("unsupported_candidate_layer", ship_id, target_module_id)
	if layer != "edge":
		return _candidate_denial("target_topology_mismatch", ship_id, target_module_id)
	var layout_projection: Dictionary = request["layout_projection"] as Dictionary
	var plan: Dictionary = layout_projection["structural_plan"] as Dictionary
	var classification: Dictionary = classify_structural_projection(plan, layout_projection)
	if not bool(classification.get("ok", false)):
		return _candidate_denial("invalid_candidate_projection", ship_id, target_module_id)
	var expected_rows: Array = classification.get("rows", []) as Array
	var validation: Dictionary = _validate_candidate_projection(
		request, edge_projection, expected_rows)
	if not bool(validation.get("ok", false)):
		return _candidate_denial(
			str(validation.get("reason", "invalid_candidate_projection")),
			ship_id,
			target_module_id)
	var projection_by_topology: Dictionary = validation["projection_by_topology"] as Dictionary
	var target_edge_key: String = str(validation["target_edge_key"])
	var target_row: Dictionary = projection_by_topology[target_edge_key] as Dictionary
	if str(target_row.get("classification", "")) == CANDIDATE_EXTERNAL_ENDPOINT:
		return _candidate_denial("unsupported_external_target", ship_id, target_module_id)
	if str(target_row.get("classification", "")) != CANDIDATE_INTERNAL_PAIR:
		return _candidate_denial("target_topology_mismatch", ship_id, target_module_id)
	var endpoint_check: Dictionary = _validate_candidate_endpoints(
		ship_id, target_module_id, endpoints, projection_by_topology)
	if not bool(endpoint_check.get("ok", false)):
		return _candidate_denial(
			str(endpoint_check.get("reason", "invalid_candidate_projection")),
			ship_id,
			target_module_id)
	var endpoints_by_id: Dictionary = endpoint_check["endpoints_by_id"] as Dictionary
	var connection_check: Dictionary = _validate_candidate_connections(
		ship_id, connections, endpoints_by_id)
	if not bool(connection_check.get("ok", false)):
		return _candidate_denial(
			str(connection_check.get("reason", "active_connection_identity_missing")),
			ship_id,
			target_module_id)
	var portal_states: Dictionary = validation["portal_states"] as Dictionary
	var baseline_graph: Variant = _candidate_graph_from_projection(
		edge_projection, "", "", portal_states)
	var topology_kind: String = str(validation["target_topology_kind"])
	var candidate_graph: Variant = _candidate_graph_from_projection(
		edge_projection, target_edge_key, topology_kind, portal_states)
	var baseline_endpoints: Dictionary = _candidate_validate_baseline_endpoints(
		baseline_graph, endpoints)
	if not bool(baseline_endpoints.get("ok", false)):
		return _candidate_denial("invalid_candidate_projection", ship_id, target_module_id)
	var actor_exit: Dictionary = _candidate_actor_exit(
		candidate_graph, str(request["actor_node_id"]), endpoints)
	if not bool(actor_exit.get("ok", false)):
		return _candidate_denial(str(actor_exit.get("reason", "egress_blocked")), ship_id, target_module_id)
	var connection_paths: Dictionary = _candidate_local_connection_paths(
		ship_id,
		baseline_graph,
		candidate_graph,
		connections,
		endpoints_by_id)
	if not bool(connection_paths.get("ok", false)):
		return _candidate_denial(
			str(connection_paths.get("reason", "connected_side_route_blocked")),
			ship_id,
			target_module_id)
	return {
		"ok": true,
		"reason": "",
		"scene_authorized": false,
		"ship_id": ship_id,
		"target_module_id": target_module_id,
		"actor_exit": actor_exit["actor_exit"],
		"local_connection_paths": connection_paths["paths"],
		"overlay": {
			"edge_key": target_edge_key,
			"node_pair": PackedStringArray([
				str(target_row["node_a"]), str(target_row["node_b"])]),
			"topology_kind": topology_kind,
			"topology_state": str(validation["target_topology_state"]),
			"retained_portal_state": _candidate_portal_copy(
				str(target_row.get("portal_id", "")), portal_states),
		},
	}


func _candidate_unresolved_row(
		projection_id: String,
		topology_id: String,
		reason: String,
		structural_module_id: String) -> Dictionary:
	return {
		"projection_edge_id": projection_id,
		"topology_edge_id": topology_id,
		"classification": CANDIDATE_UNRESOLVED,
		"node_a": "",
		"node_b": "",
		"endpoint_node_id": "",
		"unresolved_reason": reason,
		"structural_module_id": structural_module_id,
	}


func _classify_plan_edge(
		topology_id: String,
		edge: Dictionary,
		occupancy: Dictionary,
		layout: Dictionary) -> Dictionary:
	if not _candidate_valid_plan_edge_record(edge):
		return _candidate_unresolved_row(
			"plan:%s" % topology_id, topology_id, "malformed_edge_record", "")
	var module_id: String = edge["module_id"] as String
	var authored_id: String = edge.get("edge_key", edge.get("key", topology_id)) as String
	if authored_id != topology_id \
			or (edge.has("id") and (not (edge["id"] is String) or str(edge["id"]) != "edge:%s" % topology_id)):
		return _candidate_unresolved_row(
			"plan:%s" % topology_id, topology_id, "edge_identity_mismatch", module_id)
	var source_cells_variant: Variant = edge.get("source_cells", null)
	if not (source_cells_variant is Array):
		return _candidate_unresolved_row(
			"plan:%s" % topology_id, topology_id, "edge_cells_missing", module_id)
	var cells: Array = source_cells_variant as Array
	if cells.size() < 2:
		return _candidate_unresolved_row(
			"plan:%s" % topology_id, topology_id, "edge_cells_missing", module_id)
	var resolved: PackedStringArray = PackedStringArray()
	var deck: int = int(edge.get("deck", 0))
	for cell in cells.slice(0, 2):
		if not occupancy_has_cell(occupancy, cell, deck):
			continue
		var node_id: String = _node_key_from_cell(cell, deck, occupancy)
		if not node_id.is_empty() and not resolved.has(node_id):
			resolved.append(node_id)
	var row: Dictionary = {
		"projection_edge_id": "plan:%s" % topology_id,
		"topology_edge_id": topology_id,
		"classification": CANDIDATE_UNRESOLVED,
		"node_a": "",
		"node_b": "",
		"endpoint_node_id": "",
		"unresolved_reason": "",
		"structural_module_id": module_id,
	}
	if bool(edge.get("exterior", false)):
		if resolved.size() == 1:
			row["classification"] = CANDIDATE_EXTERNAL_ENDPOINT
			row["endpoint_node_id"] = resolved[0]
		else:
			row["unresolved_reason"] = "external_endpoint_cardinality"
		return row
	if resolved.size() != 2:
		row["unresolved_reason"] = "internal_endpoint_pair"
		return row
	var a: String = resolved[0]
	var b: String = resolved[1]
	row["classification"] = CANDIDATE_INTERNAL_PAIR
	row["node_a"] = a if a < b else b
	row["node_b"] = b if a < b else a
	return row


func _classify_vertical_connection(
		value: Variant,
		occupancy: Dictionary,
		room_decks: Dictionary) -> Dictionary:
	if not (value is Dictionary):
		return _candidate_unresolved_row("vertical:", "vertical:", "invalid_vertical_record", "")
	var link: Dictionary = value as Dictionary
	if not _candidate_valid_vertical_record(link):
		return _candidate_unresolved_row("vertical:", "vertical:", "malformed_vertical_record", "")
	var authored_id: String = link["id"] as String
	var topology_id: String = "vertical:%s" % authored_id
	var module_id: String = link["module_id"] as String
	if authored_id.is_empty() or module_id.is_empty():
		return _candidate_unresolved_row(topology_id, topology_id, "vertical_identity_missing", module_id)
	var from_room: String = str(link.get("from_room", ""))
	var to_room: String = str(link.get("to_room", ""))
	var from_deck: int = int(room_decks.get(from_room, 0))
	var to_deck: int = int(room_decks.get(to_room, 0))
	var from_cell: Variant = link.get("from_cell", null)
	var to_cell: Variant = link.get("to_cell", null)
	var a: String = _node_key_from_cell(from_cell, from_deck, occupancy) \
		if occupancy_has_cell(occupancy, from_cell, from_deck) else ""
	var b: String = _node_key_from_cell(to_cell, to_deck, occupancy) \
		if occupancy_has_cell(occupancy, to_cell, to_deck) else ""
	if a.is_empty() or b.is_empty() or a == b:
		return _candidate_unresolved_row(
			topology_id, topology_id, "vertical_endpoint_pair", module_id)
	return {
		"projection_edge_id": topology_id,
		"topology_edge_id": topology_id,
		"classification": CANDIDATE_VERTICAL_PAIR,
		"node_a": a if a < b else b,
		"node_b": b if a < b else a,
		"endpoint_node_id": "",
		"unresolved_reason": "",
		"structural_module_id": module_id,
	}


func _candidate_valid_plan_edge_record(edge: Dictionary) -> bool:
	for required in ["module_id", "source_cells", "deck", "kind", "state", "exterior", "portal"]:
		if not edge.has(required):
			return false
	if not (edge["module_id"] is String) \
			or not (edge["kind"] is String) or not (edge["state"] is String) \
			or not _candidate_is_bool(edge["exterior"]) or not _candidate_is_bool(edge["portal"]):
		return false
	var kind: String = edge["kind"] as String
	var state: String = edge["state"] as String
	if kind != state or kind != kind.to_upper() \
			or kind not in ["OPEN", "DOOR", "HATCH", "LOCKED", "BREACH", "SOLID"]:
		return false
	if edge.has("edge_key") and (not (edge["edge_key"] is String) or str(edge["edge_key"]).is_empty()):
		return false
	if edge.has("key") and (not (edge["key"] is String) or str(edge["key"]).is_empty()):
		return false
	if edge.has("edge_key") and edge.has("key") and edge["edge_key"] != edge["key"]:
		return false
	if not _candidate_exact_integer(edge["deck"]) or int(edge["deck"]) < 0:
		return false
	if not (edge["source_cells"] is Array) or (edge["source_cells"] as Array).size() != 2:
		return false
	for cell in edge["source_cells"] as Array:
		if not _candidate_valid_exact_cell(cell) or int((cell as Array)[2]) != int(edge["deck"]):
			return false
	for optional_bool in ["placement_required", "wrapper_required"]:
		if edge.has(optional_bool) and not _candidate_is_bool(edge[optional_bool]):
			return false
	for optional_string in ["direction", "opposite_direction", "owner_room", "other_room"]:
		if edge.has(optional_string) and not (edge[optional_string] is String):
			return false
	return true


func _candidate_valid_vertical_record(link: Dictionary) -> bool:
	for required in ["id", "module_id", "from_room", "to_room", "from_cell", "to_cell"]:
		if not link.has(required):
			return false
	for string_key in ["id", "module_id", "from_room", "to_room"]:
		if not (link[string_key] is String) or str(link[string_key]).is_empty():
			return false
	if link.has("type") and not (link["type"] is String):
		return false
	return _candidate_valid_exact_cell(link["from_cell"]) \
		and _candidate_valid_exact_cell(link["to_cell"])


func _candidate_valid_exact_cell(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	var cell: Array = value as Array
	for coordinate in cell:
		if not _candidate_exact_integer(coordinate):
			return false
	return int(cell[2]) >= 0


func _candidate_exact_integer(value: Variant) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number)


func _validate_candidate_request(request: Dictionary) -> Dictionary:
	var required: Array[String] = [
		"ship_id", "layout_revision", "layout_fingerprint", "actor_node_id",
		"target_module_id", "target_live_state", "original_descriptor",
		"layout_projection", "portal_states",
	]
	if not _candidate_has_exact_keys(request, required):
		return {"ok": false, "reason": "invalid_candidate_projection"}
	for key in ["ship_id", "layout_revision", "layout_fingerprint", "actor_node_id", "target_module_id"]:
		if not (request[key] is String) or str(request[key]).is_empty():
			return {"ok": false, "reason": "invalid_candidate_projection"}
	if str(request["layout_fingerprint"]).length() != 64:
		return {"ok": false, "reason": "invalid_candidate_projection"}
	if not has_node(str(request["actor_node_id"])):
		return {"ok": false, "reason": "invalid_candidate_projection"}
	if not (request["original_descriptor"] is Dictionary) \
			or not (request["layout_projection"] is Dictionary) \
			or not (request["portal_states"] is Array):
		return {"ok": false, "reason": "invalid_candidate_projection"}
	if not (request["target_live_state"] is String) or str(request["target_live_state"]) != "destroyed":
		return {"ok": false, "reason": "target_not_destroyed"}
	var descriptor: Dictionary = request["original_descriptor"] as Dictionary
	for descriptor_string in [
			"module_id", "structural_module_id", "layout_layer", "layout_revision", "layout_fingerprint"]:
		if not descriptor.has(descriptor_string) or not (descriptor[descriptor_string] is String):
			return {"ok": false, "reason": "target_topology_mismatch"}
	if str(descriptor.get("module_id", "")) != str(request["target_module_id"]):
		return {"ok": false, "reason": "target_topology_mismatch"}
	if str(descriptor.get("layout_revision", "")) != str(request["layout_revision"]) \
			or str(descriptor.get("layout_fingerprint", "")) != str(request["layout_fingerprint"]):
		return {"ok": false, "reason": "stale_layout"}
	var layout_projection: Dictionary = request["layout_projection"] as Dictionary
	var layout_keys: Array[String] = ["structural_plan", "vertical_connections", "portals"]
	if not _candidate_has_exact_keys(layout_projection, layout_keys) \
			or not (layout_projection["structural_plan"] is Dictionary) \
			or not (layout_projection["vertical_connections"] is Array) \
			or not (layout_projection["portals"] is Array):
		return {"ok": false, "reason": "invalid_candidate_projection"}
	for portal in layout_projection["portals"] as Array:
		if not (portal is Dictionary):
			return {"ok": false, "reason": "invalid_candidate_projection"}
	var plan: Dictionary = layout_projection["structural_plan"] as Dictionary
	if not (plan.get("occupancy", null) is Dictionary) or not (plan.get("edges", null) is Dictionary):
		return {"ok": false, "reason": "invalid_candidate_projection"}
	return {"ok": true, "reason": ""}


func _validate_candidate_projection(
		request: Dictionary,
		projection: Array[Dictionary],
		expected_rows: Array) -> Dictionary:
	if projection.size() != expected_rows.size():
		return {"ok": false, "reason": "invalid_candidate_projection"}
	var expected_by_id: Dictionary = {}
	for expected_variant in expected_rows:
		if not (expected_variant is Dictionary):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		var expected: Dictionary = expected_variant as Dictionary
		var projection_id: String = str(expected.get("projection_edge_id", ""))
		if projection_id.is_empty() or expected_by_id.has(projection_id):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		expected_by_id[projection_id] = expected
	var portal_check: Dictionary = _candidate_portal_states(request["portal_states"] as Array)
	if not bool(portal_check.get("ok", false)):
		return portal_check
	var portal_states: Dictionary = portal_check["states"] as Dictionary
	var portal_identity_check: Dictionary = _candidate_expected_portal_ids(
		request["layout_projection"] as Dictionary)
	if not bool(portal_identity_check.get("ok", false)):
		return {"ok": false, "reason": str(portal_identity_check.get(
			"reason", "portal_state_mismatch"))}
	var expected_portal_ids: Dictionary = portal_identity_check["by_edge"] as Dictionary
	var projection_by_topology: Dictionary = {}
	var pair_ids: Dictionary = {}
	var used_portal_ids: Dictionary = {}
	var blocker_revision: String = ""
	for row in projection:
		if not _candidate_has_exact_keys(row, CANDIDATE_PROJECTION_KEYS):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		for string_key in [
				"projection_edge_id", "topology_edge_id", "classification", "node_a", "node_b",
				"endpoint_node_id", "unresolved_reason", "blocker_revision", "structural_module_id", "portal_id"]:
			if not (row[string_key] is String):
				return {"ok": false, "reason": "invalid_candidate_projection"}
		var projection_id: String = row["projection_edge_id"] as String
		if not expected_by_id.has(projection_id):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		var expected: Dictionary = expected_by_id[projection_id] as Dictionary
		for identity_key in [
				"topology_edge_id", "classification", "node_a", "node_b",
				"endpoint_node_id", "unresolved_reason", "structural_module_id"]:
			if row[identity_key] != expected.get(identity_key, null):
				return {"ok": false, "reason": "invalid_candidate_projection"}
		var topology_id: String = str(row["topology_edge_id"])
		if topology_id.is_empty() or projection_by_topology.has(topology_id):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		var classification: String = str(row["classification"])
		if classification not in [
				CANDIDATE_INTERNAL_PAIR, CANDIDATE_VERTICAL_PAIR,
				CANDIDATE_EXTERNAL_ENDPOINT, CANDIDATE_UNRESOLVED]:
			return {"ok": false, "reason": "invalid_candidate_projection"}
		if classification == CANDIDATE_UNRESOLVED \
				and not str(row["unresolved_reason"]).begins_with("external_"):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		if not _candidate_is_bool(row["baseline_topology_usable"]) \
				or not _candidate_is_bool(row["base_clear_excluding_target"]) \
				or not _candidate_is_bool(row["portal_is_open"]) \
				or not _candidate_is_bool(row["portal_is_unlocked"]) \
				or not _candidate_is_bool(row["portal_is_unsafe"]):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		if not _candidate_positive_finite(row["traversal_cost"]):
			return {"ok": false, "reason": "invalid_candidate_projection"}
		var row_revision: String = str(row["blocker_revision"])
		if row_revision.is_empty():
			return {"ok": false, "reason": "invalid_candidate_projection"}
		if blocker_revision.is_empty():
			blocker_revision = row_revision
		elif blocker_revision != row_revision:
			return {"ok": false, "reason": "invalid_candidate_projection"}
		if classification in [CANDIDATE_INTERNAL_PAIR, CANDIDATE_VERTICAL_PAIR]:
			var a: String = str(row["node_a"])
			var b: String = str(row["node_b"])
			if a.is_empty() or b.is_empty() or a == b or not has_node(a) or not has_node(b):
				return {"ok": false, "reason": "invalid_candidate_projection"}
			var pair_key: String = _edge_key(a, b)
			if pair_ids.has(pair_key):
				return {"ok": false, "reason": "invalid_candidate_projection"}
			pair_ids[pair_key] = projection_id
		elif classification == CANDIDATE_EXTERNAL_ENDPOINT:
			var endpoint_node: String = str(row["endpoint_node_id"])
			if endpoint_node.is_empty() or not has_node(endpoint_node):
				return {"ok": false, "reason": "invalid_candidate_projection"}
		var portal_id: String = str(row["portal_id"])
		var plan_edge: Dictionary = _candidate_plan_edge(request, topology_id)
		var authored_portal: bool = bool(plan_edge.get("portal", false)) if not plan_edge.is_empty() else false
		if authored_portal:
			var expected_portal_id: String = str(expected_portal_ids.get(topology_id, ""))
			if portal_id.is_empty() or portal_id != expected_portal_id \
					or not portal_states.has(portal_id):
				return {"ok": false, "reason": "portal_state_mismatch"}
			var state: Dictionary = portal_states[portal_id] as Dictionary
			if str(state["edge_key"]) != topology_id \
					or state["portal_kind"] != plan_edge.get("kind", plan_edge.get("state", "")) \
					or bool(state["is_open"]) != bool(row["portal_is_open"]) \
					or bool(state["is_unlocked"]) != bool(row["portal_is_unlocked"]) \
					or bool(state["is_unsafe"]) != bool(row["portal_is_unsafe"]):
				return {"ok": false, "reason": "portal_state_mismatch"}
			used_portal_ids[portal_id] = true
		else:
			if not portal_id.is_empty() or bool(row["portal_is_open"]) \
					or bool(row["portal_is_unlocked"]) or bool(row["portal_is_unsafe"]):
				return {"ok": false, "reason": "portal_state_mismatch"}
		projection_by_topology[topology_id] = row.duplicate(true)
	if used_portal_ids.size() != portal_states.size():
		return {"ok": false, "reason": "portal_state_mismatch"}
	var binding: Dictionary = _validate_candidate_target_binding(request, projection_by_topology)
	if not bool(binding.get("ok", false)):
		return binding
	return {
		"ok": true,
		"reason": "",
		"projection_by_topology": projection_by_topology,
		"portal_states": portal_states,
		"target_edge_key": binding["target_edge_key"],
		"target_topology_kind": binding["target_topology_kind"],
		"target_topology_state": binding["target_topology_state"],
	}


func _candidate_expected_portal_ids(layout_projection: Dictionary) -> Dictionary:
	var plan: Dictionary = layout_projection["structural_plan"] as Dictionary
	var plan_edges: Dictionary = plan["edges"] as Dictionary
	for edge_key_variant in plan_edges.keys():
		if not (edge_key_variant is String) or not (plan_edges[edge_key_variant] is Dictionary):
			return {"ok": false, "reason": "invalid_candidate_projection", "by_edge": {}}
		var plan_edge: Dictionary = plan_edges[edge_key_variant] as Dictionary
		if not _candidate_valid_plan_edge_record(plan_edge):
			return {"ok": false, "reason": "invalid_candidate_projection", "by_edge": {}}
	var authored_by_edge: Dictionary = {}
	var authored_ids: Dictionary = {}
	for value in layout_projection["portals"] as Array:
		if not (value is Dictionary):
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		var portal: Dictionary = value as Dictionary
		if not portal.has("id") or not (portal["id"] is String) or str(portal["id"]).is_empty():
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		var authored_id: String = portal["id"] as String
		if authored_ids.has(authored_id):
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		authored_ids[authored_id] = true
		if not portal.has("edge_key"):
			continue
		if not (portal["edge_key"] is String) or str(portal["edge_key"]).is_empty():
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		var edge_key: String = portal["edge_key"] as String
		if authored_by_edge.has(edge_key) or not plan_edges.has(edge_key) \
				or not (plan_edges[edge_key] is Dictionary) \
				or not bool((plan_edges[edge_key] as Dictionary).get("portal", false)):
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		authored_by_edge[edge_key] = authored_id
	var by_edge: Dictionary = {}
	var runtime_ids: Dictionary = {}
	for edge_key_variant in plan_edges.keys():
		var edge_key: String = edge_key_variant as String
		var edge: Dictionary = plan_edges[edge_key_variant] as Dictionary
		if not bool(edge["portal"]):
			continue
		var portal_id: String = str(authored_by_edge.get(edge_key, "edge:%s" % edge_key))
		if portal_id.is_empty() or runtime_ids.has(portal_id):
			return {"ok": false, "reason": "portal_state_mismatch", "by_edge": {}}
		runtime_ids[portal_id] = edge_key
		by_edge[edge_key] = portal_id
	return {"ok": true, "reason": "", "by_edge": by_edge}


func _candidate_portal_states(values: Array) -> Dictionary:
	var keys: Array[String] = [
		"portal_id", "edge_key", "portal_kind", "is_open", "is_unlocked", "is_unsafe"]
	var states: Dictionary = {}
	var edge_ids: Dictionary = {}
	for value in values:
		if not (value is Dictionary):
			return {"ok": false, "reason": "portal_state_mismatch"}
		var state: Dictionary = value as Dictionary
		if not _candidate_has_exact_keys(state, keys):
			return {"ok": false, "reason": "portal_state_mismatch"}
		for string_key in ["portal_id", "edge_key", "portal_kind"]:
			if not (state[string_key] is String):
				return {"ok": false, "reason": "portal_state_mismatch"}
		var portal_id: String = state["portal_id"] as String
		var edge_id: String = state["edge_key"] as String
		if portal_id.is_empty() or edge_id.is_empty() or str(state["portal_kind"]).is_empty() \
				or states.has(portal_id) or edge_ids.has(edge_id):
			return {"ok": false, "reason": "portal_state_mismatch"}
		if not _candidate_is_bool(state["is_open"]) \
				or not _candidate_is_bool(state["is_unlocked"]) \
				or not _candidate_is_bool(state["is_unsafe"]):
			return {"ok": false, "reason": "portal_state_mismatch"}
		var portal_kind: String = state["portal_kind"] as String
		if portal_kind != portal_kind.to_upper() \
				or portal_kind not in ["OPEN", "DOOR", "HATCH", "LOCKED", "BREACH"]:
			return {"ok": false, "reason": "portal_state_mismatch"}
		if portal_kind == "LOCKED" \
				and bool(state["is_open"]) and not bool(state["is_unlocked"]):
			return {"ok": false, "reason": "portal_state_mismatch"}
		states[portal_id] = state.duplicate(true)
		edge_ids[edge_id] = portal_id
	return {"ok": true, "reason": "", "states": states}


func _validate_candidate_target_binding(
		request: Dictionary,
		projection_by_topology: Dictionary) -> Dictionary:
	var descriptor: Dictionary = request["original_descriptor"] as Dictionary
	var binding_variant: Variant = descriptor.get("edge_binding", null)
	if not (binding_variant is Dictionary):
		return {"ok": false, "reason": "target_topology_mismatch"}
	var binding: Dictionary = binding_variant as Dictionary
	for key in ["edge_key", "source_cells", "topology_kind", "topology_state"]:
		if not binding.has(key):
			return {"ok": false, "reason": "target_topology_mismatch"}
	var edge_key: String = str(binding["edge_key"])
	var target_module_id: String = str(request["target_module_id"])
	if edge_key.is_empty() or target_module_id != "edge/%s" % edge_key \
			or not projection_by_topology.has(edge_key):
		return {"ok": false, "reason": "target_topology_mismatch"}
	var layout_projection: Dictionary = request["layout_projection"] as Dictionary
	var plan: Dictionary = layout_projection["structural_plan"] as Dictionary
	var plan_edges: Dictionary = plan["edges"] as Dictionary
	if not plan_edges.has(edge_key) or not (plan_edges[edge_key] is Dictionary):
		return {"ok": false, "reason": "target_topology_mismatch"}
	var plan_edge: Dictionary = plan_edges[edge_key] as Dictionary
	if str(descriptor.get("structural_module_id", "")) != str(plan_edge.get("module_id", "")):
		return {"ok": false, "reason": "target_topology_mismatch"}
	var expected_binding: Dictionary = {}
	for source_key in [
			"edge_key", "source_cells", "direction", "opposite_direction",
			"owner_room", "other_room", "exterior", "portal"]:
		if plan_edge.has(source_key):
			expected_binding[source_key] = plan_edge[source_key]
	if plan_edge.has("kind"):
		expected_binding["topology_kind"] = plan_edge["kind"]
	if plan_edge.has("state"):
		expected_binding["topology_state"] = plan_edge["state"]
	if not _candidate_has_exact_keys(binding, _candidate_string_keys(expected_binding)):
		return {"ok": false, "reason": "target_topology_mismatch"}
	for key in expected_binding:
		if binding[key] != expected_binding[key]:
			return {"ok": false, "reason": "target_topology_mismatch"}
	var occupancy: Dictionary = plan["occupancy"] as Dictionary
	var pair: PackedStringArray = _edge_node_keys(plan_edge, occupancy, {})
	var target_row: Dictionary = projection_by_topology[edge_key] as Dictionary
	var classification: String = str(target_row["classification"])
	if classification == CANDIDATE_INTERNAL_PAIR:
		if pair.size() != 2 or _edge_key(pair[0], pair[1]) != _edge_key(
				str(target_row["node_a"]), str(target_row["node_b"])):
			return {"ok": false, "reason": "target_topology_mismatch"}
	elif classification == CANDIDATE_EXTERNAL_ENDPOINT:
		var cells: Array = _standing_cells_for_edge(plan_edge, {})
		var resolved: PackedStringArray = PackedStringArray()
		for cell in cells.slice(0, 2):
			var node_id: String = _node_key_from_cell(cell, int(plan_edge.get("deck", 0)), occupancy)
			if not node_id.is_empty() and not resolved.has(node_id):
				resolved.append(node_id)
		if resolved.size() != 1 or resolved[0] != str(target_row["endpoint_node_id"]):
			return {"ok": false, "reason": "target_topology_mismatch"}
	return {
		"ok": true,
		"reason": "",
		"target_edge_key": edge_key,
		"target_topology_kind": str(binding["topology_kind"]),
		"target_topology_state": str(binding["topology_state"]),
	}


func _validate_candidate_endpoints(
		ship_id: String,
		target_module_id: String,
		values: Array[Dictionary],
		projection_by_topology: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}
	var ports: Dictionary = {}
	var boundaries: Dictionary = {}
	for endpoint in values:
		if not _candidate_has_exact_keys(endpoint, CANDIDATE_ENDPOINT_KEYS):
			return {"ok": false, "reason": "missing_registered_exit"}
		for string_key in [
				"endpoint_id", "port_id", "ship_id", "target_module_id", "structural_edge_key",
				"portal_id", "threshold_node_id", "interior_node_id"]:
			if not (endpoint[string_key] is String):
				return {"ok": false, "reason": "missing_registered_exit"}
		var endpoint_id: String = endpoint["endpoint_id"] as String
		var port_id: String = str(endpoint["port_id"])
		var edge_key: String = str(endpoint["structural_edge_key"])
		if endpoint_id.is_empty() or port_id.is_empty() or edge_key.is_empty() \
				or str(endpoint["ship_id"]) != ship_id \
				or by_id.has(endpoint_id) or ports.has(port_id) or boundaries.has(edge_key):
			return {"ok": false, "reason": "missing_registered_exit"}
		if str(endpoint["target_module_id"]) != "edge/%s" % edge_key \
				or not projection_by_topology.has(edge_key):
			return {"ok": false, "reason": "missing_registered_exit"}
		var projected: Dictionary = projection_by_topology[edge_key] as Dictionary
		if str(projected["classification"]) != CANDIDATE_EXTERNAL_ENDPOINT \
				or str(projected["endpoint_node_id"]) != str(endpoint["threshold_node_id"]):
			return {"ok": false, "reason": "missing_registered_exit"}
		var threshold: String = str(endpoint["threshold_node_id"])
		var interior: String = str(endpoint["interior_node_id"])
		if threshold.is_empty() or interior.is_empty() or threshold == interior \
				or not has_node(threshold) or not has_node(interior):
			return {"ok": false, "reason": "missing_registered_exit"}
		if str(endpoint["portal_id"]) != str(projected["portal_id"]):
			return {"ok": false, "reason": "portal_state_mismatch"}
		if not _candidate_is_bool(endpoint["baseline_usable"]) \
				or not _candidate_is_bool(endpoint["candidate_usable"]):
			return {"ok": false, "reason": "missing_registered_exit"}
		if (bool(endpoint["baseline_usable"]) or bool(endpoint["candidate_usable"])) \
				and not _candidate_boundary_passable(projected):
			return {"ok": false, "reason": "portal_state_mismatch"}
		if bool(endpoint["baseline_usable"]) != bool(endpoint["candidate_usable"]) \
				and str(endpoint["target_module_id"]) != target_module_id:
			return {"ok": false, "reason": "missing_registered_exit"}
		by_id[endpoint_id] = endpoint.duplicate(true)
		ports[port_id] = endpoint_id
		boundaries[edge_key] = endpoint_id
	return {"ok": true, "reason": "", "endpoints_by_id": by_id}


func _validate_candidate_connections(
		ship_id: String,
		values: Array[Dictionary],
		endpoints_by_id: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var used_local_endpoints: Dictionary = {}
	for connection in values:
		if not _candidate_has_exact_keys(connection, CANDIDATE_CONNECTION_KEYS):
			return {"ok": false, "reason": "active_connection_identity_missing"}
		if not (connection["connection_id"] is String):
			return {"ok": false, "reason": "active_connection_identity_missing"}
		var connection_id: String = connection["connection_id"] as String
		if connection_id.is_empty() or seen.has(connection_id):
			return {"ok": false, "reason": "active_connection_identity_missing"}
		var sides: Array[Dictionary] = []
		for side_key in ["host", "mobile"]:
			if not (connection[side_key] is Dictionary):
				return {"ok": false, "reason": "active_connection_identity_missing"}
			var side: Dictionary = connection[side_key] as Dictionary
			if not _candidate_has_exact_keys(side, CANDIDATE_CONNECTION_SIDE_KEYS) \
					or not (side["ship_id"] is String) or not (side["endpoint_id"] is String) \
					or str(side["ship_id"]).is_empty() or str(side["endpoint_id"]).is_empty():
				return {"ok": false, "reason": "active_connection_identity_missing"}
			sides.append(side)
		var local_count: int = 0
		for side in sides:
			if str(side["ship_id"]) == ship_id:
				local_count += 1
				var local_endpoint_id: String = str(side["endpoint_id"])
				if not endpoints_by_id.has(local_endpoint_id) or used_local_endpoints.has(local_endpoint_id):
					return {"ok": false, "reason": "active_connection_identity_missing"}
				used_local_endpoints[local_endpoint_id] = connection_id
		if local_count != 1:
			return {"ok": false, "reason": "active_connection_identity_missing"}
		if str(sides[0]["ship_id"]) == str(sides[1]["ship_id"]):
			return {"ok": false, "reason": "active_connection_identity_missing"}
		seen[connection_id] = true
	return {"ok": true, "reason": ""}


func _candidate_graph_from_projection(
		projection: Array[Dictionary],
		target_edge_key: String,
		target_kind: String,
		_portal_states: Dictionary) -> Variant:
	var graph: Variant = get_script().new()
	graph.cell_size = cell_size
	graph.deck_height = deck_height
	graph.nodes = nodes.duplicate(true)
	graph.edges.clear()
	for row in projection:
		var classification: String = str(row["classification"])
		if classification not in [CANDIDATE_INTERNAL_PAIR, CANDIDATE_VERTICAL_PAIR]:
			continue
		var topology_id: String = str(row["topology_edge_id"])
		var base_clear: bool = bool(row["base_clear_excluding_target"])
		var passable: bool = bool(row["baseline_topology_usable"]) and base_clear
		var portal_id: String = str(row["portal_id"])
		if not portal_id.is_empty():
			passable = passable and (bool(row["portal_is_open"]) or bool(row["portal_is_unsafe"]))
		var cost: float = float(row["traversal_cost"])
		if not target_edge_key.is_empty() and topology_id == target_edge_key:
			passable = _candidate_replacement_passable(target_kind, row) and base_clear
			cost = maxf(cost, _candidate_authored_cost(target_kind))
		var a: String = str(row["node_a"])
		var b: String = str(row["node_b"])
		graph.edges[graph._edge_key(a, b)] = cost if passable else BLOCKED_COST
	graph._base_edges = graph.edges.duplicate(true)
	graph.dirty = false
	return graph


func _candidate_replacement_passable(kind: String, row: Dictionary) -> bool:
	var normalized: String = kind.to_upper()
	if normalized == "OPEN":
		return true
	if normalized in ["SOLID", "BREACH"]:
		return false
	if normalized in ["DOOR", "HATCH", "LOCKED"]:
		return not str(row["portal_id"]).is_empty() \
			and (bool(row["portal_is_open"]) or bool(row["portal_is_unsafe"]))
	return false


func _candidate_authored_cost(kind: String) -> float:
	return 1.15 if kind.to_upper() == "HATCH" else 1.0


func _candidate_boundary_passable(row: Dictionary) -> bool:
	var passable: bool = bool(row["baseline_topology_usable"]) \
		and bool(row["base_clear_excluding_target"])
	if not str(row["portal_id"]).is_empty():
		passable = passable and (bool(row["portal_is_open"]) or bool(row["portal_is_unsafe"]))
	return passable


func _candidate_validate_baseline_endpoints(
		graph: Variant,
		endpoints: Array[Dictionary]) -> Dictionary:
	for endpoint in endpoints:
		if not bool(endpoint["baseline_usable"]):
			continue
		var path: Dictionary = _candidate_shortest_path(
			graph, str(endpoint["threshold_node_id"]), str(endpoint["interior_node_id"]))
		if not bool(path.get("ok", false)):
			return {"ok": false, "reason": "invalid_candidate_projection"}
	return {"ok": true, "reason": ""}


func _candidate_actor_exit(
		graph: Variant,
		actor_node_id: String,
		endpoints: Array[Dictionary]) -> Dictionary:
	if endpoints.is_empty():
		return {"ok": false, "reason": "missing_registered_exit"}
	var candidates: Array[Dictionary] = []
	for endpoint in endpoints:
		if bool(endpoint["candidate_usable"]):
			candidates.append(endpoint)
	if candidates.is_empty():
		return {"ok": false, "reason": "egress_blocked"}
	candidates.sort_custom(_candidate_endpoint_less)
	var best: Dictionary = {}
	for endpoint in candidates:
		var threshold: String = str(endpoint["threshold_node_id"])
		var interior: String = str(endpoint["interior_node_id"])
		var threshold_path: Dictionary = _candidate_shortest_path(graph, threshold, interior)
		if not bool(threshold_path.get("ok", false)):
			continue
		var actor_path: Dictionary = _candidate_shortest_path(graph, actor_node_id, threshold)
		if not bool(actor_path.get("ok", false)):
			continue
		var candidate: Dictionary = {
			"endpoint_id": str(endpoint["endpoint_id"]),
			"node_path": (actor_path["path"] as PackedStringArray).duplicate(),
			"cost": float(actor_path["cost"]),
		}
		if best.is_empty() or float(candidate["cost"]) < float(best["cost"]) \
				or (is_equal_approx(float(candidate["cost"]), float(best["cost"])) \
				and str(candidate["endpoint_id"]) < str(best["endpoint_id"])):
			best = candidate
	if best.is_empty():
		return {"ok": false, "reason": "egress_blocked"}
	return {"ok": true, "reason": "", "actor_exit": best}


func _candidate_local_connection_paths(
		ship_id: String,
		baseline_graph: Variant,
		candidate_graph: Variant,
		connections: Array[Dictionary],
		endpoints_by_id: Dictionary) -> Dictionary:
	var ordered: Array[Dictionary] = connections.duplicate(true)
	ordered.sort_custom(_candidate_connection_less)
	var paths: Array[Dictionary] = []
	for connection in ordered:
		var local_side_name: String = "host" \
			if str((connection["host"] as Dictionary)["ship_id"]) == ship_id else "mobile"
		var remote_side_name: String = "mobile" if local_side_name == "host" else "host"
		var local_side: Dictionary = connection[local_side_name] as Dictionary
		var remote_side: Dictionary = connection[remote_side_name] as Dictionary
		var endpoint: Dictionary = endpoints_by_id[str(local_side["endpoint_id"])] as Dictionary
		if not bool(endpoint["baseline_usable"]):
			continue
		var threshold: String = str(endpoint["threshold_node_id"])
		var interior: String = str(endpoint["interior_node_id"])
		var baseline_path: Dictionary = _candidate_shortest_path(baseline_graph, threshold, interior)
		if not bool(baseline_path.get("ok", false)):
			return {"ok": false, "reason": "invalid_candidate_projection", "paths": []}
		var candidate_path: Dictionary = _candidate_shortest_path(candidate_graph, threshold, interior)
		if not bool(candidate_path.get("ok", false)):
			return {"ok": false, "reason": "connected_side_route_blocked", "paths": []}
		paths.append({
			"connection_id": str(connection["connection_id"]),
			"local_side": local_side_name,
			"remote_identity": remote_side.duplicate(true),
			"endpoint_id": str(endpoint["endpoint_id"]),
			"threshold_node_id": threshold,
			"interior_node_id": interior,
			"node_path": (candidate_path["path"] as PackedStringArray).duplicate(),
			"cost": float(candidate_path["cost"]),
		})
	return {"ok": true, "reason": "", "paths": paths}


func _candidate_shortest_path(graph: Variant, start: String, goal: String) -> Dictionary:
	if not graph.has_node(start) or not graph.has_node(goal):
		return {"ok": false, "path": PackedStringArray(), "cost": INF}
	var distance: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var unvisited: Dictionary = {start: true}
	while not unvisited.is_empty():
		var candidates: Array = unvisited.keys()
		candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
			var da: float = float(distance.get(str(a), INF))
			var db: float = float(distance.get(str(b), INF))
			return str(a) < str(b) if is_equal_approx(da, db) else da < db)
		var current: String = str(candidates[0])
		unvisited.erase(current)
		if current == goal:
			break
		var neighbors_list: Array = graph.neighbors(current)
		neighbors_list.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str((a as Dictionary).get("to", "")) < str((b as Dictionary).get("to", "")))
		for neighbor_variant in neighbors_list:
			var neighbor: Dictionary = neighbor_variant as Dictionary
			var next: String = str(neighbor["to"])
			var next_distance: float = float(distance[current]) + float(neighbor["cost"])
			if not distance.has(next) or next_distance < float(distance[next]) \
					or (is_equal_approx(next_distance, float(distance[next])) \
					and current < str(previous.get(next, "~"))):
				distance[next] = next_distance
				previous[next] = current
				unvisited[next] = true
	if not distance.has(goal):
		return {"ok": false, "path": PackedStringArray(), "cost": INF}
	var reversed: PackedStringArray = PackedStringArray([goal])
	var cursor: String = goal
	while cursor != start:
		if not previous.has(cursor):
			return {"ok": false, "path": PackedStringArray(), "cost": INF}
		cursor = str(previous[cursor])
		reversed.append(cursor)
	var path: PackedStringArray = PackedStringArray()
	for index in range(reversed.size() - 1, -1, -1):
		path.append(reversed[index])
	return {"ok": true, "path": path, "cost": float(distance[goal])}


func _candidate_denial(reason: String, ship_id: String, target_module_id: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"scene_authorized": false,
		"ship_id": ship_id,
		"target_module_id": target_module_id,
		"actor_exit": {},
		"local_connection_paths": [],
		"overlay": {},
	}


func _candidate_portal_copy(portal_id: String, portal_states: Dictionary) -> Dictionary:
	if portal_id.is_empty() or not portal_states.has(portal_id):
		return {}
	return (portal_states[portal_id] as Dictionary).duplicate(true)


func _candidate_plan_edge(request: Dictionary, topology_id: String) -> Dictionary:
	var layout_projection: Dictionary = request["layout_projection"] as Dictionary
	var plan: Dictionary = layout_projection["structural_plan"] as Dictionary
	var edges_variant: Variant = plan.get("edges", {})
	if not (edges_variant is Dictionary) or not (edges_variant as Dictionary).has(topology_id):
		return {}
	var value: Variant = (edges_variant as Dictionary)[topology_id]
	return (value as Dictionary) if value is Dictionary else {}


func _candidate_has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func _candidate_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in value.keys():
		result.append(str(key))
	return result


func _candidate_positive_finite(value: Variant) -> bool:
	if not (value is int or value is float) or value is bool:
		return false
	var number: float = float(value)
	return is_finite(number) and number > 0.0 and number < BLOCKED_COST


func _candidate_is_bool(value: Variant) -> bool:
	return value is bool


func _candidate_endpoint_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("endpoint_id", "")) < str(b.get("endpoint_id", ""))


func _candidate_connection_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("connection_id", "")) < str(b.get("connection_id", ""))


func _is_floor_module(module_id: String) -> bool:
	if module_id.is_empty():
		return false
	for prefix in FLOOR_MODULE_PREFIXES:
		if module_id.begins_with(prefix) or module_id.find(prefix) >= 0:
			return true
	return false

func _read_world_position(placement: Dictionary) -> Vector3:
	return _vec3_from_variant(placement.get("world_position", placement.get("position", null)))

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

func _set_base_edge(a: String, b: String, cost: float) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	if not nodes.has(a) or not nodes.has(b):
		return
	edges[_edge_key(a, b)] = cost


func _overlay_blocked_links(layout: Dictionary, occupancy: Dictionary) -> void:
	var blocked_variant: Variant = layout.get("blocked_links", [])
	if not (blocked_variant is Array):
		return
	var room_decks: Dictionary = _room_decks(layout)
	for link_variant in (blocked_variant as Array):
		if not (link_variant is Dictionary):
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_key: String = _node_key_from_cell(
			link.get("from_cell", null), int(room_decks.get(from_room, 0)), occupancy)
		var to_key: String = _node_key_from_cell(
			link.get("to_cell", null), int(room_decks.get(to_room, 0)), occupancy)
		if from_key.is_empty() or to_key.is_empty():
			continue
		_set_base_edge(from_key, to_key, BLOCKED_COST)


func _add_vertical_connection_edges(layout: Dictionary, occupancy: Dictionary) -> void:
	var vertical_variant: Variant = layout.get("vertical_connections", [])
	if not (vertical_variant is Array):
		return
	var room_decks: Dictionary = _room_decks(layout)
	for link_variant in (vertical_variant as Array):
		if not (link_variant is Dictionary):
			continue
		var link: Dictionary = link_variant
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_key: String = _node_key_from_cell(
			link.get("from_cell", null), int(room_decks.get(from_room, 0)), occupancy)
		var to_key: String = _node_key_from_cell(
			link.get("to_cell", null), int(room_decks.get(to_room, 0)), occupancy)
		if from_key.is_empty() or to_key.is_empty():
			continue
		var pa: Vector3 = get_node_pos(from_key)
		var pb: Vector3 = get_node_pos(to_key)
		var dx: float = absf(pa.x - pb.x)
		var dz: float = absf(pa.z - pb.z)
		var same_xz: bool = dx < 0.01 and dz < 0.01
		var cost: float = 1.25 if same_xz else 1.5
		_set_base_edge(from_key, to_key, cost)


func _edge_node_keys(edge: Dictionary, occupancy: Dictionary, layout: Dictionary = {}) -> PackedStringArray:
	var deck: int = int(edge.get("deck", 0))
	var cells: Array = _standing_cells_for_edge(edge, layout)
	if cells.size() < 2:
		return PackedStringArray()
	var a: String = _node_key_from_cell(cells[0], deck, occupancy)
	var b: String = _node_key_from_cell(cells[1], deck, occupancy)
	if a.is_empty() or b.is_empty() or a == b:
		return PackedStringArray()
	return PackedStringArray([a, b])


func _standing_cells_for_edge(edge: Dictionary, layout: Dictionary) -> Array:
	var logical: Array = _logical_endpoint_cells(edge, layout)
	if logical.size() >= 2:
		return logical
	var source_cells: Variant = edge.get("source_cells", [])
	if source_cells is Array:
		return source_cells as Array
	return []


func _logical_endpoint_cells(edge: Dictionary, layout: Dictionary) -> Array:
	var lf: Variant = edge.get("logical_from_cell", null)
	var lt: Variant = edge.get("logical_to_cell", null)
	if lf != null and lt != null:
		return [lf, lt]
	if not bool(edge.get("portal", false)) and not bool(edge.get("logical_boundary", false)):
		return []
	var portals_v: Variant = layout.get("portals", [])
	if not (portals_v is Array):
		return []
	var edge_key_value: String = str(edge.get("key", edge.get("edge_key", "")))
	var edge_cell: Variant = edge.get("cell", null)
	var direction: String = str(edge.get("direction", ""))
	var owner: String = str(edge.get("owner_room", ""))
	var other: String = str(edge.get("other_room", ""))
	for portal_v in (portals_v as Array):
		if not (portal_v is Dictionary):
			continue
		var portal: Dictionary = portal_v
		if not bool(portal.get("logical_boundary", false)):
			continue
		var portal_key: String = str(portal.get("edge_key", ""))
		if not edge_key_value.is_empty() and portal_key == edge_key_value:
			return [portal.get("from_cell", null), portal.get("to_cell", null)]
		var portal_dir: String = str(portal.get("edge_direction", portal.get("direction", "")))
		if portal_dir == direction and _cell_xz_equal(portal.get("edge_cell", null), edge_cell):
			return [portal.get("from_cell", null), portal.get("to_cell", null)]
		var from_room: String = str(portal.get("from_room", ""))
		var to_room: String = str(portal.get("to_room", ""))
		if other.is_empty():
			continue
		if (from_room == owner and to_room == other) or (from_room == other and to_room == owner):
			return [portal.get("from_cell", null), portal.get("to_cell", null)]
	return []


func _cell_xz_equal(a: Variant, b: Variant) -> bool:
	var ac: Vector2i = _cell_xz(a)
	var bc: Vector2i = _cell_xz(b)
	if ac == Vector2i(-99999, -99999) or bc == Vector2i(-99999, -99999):
		return false
	return ac == bc


func _cell_xz(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(-99999, -99999)


func _node_key_from_cell(value: Variant, fallback_deck: int, occupancy: Dictionary) -> String:
	var cell := Vector2i.ZERO
	var deck: int = fallback_deck
	if value is Vector2i:
		cell = value as Vector2i
	elif value is Array and (value as Array).size() >= 2:
		var values: Array = value
		cell = Vector2i(int(values[0]), int(values[1]))
		if values.size() >= 3:
			deck = int(values[2])
	else:
		return ""
	var occupancy_key: String = occupancy_key_for_cell(value, fallback_deck)
	if occupancy_key.is_empty():
		occupancy_key = "%d|%d|%d" % [deck, cell.x, cell.y]
	if occupancy.has(occupancy_key):
		var record_variant: Variant = occupancy[occupancy_key]
		if record_variant is Dictionary:
			return _key_for_pos(_occupancy_world_position(record_variant as Dictionary))
	var pos := Vector3(float(cell.x) * cell_size, float(deck) * deck_height, float(cell.y) * cell_size)
	var key: String = _key_for_pos(pos)
	return key if nodes.has(key) else ""


func _occupancy_world_position(record: Dictionary) -> Vector3:
	var from_pos: Vector3 = _vec3_from_variant(record.get("position", record.get("world_position", null)))
	if from_pos != Vector3.INF:
		return from_pos
	var deck: int = int(record.get("deck", 0))
	var cell: Vector2i = _cell_xz_from_variant(record.get("cell", null))
	if cell == Vector2i(-99999, -99999):
		var key_parts: PackedStringArray = str(record.get("cell_key", "")).split("|")
		if key_parts.size() >= 3:
			deck = int(key_parts[0])
			cell = Vector2i(int(key_parts[1]), int(key_parts[2]))
	if cell == Vector2i(-99999, -99999):
		cell = Vector2i.ZERO
	return Vector3(float(cell.x) * cell_size, float(deck) * deck_height, float(cell.y) * cell_size)


func _vec3_from_variant(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	if raw is Dictionary:
		var d: Dictionary = raw
		if d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	return Vector3.INF


func _cell_xz_from_variant(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	if raw is Dictionary:
		var d: Dictionary = raw
		if d.has("x") and d.has("y"):
			return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return Vector2i(-99999, -99999)


func _room_decks(layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rooms_variant: Variant = layout.get("rooms", [])
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
