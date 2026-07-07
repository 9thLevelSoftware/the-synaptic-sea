extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")
const CellLayoutEngineScript := preload("res://scripts/procgen/cell_layout_engine.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

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

	# --- Tranche 5 (2026-07-06 audit M+M, topology_template.gd:52 +
	# stacked_v2.json:95): template.connections was parsed but consumed by
	# nothing — the engine was purely attach_to-driven, so stacked_v2's
	# declared "elevator -> upper_hub" cross-deck edge was never emitted and
	# the elevator zone had no vertical path.
	var v2_file := FileAccess.open("res://data/procgen/templates/stacked_v2.json", FileAccess.READ)
	if v2_file == null:
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2.json missing")
		quit(1)
		return
	var v2_data: Variant = JSON.parse_string(v2_file.get_as_text())
	v2_file.close()
	if not (v2_data is Dictionary):
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2.json did not parse")
		quit(1)
		return
	var v2_template: TopologyTemplateScript = TopologyTemplateScript.from_dict(v2_data)
	var v2_plan: Array[Dictionary] = assigner.assign(v2_template, bp, {})
	var v2_grid: Dictionary = engine.layout(v2_plan, v2_template, 42)

	# Map zone -> room ids for the two zones the declared connection names.
	var elevator_rooms: Array[String] = []
	var upper_hub_rooms: Array[String] = []
	for room in v2_plan:
		var zid: String = str(room.get("zone_id", ""))
		if zid == "elevator":
			elevator_rooms.append(str(room["id"]))
		elif zid == "upper_hub":
			upper_hub_rooms.append(str(room["id"]))
	if elevator_rooms.is_empty() or upper_hub_rooms.is_empty():
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2 elevator/upper_hub zones produced no rooms")
		quit(1)
		return

	var elevator_linked: bool = false
	for adj in v2_grid.get("adjacencies", []):
		var fr: String = str(adj["from_room"])
		var tr: String = str(adj["to_room"])
		if (fr in elevator_rooms and tr in upper_hub_rooms) \
				or (tr in elevator_rooms and fr in upper_hub_rooms):
			elevator_linked = true
			break
	if not elevator_linked:
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2 declared connection elevator->upper_hub not emitted (template.connections unconsumed)")
		quit(1)
		return

	# Determinism must survive the connections wiring.
	var v2_grid_b: Dictionary = engine.layout(v2_plan, v2_template, 42)
	if str(v2_grid) != str(v2_grid_b):
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2 determinism mismatch after connections wiring")
		quit(1)
		return

	# Full pipeline: the serialized layout's vertical_connections must carry the
	# elevator's cross-deck edge (this is what the loader turns into nav links).
	var generator := ShipLayoutGeneratorScript.new()
	var v2_bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var v2_layout: Dictionary = generator.generate_with_options(
		v2_bp, {"template": "stacked_v2"}, "", "", true)
	if v2_layout.is_empty():
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2 pipeline generation returned empty")
		quit(1)
		return
	var elevator_vertical: bool = false
	for vc in v2_layout.get("vertical_connections", []):
		var vfr: String = str(vc.get("from_room", ""))
		var vtr: String = str(vc.get("to_room", ""))
		if vfr.begins_with("elevator") or vtr.begins_with("elevator"):
			elevator_vertical = true
			break
	if not elevator_vertical:
		push_error("CELL LAYOUT ENGINE FAIL stacked_v2 pipeline layout has no elevator vertical_connection (elevator zone unreachable across decks)")
		quit(1)
		return

	print("CELL LAYOUT ENGINE PASS rooms=%d adjacencies=%d no_overlap=true connected=true deterministic=true connections_wired=true stacked_v2_elevator=true" % [rooms.size(), adjacencies.size()])
	quit(0)
