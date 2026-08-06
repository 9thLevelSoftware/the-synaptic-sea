extends RefCounted
class_name WallDoorResolver

## Compatibility facade for the pre-compiler resolver API.
##
## StructuralEdgeCompiler is the only authority for boundary ownership,
## positions, and poses. This class only converts the historical CellGrid input
## into the canonical layout contract and adapts canonical records back into the
## room-grouped shape expected by legacy serializer/debug callers.

const StructuralEdgePlanScript := preload("res://scripts/procgen/structural_edge_plan.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")


func resolve(cell_grid: Dictionary, room_plan: Array[Dictionary]) -> Dictionary:
	var canonical_layout: Dictionary = _legacy_layout_to_canonical(cell_grid, room_plan)
	var compiler = StructuralEdgeCompilerScript.new()
	var structural_plan: Dictionary = compiler.compile(canonical_layout)
	var validator = StructuralPlanValidatorScript.new()
	var verdict: Dictionary = validator.validate(structural_plan, canonical_layout)
	if not bool(verdict.get("ok", false)):
		push_error(
			"WALL DOOR RESOLVER FAIL canonical structural plan validation failed: %s"
			% JSON.stringify(verdict.get("errors", []))
		)
		return {}
	return _legacy_geometry_from_plan(structural_plan, canonical_layout)


func _legacy_layout_to_canonical(
		cell_grid: Dictionary,
		room_plan: Array[Dictionary]) -> Dictionary:
	var rooms: Array = []
	var raw_rooms: Variant = cell_grid.get("rooms", {})
	if raw_rooms is Dictionary:
		for room_key in raw_rooms.keys():
			var raw_room: Variant = raw_rooms[room_key]
			if not (raw_room is Dictionary):
				continue
			var room: Dictionary = (raw_room as Dictionary).duplicate(true)
			var room_id: String = String(room.get("id", room_key))
			room["id"] = room_id
			if not room.has("deck"):
				room["deck"] = _legacy_deck_for_room(room_id, room_plan)
			if not (room.get("cells", []) is Array):
				room["cells"] = []
			var role: String = _legacy_role_for_room(room_id, room_plan)
			if not role.is_empty() and not room.has("role"):
				room["role"] = role
			rooms.append(room)
	elif raw_rooms is Array:
		for raw_room in raw_rooms:
			if not (raw_room is Dictionary):
				continue
			var room: Dictionary = (raw_room as Dictionary).duplicate(true)
			var room_id: String = String(room.get("id", ""))
			if room_id.is_empty():
				continue
			if not room.has("deck"):
				room["deck"] = _legacy_deck_for_room(room_id, room_plan)
			if not (room.get("cells", []) is Array):
				room["cells"] = []
			var role: String = _legacy_role_for_room(room_id, room_plan)
			if not role.is_empty() and not room.has("role"):
				room["role"] = role
			rooms.append(room)

	return {
		"rooms": rooms,
		"portals": _legacy_portal_intents(cell_grid.get("adjacencies", []), rooms),
	}


func _legacy_portal_intents(raw_adjacencies: Variant, rooms: Array) -> Array:
	var portals: Array = []
	if not (raw_adjacencies is Array):
		return portals
	var index: int = 0
	for raw_adjacency in raw_adjacencies:
		if not (raw_adjacency is Dictionary):
			index += 1
			continue
		var adjacency: Dictionary = raw_adjacency
		var from_room: String = String(
			adjacency.get("from_room", adjacency.get("room_a", adjacency.get("from", "")))
		)
		var to_room: String = String(
				adjacency.get("to_room", adjacency.get("room_b", adjacency.get("to", "")))
			)
		var portal: Dictionary = {
			"id": "legacy-portal:%d" % index,
			"from_room": from_room,
			"to_room": to_room,
			"type": adjacency.get(
				"type", adjacency.get("portal_type", adjacency.get("kind", "DOOR"))
			),
			"required": bool(adjacency.get("required", false)),
		}
		var from_cell_result: Dictionary = _legacy_cell(adjacency.get("from_cell", null))
		var to_cell_result: Dictionary = _legacy_cell(adjacency.get("to_cell", null))
		if bool(from_cell_result.get("ok", false)) and bool(to_cell_result.get("ok", false)):
			var from_cell: Vector2i = from_cell_result["cell"]
			var to_cell: Vector2i = to_cell_result["cell"]
			var direction: String = _direction_for_delta(to_cell - from_cell)
			if direction.is_empty():
				# Retain malformed geometry as an explicit invalid intent. The
				# compiler will reject it rather than falling back to pair-only
				# placement.
				portal["cell"] = from_cell
				portal["direction"] = "invalid"
			else:
				portal["cell"] = from_cell
				portal["direction"] = direction
				portal["deck"] = _legacy_deck_for_room(from_room, rooms)
				portal["edge_key"] = StructuralEdgePlanScript.edge_key(
					int(portal["deck"]), from_cell, direction
				)
		elif adjacency.has("edge_key") or adjacency.has("required_edge"):
			portal["edge_key"] = adjacency.get(
				"edge_key", adjacency.get("required_edge", "")
			)
		portals.append(portal)
		index += 1
	return portals


func _legacy_geometry_from_plan(structural_plan: Dictionary, layout: Dictionary) -> Dictionary:
	var geometry: Dictionary = {}
	var rooms: Array = layout.get("rooms", [])
	for room_variant in rooms:
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		if room_id.is_empty():
			continue
		geometry[room_id] = {
			"wall_segments": [],
			"portals": [],
			"interior_zones": {
				"reserved_cells": [],
				"wall_slots": [],
				"center_slots": [],
			},
		}

	var edges: Variant = structural_plan.get("edges", {})
	if edges is Dictionary:
		for edge_variant in edges.values():
			if not (edge_variant is Dictionary):
				continue
			var edge: Dictionary = edge_variant
			var kind: String = String(edge.get("kind", edge.get("state", "")))
			if kind == "OPEN":
				continue
			var owner_room: String = String(edge.get("owner_room", ""))
			if owner_room.is_empty() or not geometry.has(owner_room):
				continue
			var room_geometry: Dictionary = geometry[owner_room]
			if kind == "SOLID":
				var walls: Array = room_geometry.get("wall_segments", [])
				walls.append(_legacy_wall_record(edge))
				room_geometry["wall_segments"] = walls
			elif kind in ["DOOR", "LOCKED", "HATCH", "BREACH"]:
				var portals: Array = room_geometry.get("portals", [])
				portals.append(_legacy_portal_record(edge))
				room_geometry["portals"] = portals
			geometry[owner_room] = room_geometry

	_populate_legacy_interior_zones(geometry, structural_plan, rooms)
	return geometry


func _legacy_wall_record(edge: Dictionary) -> Dictionary:
	var edge_key: String = String(edge.get("edge_key", ""))
	return {
		"id": String(edge.get("id", "edge:" + edge_key)),
		"name": "wall_edge_%s" % edge_key.replace("|", "_"),
		"module_id": String(edge.get("module_id", "wall_straight_1x1")),
		"position": edge.get("position", Vector3.ZERO),
		"yaw_degrees": float(edge.get("yaw_degrees", 0.0)),
		"cell": edge.get("cell", Vector2i.ZERO),
		"direction": String(edge.get("direction", "")),
		"edge_key": edge_key,
		"room_id": String(edge.get("owner_room", "")),
	}


func _legacy_portal_record(edge: Dictionary) -> Dictionary:
	var source_cells: Array = edge.get("source_cells", [])
	var from_cell: Variant = source_cells[0] if source_cells.size() > 0 else edge.get("cell", Vector2i.ZERO)
	var to_cell: Variant = source_cells[1] if source_cells.size() > 1 else Vector2i.ZERO
	var owner_room: String = String(edge.get("owner_room", ""))
	return {
		"id": String(edge.get("id", "")),
		"portal_id": String(edge.get("id", "")),
		"edge_key": String(edge.get("edge_key", "")),
		"wall": String(edge.get("direction", "")),
		"direction": String(edge.get("direction", "")),
		"module_id": String(edge.get("module_id", "")),
		"position": edge.get("position", Vector3.ZERO),
		"yaw_degrees": float(edge.get("yaw_degrees", 0.0)),
		"from_room": owner_room,
		"to_room": String(edge.get("other_room", "")),
		"from_cell": from_cell,
		"to_cell": to_cell,
		"kind": String(edge.get("kind", "")),
		"room_ids": edge.get("room_ids", []),
	}


func _populate_legacy_interior_zones(
		geometry: Dictionary,
		structural_plan: Dictionary,
		rooms: Array) -> void:
	var wall_cells_by_room: Dictionary = {}
	var reserved_cells_by_room: Dictionary = {}
	var edges: Variant = structural_plan.get("edges", {})
	if edges is Dictionary:
		for edge_variant in edges.values():
			if not (edge_variant is Dictionary):
				continue
			var edge: Dictionary = edge_variant
			var owner_room: String = String(edge.get("owner_room", ""))
			if owner_room.is_empty():
				continue
			var kind: String = String(edge.get("kind", edge.get("state", "")))
			var cell: Variant = edge.get("cell", null)
			if kind == "SOLID":
				var wall_cells: Array = wall_cells_by_room.get(owner_room, [])
				_append_unique_cell(wall_cells, cell)
				wall_cells_by_room[owner_room] = wall_cells
			elif kind in ["DOOR", "LOCKED", "HATCH", "BREACH"]:
				var reserved_cells: Array = reserved_cells_by_room.get(owner_room, [])
				_append_unique_cell(reserved_cells, cell)
				reserved_cells_by_room[owner_room] = reserved_cells

	for room_variant in rooms:
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = String(room.get("id", ""))
		if room_id.is_empty() or not geometry.has(room_id):
			continue
		var room_geometry: Dictionary = geometry[room_id]
		var wall_cells: Array = wall_cells_by_room.get(room_id, [])
		var reserved_cells: Array = reserved_cells_by_room.get(room_id, [])
		var wall_slots: Array = []
		var center_slots: Array = []
		var raw_cells: Variant = room.get("cells", [])
		if raw_cells is Array:
			for cell in raw_cells:
				if reserved_cells.has(cell):
					continue
				if wall_cells.has(cell):
					wall_slots.append({"cell": cell, "against_wall": true})
				else:
					center_slots.append(cell)
		room_geometry["interior_zones"] = {
			"reserved_cells": reserved_cells,
			"wall_slots": wall_slots,
			"center_slots": center_slots,
		}
		geometry[room_id] = room_geometry


func _append_unique_cell(cells: Array, cell: Variant) -> void:
	if cell is Vector2i and not cells.has(cell):
		cells.append(cell)


func _legacy_role_for_room(room_id: String, room_plan: Array[Dictionary]) -> String:
	for room_variant in room_plan:
		var room: Dictionary = room_variant
		if String(room.get("id", "")) == room_id:
			return String(room.get("role", room.get("room_role", "")))
	return ""


func _legacy_deck_for_room(room_id: String, records: Variant) -> int:
	if records is Dictionary and records.has(room_id):
		var record: Variant = records[room_id]
		if record is Dictionary:
			return int((record as Dictionary).get("deck", 0))
	if records is Array:
		for record_variant in records:
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			if String(record.get("id", "")) == room_id:
				return int(record.get("deck", 0))
	return 0


func _legacy_cell(raw_cell: Variant) -> Dictionary:
	if raw_cell is Vector2i:
		return {"ok": true, "cell": raw_cell}
	if raw_cell is Array:
		var values: Array = raw_cell
		if values.size() == 2 and values[0] is int and values[1] is int:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	if raw_cell is Dictionary:
		var value: Dictionary = raw_cell
		if value.get("x", null) is int and value.get("y", null) is int:
			return {"ok": true, "cell": Vector2i(int(value["x"]), int(value["y"]))}
	return {"ok": false, "cell": Vector2i.ZERO}


func _direction_for_delta(delta: Vector2i) -> String:
	for direction_variant in StructuralEdgePlanScript.DIRECTIONS.keys():
		var direction: String = String(direction_variant)
		if StructuralEdgePlanScript.DIRECTIONS[direction] == delta:
			return direction
	return ""
