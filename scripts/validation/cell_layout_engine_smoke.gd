extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")
const CellLayoutEngineScript := preload("res://scripts/procgen/cell_layout_engine.gd")

func _initialize() -> void:
	var template_data: Dictionary = {
		"id": "test",
		"description": "Test",
		"zones": [
			{"id": "entry", "role_pool": ["airlock"], "count": 1,
			 "position_hint": "bow", "deck": 0, "layout": "single", "attach_to": ""},
			{"id": "spine", "role_pool": ["corridor"], "count": 3,
			 "position_hint": "center", "deck": 0, "layout": "linear", "attach_to": "entry"},
			{"id": "side", "role_pool": ["cargo"], "count": 1,
			 "position_hint": "lateral", "deck": 0, "layout": "clustered", "attach_to": "spine"},
			{"id": "destination", "role_pool": ["reactor"], "count": 1,
			 "position_hint": "stern", "deck": 0, "layout": "single", "attach_to": "spine"},
		],
		"connections": [
			{"from": "entry", "to": "spine[0]", "distribution": "adjacent"},
			{"from": "spine[*]", "to": "spine[*+1]", "distribution": "adjacent"},
			{"from": "spine[*]", "to": "side", "distribution": "spread"},
			{"from": "spine[-1]", "to": "destination", "distribution": "adjacent"},
		],
		"deck_config": {"max_decks": 1, "vertical_transition_probability": 0.0},
	}
	var template: TopologyTemplateScript = TopologyTemplateScript.from_dict(template_data)

	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)

	var assigner: RoomAssignerScript = RoomAssignerScript.new()
	var room_plan: Array[Dictionary] = assigner.assign(template, bp, {})

	var engine: CellLayoutEngineScript = CellLayoutEngineScript.new()
	var cell_grid: Dictionary = engine.layout(room_plan, template, 42)

	var rooms: Dictionary = cell_grid.get("rooms", {})
	var adjacencies: Array = cell_grid.get("adjacencies", [])

	if rooms.is_empty():
		push_error("CELL LAYOUT ENGINE FAIL rooms dict is empty")
		quit(1)
		return

	for room in room_plan:
		var rid: String = str(room["id"])
		if not rooms.has(rid):
			push_error("CELL LAYOUT ENGINE FAIL room %s not placed" % rid)
			quit(1)
			return

	var occupied: Dictionary = {}
	for rid in rooms.keys():
		var room_data: Dictionary = rooms[rid]
		var cells: Array = room_data.get("cells", [])
		var deck: int = int(room_data.get("deck", 0))
		for cell in cells:
			var key: String = "%d_%d_%d" % [cell.x, cell.y, deck]
			if occupied.has(key):
				push_error("CELL LAYOUT ENGINE FAIL overlap at %s between %s and %s" % [key, rid, occupied[key]])
				quit(1)
				return
			occupied[key] = rid

	if adjacencies.is_empty():
		push_error("CELL LAYOUT ENGINE FAIL no adjacencies found")
		quit(1)
		return

	var entry_id: String = str(room_plan[0]["id"])
	var adj_map: Dictionary = {}
	for adj in adjacencies:
		var fr: String = str(adj["from_room"])
		var tr: String = str(adj["to_room"])
		if not adj_map.has(fr):
			adj_map[fr] = []
		adj_map[fr].append(tr)
		if not adj_map.has(tr):
			adj_map[tr] = []
		adj_map[tr].append(fr)

	var visited: Dictionary = {entry_id: true}
	var queue: Array = [entry_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in adj_map.get(current, []):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	if visited.size() != rooms.size():
		push_error("CELL LAYOUT ENGINE FAIL connectivity: reached %d of %d rooms" % [visited.size(), rooms.size()])
		quit(1)
		return

	var grid_a: Dictionary = engine.layout(room_plan, template, 42)
	var grid_b: Dictionary = engine.layout(room_plan, template, 42)
	if str(grid_a) != str(grid_b):
		push_error("CELL LAYOUT ENGINE FAIL determinism mismatch")
		quit(1)
		return

	print("CELL LAYOUT ENGINE PASS rooms=%d adjacencies=%d no_overlap=true connected=true deterministic=true" % [rooms.size(), adjacencies.size()])
	quit(0)
