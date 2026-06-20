extends SceneTree

const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")

func _initialize() -> void:
	# Minimal input: 2 rooms (airlock + reactor) already laid out
	var cell_grid: Dictionary = {
		"rooms": {
			"airlock_01": {
				"cells": [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
				"origin": Vector2i(0, 0),
				"footprint": Vector2i(2, 2),
				"deck": 0,
			},
			"reactor_01": {
				"cells": [Vector2i(2,0), Vector2i(3,0), Vector2i(2,1), Vector2i(3,1)],
				"origin": Vector2i(2, 0),
				"footprint": Vector2i(2, 2),
				"deck": 0,
			},
		},
		"adjacencies": [
			{"from_room": "airlock_01", "to_room": "reactor_01",
			 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0)},
		],
	}

	var geometry: Dictionary = {
		"airlock_01": {
			"wall_segments": [
				{"name": "wall_south_x0_z0", "module_id": "wall_straight_1x1",
				 "position": Vector3(0.0, 0.0, -2.0), "yaw_degrees": 0.0,
				 "cell": Vector2i(0, 0), "direction": "south"},
			],
			"portals": [
				{"id": "east_airlock_01_to_reactor_01", "wall": "east",
				 "module_id": "bulkhead_portal_2x1",
				 "position": Vector3(6.0, 0.0, 0.0), "yaw_degrees": 270.0,
				 "to_room": "reactor_01",
				 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0)},
			],
			"interior_zones": {
				"reserved_cells": [Vector2i(1, 0)],
				"wall_slots": [],
				"center_slots": [Vector2i(0, 1)],
			},
		},
		"reactor_01": {
			"wall_segments": [],
			"portals": [],
			"interior_zones": {"reserved_cells": [], "wall_slots": [], "center_slots": []},
		},
	}

	var room_plan: Array[Dictionary] = [
		{"id": "airlock_01", "role": "airlock", "zone_id": "entry", "deck": 0,
		 "position_hint": "bow", "target_cells": 4, "footprint": Vector2i(2, 2)},
		{"id": "reactor_01", "role": "reactor", "zone_id": "destination", "deck": 0,
		 "position_hint": "stern", "target_cells": 4, "footprint": Vector2i(2, 2)},
	]

	var serializer: LayoutSerializerScript = LayoutSerializerScript.new()
	var layout: Dictionary = serializer.serialize(cell_grid, geometry, room_plan, "spine", 42, "test")

	# --- Required top-level keys ---
	var required_keys: Array[String] = [
		"schema_version", "document_kind", "program_id", "kit_id",
		"design_intent", "cell_size", "rooms", "room_links",
		"blocked_links", "vertical_connections", "landmarks",
		"critical_path", "fire_zones", "arc_zones", "breach_zones", "prototype",
	]
	for key in required_keys:
		if not layout.has(key):
			push_error("LAYOUT SERIALIZER FAIL missing key: %s" % key)
			quit(1)
			return

	if str(layout["schema_version"]) != "1.1.0":
		push_error("LAYOUT SERIALIZER FAIL schema_version=%s" % str(layout["schema_version"]))
		quit(1)
		return

	if str(layout["document_kind"]) != "ship_layout":
		push_error("LAYOUT SERIALIZER FAIL document_kind=%s" % str(layout["document_kind"]))
		quit(1)
		return

	# Rooms must use room_role (not role) to match golden format
	var rooms: Array = layout["rooms"]
	if rooms.size() != 2:
		push_error("LAYOUT SERIALIZER FAIL rooms=%d expected=2" % rooms.size())
		quit(1)
		return

	var first_room: Dictionary = rooms[0]
	if not first_room.has("room_role"):
		push_error("LAYOUT SERIALIZER FAIL room missing room_role key")
		quit(1)
		return
	if str(first_room["room_role"]) != "airlock":
		push_error("LAYOUT SERIALIZER FAIL first room_role=%s expected=airlock" % str(first_room["room_role"]))
		quit(1)
		return

	# Structural placements must use world_position and module (golden format)
	if not first_room.has("structural_placements"):
		push_error("LAYOUT SERIALIZER FAIL room missing structural_placements")
		quit(1)
		return
	var placements: Array = first_room["structural_placements"]
	if placements.is_empty():
		push_error("LAYOUT SERIALIZER FAIL room has no structural_placements")
		quit(1)
		return
	var first_placement: Dictionary = placements[0]
	if not first_placement.has("world_position"):
		push_error("LAYOUT SERIALIZER FAIL placement missing world_position")
		quit(1)
		return
	if not first_placement.has("module"):
		push_error("LAYOUT SERIALIZER FAIL placement missing module key")
		quit(1)
		return

	# Empty gameplay arrays
	if not (layout["blocked_links"] is Array) or not layout["blocked_links"].is_empty():
		push_error("LAYOUT SERIALIZER FAIL blocked_links not empty array")
		quit(1)
		return
	if not (layout["fire_zones"] is Array) or not layout["fire_zones"].is_empty():
		push_error("LAYOUT SERIALIZER FAIL fire_zones not empty array")
		quit(1)
		return

	# Prototype must have start_room and goal_room
	var proto: Dictionary = layout["prototype"]
	if str(proto.get("start_room", "")) != "airlock_01":
		push_error("LAYOUT SERIALIZER FAIL start_room=%s" % str(proto.get("start_room", "")))
		quit(1)
		return
	if str(proto.get("goal_room", "")) != "reactor_01":
		push_error("LAYOUT SERIALIZER FAIL goal_room=%s" % str(proto.get("goal_room", "")))
		quit(1)
		return

	# Critical path must include start and goal
	var cp: Array = layout["critical_path"]
	if cp.is_empty():
		push_error("LAYOUT SERIALIZER FAIL critical_path empty")
		quit(1)
		return
	if str(cp[0]) != "airlock_01":
		push_error("LAYOUT SERIALIZER FAIL critical_path[0]=%s" % str(cp[0]))
		quit(1)
		return
	if str(cp[-1]) != "reactor_01":
		push_error("LAYOUT SERIALIZER FAIL critical_path[-1]=%s" % str(cp[-1]))
		quit(1)
		return

	print("LAYOUT SERIALIZER PASS keys=valid rooms=2 schema=1.1.0 golden_format=true prototype=valid critical_path=valid")
	quit(0)
