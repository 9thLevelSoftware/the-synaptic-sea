extends RefCounted
class_name WallDoorResolver

## Compatibility facade for callers that still provide the pre-canonical cell grid.
## StructuralEdgeCompiler is the only wall/portal boundary authority; this class
## only adapts its validated records to the legacy per-room geometry shape.

const StructuralEdgeCompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript: GDScript = preload("res://scripts/procgen/structural_plan_validator.gd")


func resolve(cell_grid: Dictionary, room_plan: Array[Dictionary]) -> Dictionary:
	var layout: Dictionary = _legacy_cell_grid_to_layout(cell_grid, room_plan)
	var compiler = StructuralEdgeCompilerScript.new()
	var plan: Dictionary = compiler.compile(layout)
	var validator = StructuralPlanValidatorScript.new()
	var verdict: Dictionary = validator.validate(plan, layout)
	if not bool(verdict.get("ok", false)):
		push_error("WALL DOOR RESOLVER FAIL structural plan validation failed: %s" % str(verdict.get("errors", [])))
		return {}
	return _adapt_validated_plan_to_legacy_geometry(plan, layout)


func _legacy_cell_grid_to_layout(cell_grid: Dictionary, room_plan: Array[Dictionary]) -> Dictionary:
	var room_roles: Dictionary = {}
	for room in room_plan:
		room_roles[str(room.get("id", ""))] = str(room.get("role", room.get("room_role", "")))

	var canonical_rooms: Array = []
	var room_decks: Dictionary = {}
	var rooms_variant: Variant = cell_grid.get("rooms", null)
	if typeof(rooms_variant) != TYPE_DICTIONARY:
		return {"rooms": canonical_rooms, "portals": []}
	var rooms: Dictionary = rooms_variant
	for room_id_variant in rooms.keys():
		var room_id: String = str(room_id_variant)
		var room_variant: Variant = rooms[room_id_variant]
		if typeof(room_variant) != TYPE_DICTIONARY:
			canonical_rooms.append({"id": room_id, "deck": -1, "cells": []})
			continue
		var room: Dictionary = room_variant
		var cells: Array = []
		var cells_variant: Variant = room.get("cells", null)
		if typeof(cells_variant) == TYPE_ARRAY:
			cells = (cells_variant as Array).duplicate(true)
		else:
			cells = [cells_variant]
		var deck_value: Variant = room.get("deck", 0)
		room_decks[room_id] = deck_value
		canonical_rooms.append({
			"id": room_id,
			"room_role": str(room_roles.get(room_id, room.get("role", ""))),
			"deck": deck_value,
			"cells": cells,
			"footprint": room.get("footprint", []),
		})

	var portals: Array = []
	var vertical_connections: Array = []
	var adjacencies_variant: Variant = cell_grid.get("adjacencies", [])
	if typeof(adjacencies_variant) == TYPE_ARRAY:
		for adjacency_variant in (adjacencies_variant as Array):
			if typeof(adjacency_variant) != TYPE_DICTIONARY:
				portals.append(adjacency_variant)
				continue
			var adjacency: Dictionary = adjacency_variant
			var from_room: String = str(adjacency.get("from_room", ""))
			var to_room: String = str(adjacency.get("to_room", ""))
			var portal: Dictionary = {
				"id": str(adjacency.get("id", "%s_to_%s" % [from_room, to_room])),
				"from_room": from_room,
				"to_room": to_room,
				"from_cell": adjacency.get("from_cell", null),
				"to_cell": adjacency.get("to_cell", null),
				"module_id": str(adjacency.get("module_id", "bulkhead_portal_2x1")),
				"state": str(adjacency.get("state", adjacency.get("portal_type", "DOOR"))).to_upper(),
			}
			if adjacency.has("exterior"):
				portal["exterior"] = adjacency["exterior"]
			var from_deck: Variant = room_decks.get(from_room, null)
			var to_deck: Variant = room_decks.get(to_room, null)
			if from_deck != null and to_deck != null and _is_integer(from_deck) and _is_integer(to_deck) and int(from_deck) != int(to_deck):
				vertical_connections.append({
					"id": portal["id"],
					"from_room": from_room,
					"to_room": to_room,
					"from_cell": portal["from_cell"],
					"to_cell": portal["to_cell"],
				})
			else:
				portals.append(portal)

	return {
		"cell_size": 4.0,
		"rooms": canonical_rooms,
		"portals": portals,
		"vertical_connections": vertical_connections,
	}


func _adapt_validated_plan_to_legacy_geometry(plan: Dictionary, layout: Dictionary) -> Dictionary:
	var geometry: Dictionary = {}
	var room_cells: Dictionary = {}
	var room_data: Dictionary = {}
	for room_variant in (layout.get("rooms", []) as Array):
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		room_cells[room_id] = []
		room_data[room_id] = {
			"walls": [],
			"portals": [],
			"reserved": [],
		}
		for cell_variant in (room.get("cells", []) as Array):
			var cell_info: Dictionary = _legacy_cell(cell_variant)
			if bool(cell_info.get("ok", false)):
				(room_cells[room_id] as Array).append(cell_info["cell"])

	var occupancy: Dictionary = plan.get("occupancy", {})
	for occupancy_variant in occupancy.values():
		if typeof(occupancy_variant) != TYPE_DICTIONARY:
			continue
		var occupancy_record: Dictionary = occupancy_variant
		var owner_room: String = str(occupancy_record.get("room_id", ""))
		if not room_data.has(owner_room):
			continue
		var cell_info: Dictionary = _legacy_cell(occupancy_record.get("cell", null))
		if bool(cell_info.get("ok", false)) and not (room_cells[owner_room] as Array).has(cell_info["cell"]):
			(room_cells[owner_room] as Array).append(cell_info["cell"])

	var edges: Dictionary = plan.get("edges", {})
	for edge_variant in edges.values():
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var owner_room: String = str(edge.get("owner_room", ""))
		if not room_data.has(owner_room):
			continue
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID")))
		if kind == "SOLID":
			(room_data[owner_room]["walls"] as Array).append(_legacy_wall(edge, owner_room))
		elif bool(edge.get("portal", false)):
			var portal: Dictionary = _legacy_portal(edge, owner_room)
			(room_data[owner_room]["portals"] as Array).append(portal)
			var portal_cell: Variant = portal.get("from_cell", null)
			if portal_cell is Vector2i and not (room_data[owner_room]["reserved"] as Array).has(portal_cell):
				(room_data[owner_room]["reserved"] as Array).append(portal_cell)

	for room_id_variant in room_data.keys():
		var room_id: String = str(room_id_variant)
		var state: Dictionary = room_data[room_id]
		var wall_segments: Array = state["walls"]
		var portals: Array = state["portals"]
		var reserved_cells: Array = state["reserved"]
		var wall_slot_cells: Array = []
		var center_cells: Array = []
		for cell_variant in (room_cells.get(room_id, []) as Array):
			var has_wall: bool = _has_cell_record(wall_segments, cell_variant)
			var has_portal: bool = _has_cell_record(portals, cell_variant, "from_cell")
			if has_wall and not has_portal:
				wall_slot_cells.append({"cell": cell_variant, "against_wall": true})
			elif not has_wall and not has_portal:
				center_cells.append(cell_variant)
		geometry[room_id] = {
			"wall_segments": wall_segments,
			"portals": portals,
			"interior_zones": {
				"reserved_cells": reserved_cells,
				"wall_slots": wall_slot_cells,
				"center_slots": center_cells,
			},
		}
	return geometry


func _legacy_wall(edge: Dictionary, room_id: String) -> Dictionary:
	var cell: Vector2i = edge.get("cell", Vector2i.ZERO)
	var direction: String = str(edge.get("direction", ""))
	return {
		"name": "wall_%s_%s_x%d_z%d" % [room_id, direction, cell.x, cell.y],
		"module_id": str(edge.get("module_id", "wall_straight_1x1")),
		"position": edge.get("position", Vector3.ZERO),
		"yaw_degrees": float(edge.get("yaw_degrees", 0.0)),
		"cell": cell,
		"direction": direction,
	}


func _legacy_portal(edge: Dictionary, owner_room: String) -> Dictionary:
	var source_cells: Array = edge.get("source_cells", []) if typeof(edge.get("source_cells", [])) == TYPE_ARRAY else []
	var from_cell: Vector2i = edge.get("cell", Vector2i.ZERO)
	var to_cell: Vector2i = Vector2i.ZERO
	if source_cells.size() >= 2:
		var first_info: Dictionary = _legacy_cell(source_cells[0])
		var second_info: Dictionary = _legacy_cell(source_cells[1])
		if bool(first_info.get("ok", false)):
			from_cell = first_info["cell"]
		if bool(second_info.get("ok", false)):
			to_cell = second_info["cell"]
	return {
		"id": str(edge.get("id", "edge:%s" % str(edge.get("edge_key", "")))),
		"wall": str(edge.get("direction", "")),
		"direction": str(edge.get("direction", "")),
		"module_id": str(edge.get("module_id", "bulkhead_portal_2x1")),
		"position": edge.get("position", Vector3.ZERO),
		"yaw_degrees": float(edge.get("yaw_degrees", 0.0)),
		"to_room": str(edge.get("other_room", "")),
		"from_room": owner_room,
		"from_cell": from_cell,
		"to_cell": to_cell,
		"edge_key": str(edge.get("edge_key", "")),
	}


func _has_cell_record(records: Array, cell: Variant, cell_key: String = "cell") -> bool:
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		if record.get(cell_key, null) == cell:
			return true
	return false


func _legacy_cell(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "cell": value}
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false}
	var values: Array = value
	if values.size() < 2 or not _is_integer(values[0]) or not _is_integer(values[1]):
		return {"ok": false}
	return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}


func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_equal_approx(float(value), roundf(float(value)))
	if typeof(value) == TYPE_STRING:
		return str(value).is_valid_int()
	return false
