extends RefCounted
class_name StructuralEdgePlan

## Canonical, data-only structural grid helpers.
##
## Cells are addressed by integer (x, y) coordinates on an integer deck. A
## boundary is identified geometrically, rather than by the room that happened
## to be visited first, so both sides of a shared edge produce one edge ID.

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

const DIRECTIONS := {
	"north": Vector2i(0, -1),
	"east": Vector2i(1, 0),
	"south": Vector2i(0, 1),
	"west": Vector2i(-1, 0),
}
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}
const YAW_DEGREES := {"south": 0.0, "west": 90.0, "north": 180.0, "east": 270.0}


## Returns the stable identity of an occupied grid cell.
static func cell_key(deck: int, cell: Vector2i) -> String:
	return "%d|%d|%d" % [deck, cell.x, cell.y]


## Returns a geometry-derived identity for a cardinal cell boundary.
##
## Horizontal boundaries use the lower z/grid-y line and x span. Vertical
## boundaries use the y/grid-z line and the lower x span. Consequently, the
## edge from (x, y) east is identical to the edge from (x + 1, y) west, and
## likewise for north/south traversal.
static func edge_key(deck: int, cell: Vector2i, direction: String) -> String:
	assert(DIRECTIONS.has(direction), "unknown edge direction: %s" % direction)
	if not DIRECTIONS.has(direction):
		return ""
	var delta: Vector2i = DIRECTIONS[direction]
	var neighbor := cell + delta
	if direction == "north" or direction == "south":
		return "%d|h|%d|%d" % [deck, min(cell.y, neighbor.y), cell.x]
	return "%d|v|%d|%d" % [deck, cell.y, min(cell.x, neighbor.x)]


## Returns the center of a cell's requested boundary in world coordinates.
##
## Structural module local axes use south as the zero-yaw pose. The world
## position is still derived exclusively from the integer cell and direction;
## no visual bounds or floating-point orientation inference is involved.
static func edge_world_position(deck: int, cell: Vector2i, direction: String) -> Vector3:
	assert(DIRECTIONS.has(direction), "unknown edge direction: %s" % direction)
	if not DIRECTIONS.has(direction):
		return Vector3.ZERO
	var center := Vector3(
		float(cell.x) * CELL_SIZE,
		float(deck) * DECK_HEIGHT,
		float(cell.y) * CELL_SIZE,
	)
	var delta: Vector2i = DIRECTIONS[direction]
	return center + Vector3(
		float(delta.x) * CELL_SIZE * 0.5,
		0.0,
		float(delta.y) * CELL_SIZE * 0.5,
	)


## Creates a normalized occupied-cell record for compiler/validator consumers.
static func make_cell(deck: int, cell: Vector2i, room_id: String) -> Dictionary:
	var key := cell_key(deck, cell)
	return {
		"id": "cell:" + key,
		"key": key,
		"deck": deck,
		"cell": cell,
		"room_id": room_id,
		"position": Vector3(
			float(cell.x) * CELL_SIZE,
			float(deck) * DECK_HEIGHT,
			float(cell.y) * CELL_SIZE,
		),
	}


## Creates a canonical edge/placement record.
##
## `key` is expected to be the result of edge_key(). Its deck component is
## decoded only to derive the world position; identity remains the supplied
## canonical key. Source cells include both sides so validation can check
## reciprocity without reconstructing geometry from room ordering.
static func make_edge(key: String, kind: String, owner_room: String,
		other_room: String, cell: Vector2i, direction: String) -> Dictionary:
	assert(DIRECTIONS.has(direction), "unknown edge direction: %s" % direction)
	if not DIRECTIONS.has(direction):
		return {}
	var deck := _deck_from_edge_key(key)
	var delta: Vector2i = DIRECTIONS[direction]
	var neighbor := cell + delta
	var room_ids: Array[String] = [owner_room, other_room]
	var source_cells: Array[Vector2i] = [cell, neighbor]
	return {
		"id": "edge:" + key,
		"edge_key": key,
		"key": key,
		"module_id": _module_id_for_kind(kind),
		"kind": kind,
		"position": edge_world_position(deck, cell, direction),
		"yaw_degrees": float(YAW_DEGREES[direction]),
		"direction": direction,
		"opposite_direction": OPPOSITE[direction],
		"deck": deck,
		"cell": cell,
		"room_ids": room_ids,
		"owner_room": owner_room,
		"other_room": other_room,
		"source_cells": source_cells,
	}


static func _deck_from_edge_key(key: String) -> int:
	var parts := key.split("|")
	assert(parts.size() >= 4, "invalid canonical edge key: %s" % key)
	if parts.is_empty():
		return 0
	return int(parts[0])


static func _module_id_for_kind(kind: String) -> String:
	match kind:
		"SOLID":
			return "wall_straight_1x1"
		"DOOR":
			return "bulkhead_portal_2x1"
		"LOCKED":
			return "doorway_frame_blocked_1x1"
		"HATCH":
			return "doorway_frame_open_1x1"
		"BREACH":
			return ""
		"OPEN":
			return ""
		_:
			return ""
