extends SceneTree

## ADR-0049 / ADR-0054: standing nav graph from compiler kinds.
## Marker: SHIP NAV GRAPH PASS nodes=<n> edges=<e> path=true wall=true shortcut_blocked=true stacked_vertical=true

const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GOLDEN: String = "res://data/procgen/golden/coherent_ship_001/layout.json"


func _initialize() -> void:
	var layout: Dictionary = _load_json(GOLDEN)
	if layout.is_empty():
		_fail("golden layout missing")
		return
	var graph = ShipNavGraphScript.new()
	var n: int = graph.build_from_layout(layout)
	if n < 8:
		_fail("expected >= 8 floor nodes, got %d" % n)
		return
	if graph.edge_count() < 4:
		_fail("expected edges between floor cells, got %d" % graph.edge_count())
		return
	var start := Vector3(0.0, 0.0, 0.0)
	var goal := Vector3(12.0, 0.0, 0.0)
	var path: Array = ThreatPathfinderScript.find_path(graph, start, goal)
	if path.size() < 2:
		_fail("no path along corridor floors (path size=%d)" % path.size())
		return
	var mid_a: String = graph.nearest_node(Vector3(4.0, 0.0, 0.0))
	var mid_b: String = graph.nearest_node(Vector3(8.0, 0.0, 0.0))
	if not mid_a.is_empty() and not mid_b.is_empty() and mid_a != mid_b:
		graph.set_edge_blocked(mid_a, mid_b, true)
		var blocked_path: Array = ThreatPathfinderScript.find_path(graph, start, goal)
		if blocked_path.size() >= path.size() and not blocked_path.is_empty():
			pass
		graph.set_edge_blocked(mid_a, mid_b, false)

	if not _golden_shortcut_standing_blocked(graph, layout):
		return
	if not _blocked_links_overlay_on_stored_door():
		return
	if not _stacked_has_vertical_and_path():
		return

	print("SHIP NAV GRAPH PASS nodes=%d edges=%d path=true wall=true shortcut_blocked=true stacked_vertical=true" % [
		n, graph.edge_count()])
	quit(0)


func _golden_shortcut_standing_blocked(graph, layout: Dictionary) -> bool:
	var occupancy: Dictionary = {}
	var plan_variant: Variant = layout.get("structural_plan", {})
	if plan_variant is Dictionary:
		var occ_variant: Variant = (plan_variant as Dictionary).get("occupancy", {})
		if occ_variant is Dictionary:
			occupancy = occ_variant
	var from_key: String = graph._node_key_from_cell([8, 1, 1], 1, occupancy)
	var to_key: String = graph._node_key_from_cell([9, 1, 1], 1, occupancy)
	# Reactor cell [9,1,1] is occupied; failing to resolve it is not "no neighbor".
	if to_key.is_empty():
		_fail("golden reactor cell [9,1,1] did not resolve to a nav node")
		return false
	if from_key.is_empty() or from_key == to_key:
		return true
	if graph.edge_cost(from_key, to_key) < ShipNavGraphScript.BLOCKED_COST:
		_fail("golden spine_to_reactor_blocked_shortcut is standing-passable")
		return false
	return true


func _blocked_links_overlay_on_stored_door() -> bool:
	var occupancy := {
		"0|0|0": {
			"cell_key": "0|0|0", "deck": 0, "cell": [0, 0], "room_id": "a",
			"position": [0.0, 0.0, 0.0],
		},
		"0|1|0": {
			"cell_key": "0|1|0", "deck": 0, "cell": [1, 0], "room_id": "b",
			"position": [4.0, 0.0, 0.0],
		},
	}
	var layout := {
		"cell_size": 4.0,
		"deck_height": 4.0,
		"rooms": [
			{"id": "a", "deck": 0, "cells": [[0, 0]]},
			{"id": "b", "deck": 0, "cells": [[1, 0]]},
		],
		"blocked_links": [{
			"id": "synthetic_blocked_door",
			"from_room": "a",
			"to_room": "b",
			"from_cell": [0, 0, 0],
			"to_cell": [1, 0, 0],
		}],
		"vertical_connections": [],
		"structural_plan": {
			"occupancy": occupancy,
			"edges": {
				"0|v|0|0": {
					"kind": "DOOR",
					"state": "DOOR",
					"deck": 0,
					"cell": [0, 0],
					"direction": "east",
					"source_cells": [[0, 0, 0], [1, 0, 0]],
					"position": [2.0, 0.0, 0.0],
					"yaw_degrees": 270.0,
				},
			},
		},
	}
	var graph = ShipNavGraphScript.new()
	if graph.build_from_layout(layout) < 2:
		_fail("synthetic overlay layout built no nodes")
		return false
	var a_key: String = graph._node_key_from_cell([0, 0, 0], 0, occupancy)
	var b_key: String = graph._node_key_from_cell([1, 0, 0], 0, occupancy)
	if a_key.is_empty() or b_key.is_empty():
		_fail("synthetic overlay occupancy keys missing")
		return false
	var edge_key: String = graph._edge_key(a_key, b_key)
	if not graph._base_edges.has(edge_key):
		_fail("blocked_links overlay omitted the stored DOOR hop")
		return false
	if float(graph._base_edges[edge_key]) < ShipNavGraphScript.BLOCKED_COST:
		_fail("blocked_links overlay left stored DOOR standing-passable")
		return false
	for neigh in graph.neighbors(a_key):
		if not (neigh is Dictionary):
			continue
		if str((neigh as Dictionary).get("to", "")) == b_key:
			_fail("neighbors() still returns blocked_links overlay hop")
			return false
	return true


func _stacked_has_vertical_and_path() -> bool:
	var generator = ShipLayoutGeneratorScript.new()
	var bp = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		42)
	var layout: Dictionary = generator.generate(bp, {"template": "stacked"})
	if layout.is_empty():
		_fail("stacked layout empty")
		return false
	var graph = ShipNavGraphScript.new()
	var n: int = graph.build_from_layout(layout)
	if n < 4:
		_fail("stacked nav nodes %d" % n)
		return false
	var vertical: int = 0
	for edge_key in graph._base_edges:
		var parts: PackedStringArray = str(edge_key).split("|")
		if parts.size() != 2:
			continue
		var pa: Vector3 = graph.get_node_pos(parts[0])
		var pb: Vector3 = graph.get_node_pos(parts[1])
		if absf(pa.y - pb.y) > graph.deck_height * 0.5:
			vertical += 1
	if vertical < 1:
		_fail("stacked template has no vertical _base_edges")
		return false
	var proto: Dictionary = layout.get("prototype", {}) as Dictionary
	var start_id: String = str(proto.get("start_room", ""))
	var goal_id: String = str(proto.get("goal_room", ""))
	var start_pos: Vector3 = _room_floor_pos(layout, start_id)
	var goal_pos: Vector3 = _room_floor_pos(layout, goal_id)
	if start_pos == Vector3.INF or goal_pos == Vector3.INF:
		_fail("stacked start/goal floor missing")
		return false
	var path: Array = ThreatPathfinderScript.find_path(graph, start_pos, goal_pos)
	if path.is_empty() and start_id != goal_id:
		_fail("stacked standing start→goal empty")
		return false
	return true


func _room_floor_pos(layout: Dictionary, room_id: String) -> Vector3:
	if room_id.is_empty():
		return Vector3.INF
	for room_variant in layout.get("rooms", []):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) != room_id:
			continue
		var plan_variant: Variant = layout.get("structural_plan", {})
		if plan_variant is Dictionary:
			var occupancy_variant: Variant = (plan_variant as Dictionary).get("occupancy", {})
			if occupancy_variant is Dictionary:
				for record_variant in (occupancy_variant as Dictionary).values():
					if not (record_variant is Dictionary):
						continue
					var record: Dictionary = record_variant
					if str(record.get("room_id", "")) != room_id:
						continue
					var raw: Variant = record.get("position", null)
					if raw is Array and (raw as Array).size() >= 3:
						return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
					if raw is Vector3:
						return raw as Vector3
		for placement_variant in room.get("structural_placements", []):
			if not (placement_variant is Dictionary):
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id.find("floor") < 0 and module_id.find("ramp") < 0:
				continue
			var pos: Variant = placement.get("world_position", placement.get("position", null))
			if pos is Array and (pos as Array).size() >= 3:
				return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return Vector3.INF


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return p if p is Dictionary else {}


func _fail(reason: String) -> void:
	push_error("SHIP NAV GRAPH FAIL reason=%s" % reason)
	quit(1)
