extends SceneTree

## Verifies ShipNavGraph honors compiler edge kinds instead of proximity alone.
## Marker: NAV SOLID EDGES PASS

const NavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")


func _initialize() -> void:
	var export_dir: String = OS.get_environment("WORLDGEN_EXPORT_DIR")
	if export_dir.is_empty():
		export_dir = "D:/world_gen/target/export"
	var layout_path: String = export_dir.path_join("layout.json")
	if not FileAccess.file_exists(layout_path):
		_fail("worldgen layout missing: %s" % layout_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not (parsed is Dictionary):
		_fail("worldgen layout is not a Dictionary")
		return
	var layout: Dictionary = parsed
	var plan_variant: Variant = layout.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		_fail("worldgen layout has no structural_plan")
		return
	var graph = NavGraphScript.new()
	var node_count: int = graph.build_from_layout(layout)
	if node_count < 2:
		_fail("nav graph has too few nodes: %d" % node_count)
		return

	var solid_checked: int = 0
	var passable_checked: int = 0
	var locked_checked: int = 0
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
		var first_id: String = _node_id(first)
		var second_id: String = _node_id(second)
		if not graph.has_node(first_id) or not graph.has_node(second_id):
			continue
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
		var cost: float = graph.edge_cost(first_id, second_id)
		if kind == "SOLID":
			solid_checked += 1
			if cost < NavGraphScript.BLOCKED_COST:
				_fail("SOLID edge crossed by nav graph: %s -> %s cost=%s" % [first_id, second_id, str(cost)])
				return
		elif kind == "LOCKED":
			locked_checked += 1
			if cost < NavGraphScript.BLOCKED_COST:
				_fail("LOCKED edge was not blocked: %s -> %s cost=%s" % [first_id, second_id, str(cost)])
				return
		elif kind == "OPEN" or kind == "DOOR" or kind == "HATCH" or kind == "BREACH":
			passable_checked += 1
			if cost >= NavGraphScript.BLOCKED_COST:
				_fail("passable edge was blocked kind=%s %s -> %s" % [kind, first_id, second_id])
				return

	var start_room: String = str((layout.get("prototype", {}) as Dictionary).get("start_room", ""))
	var goal_room: String = str((layout.get("prototype", {}) as Dictionary).get("goal_room", ""))
	var start_node: String = _first_room_node(graph, start_room)
	var goal_node: String = _first_room_node(graph, goal_room)
	if start_node.is_empty() or goal_node.is_empty():
		_fail("could not resolve start/goal graph nodes start=%s goal=%s" % [start_room, goal_room])
		return
	if not _reachable(graph, start_node, goal_node):
		_fail("start-to-goal path is not reachable start=%s goal=%s" % [start_node, goal_node])
		return
	if solid_checked <= 0 or passable_checked <= 0:
		_fail("edge coverage insufficient solid=%d passable=%d" % [solid_checked, passable_checked])
		return

	print("NAV SOLID EDGES PASS nodes=%d solid_checked=%d passable_checked=%d locked_checked=%d path=true" % [
		node_count, solid_checked, passable_checked, locked_checked])
	quit(0)


func _read_cell(value: Variant, default_deck: int) -> Dictionary:
	if value is Array:
		var values: Array = value
		if values.size() < 2:
			return {"ok": false}
		var deck: int = default_deck
		if values.size() >= 3:
			deck = int(values[2])
		if deck < 0:
			return {"ok": false}
		return {"ok": true, "x": int(values[0]), "z": int(values[1]), "deck": deck}
	if value is String:
		var text: String = str(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() < 2:
			parts = text.split(" ", false)
		if parts.size() < 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
			return {"ok": false}
		var deck: int = default_deck
		if parts.size() >= 3 and parts[2].strip_edges().is_valid_int():
			deck = int(parts[2].strip_edges())
		if deck < 0:
			return {"ok": false}
		return {"ok": true, "x": int(parts[0]), "z": int(parts[1]), "deck": deck}
	return {"ok": false}


func _node_id(cell: Dictionary) -> String:
	return "%d:%d:%d" % [int(cell["x"]), int(cell["deck"]), int(cell["z"])]


func _first_room_node(graph, room_id: String) -> String:
	for node_id_variant in graph.nodes.keys():
		var node_id: String = str(node_id_variant)
		if graph.get_node_room(node_id) == room_id:
			return node_id
	return ""


func _reachable(graph, start: String, goal: String) -> bool:
	var queue: Array[String] = [start]
	var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal:
			return true
		for neighbor_variant in graph.neighbors(current):
			var neighbor: String = str((neighbor_variant as Dictionary).get("to", ""))
			if not neighbor.is_empty() and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


func _fail(reason: String) -> void:
	push_error("NAV SOLID EDGES FAIL reason=%s" % reason)
	quit(1)
