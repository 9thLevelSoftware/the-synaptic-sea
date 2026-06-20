extends SceneTree

const WallDoorResolverScript := preload("res://scripts/procgen/wall_door_resolver.gd")

func _initialize() -> void:
	# Minimal 2-room layout: airlock(2x2) + corridor(1x2), adjacent on east edge
	var cell_grid: Dictionary = {
		"rooms": {
			"airlock_01": {
				"cells": [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
				"origin": Vector2i(0, 0),
				"footprint": Vector2i(2, 2),
				"deck": 0,
			},
			"corridor_01": {
				"cells": [Vector2i(2,0), Vector2i(2,1)],
				"origin": Vector2i(2, 0),
				"footprint": Vector2i(1, 2),
				"deck": 0,
			},
		},
		"adjacencies": [
			{"from_room": "airlock_01", "to_room": "corridor_01",
			 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0)},
		],
	}

	var room_plan: Array[Dictionary] = [
		{"id": "airlock_01", "role": "airlock", "zone_id": "entry", "deck": 0,
		 "position_hint": "bow", "target_cells": 4, "footprint": Vector2i(2, 2)},
		{"id": "corridor_01", "role": "corridor", "zone_id": "spine", "deck": 0,
		 "position_hint": "center", "target_cells": 2, "footprint": Vector2i(1, 2)},
	]

	var resolver: WallDoorResolverScript = WallDoorResolverScript.new()
	var geometry: Dictionary = resolver.resolve(cell_grid, room_plan)

	# Must have geometry for both rooms
	if not geometry.has("airlock_01"):
		push_error("WALL DOOR RESOLVER FAIL missing airlock_01 geometry")
		quit(1)
		return
	if not geometry.has("corridor_01"):
		push_error("WALL DOOR RESOLVER FAIL missing corridor_01 geometry")
		quit(1)
		return

	# Airlock should have walls on exposed edges
	var airlock_geo: Dictionary = geometry["airlock_01"]
	var airlock_walls: Array = airlock_geo.get("wall_segments", [])
	if airlock_walls.is_empty():
		push_error("WALL DOOR RESOLVER FAIL airlock has no walls")
		quit(1)
		return

	# Airlock should have at least one portal to corridor
	var airlock_portals: Array = airlock_geo.get("portals", [])
	if airlock_portals.is_empty():
		push_error("WALL DOOR RESOLVER FAIL airlock has no portals")
		quit(1)
		return

	# Portal should reference corridor
	var portal: Dictionary = airlock_portals[0]
	if str(portal.get("to_room", "")) != "corridor_01":
		push_error("WALL DOOR RESOLVER FAIL portal to_room=%s expected=corridor_01" % str(portal.get("to_room", "")))
		quit(1)
		return

	# Interior zones should exist
	if not airlock_geo.has("interior_zones"):
		push_error("WALL DOOR RESOLVER FAIL airlock missing interior_zones")
		quit(1)
		return

	# No wall should be placed where a portal exists (exposed edge facing corridor)
	# The airlock east edge at (1,0) faces corridor — should be portal, not wall
	for wall in airlock_walls:
		var wall_cell: Variant = wall.get("cell", null)
		var wall_dir: String = str(wall.get("direction", ""))
		if wall_cell is Vector2i and wall_cell == Vector2i(1, 0) and wall_dir == "east":
			push_error("WALL DOOR RESOLVER FAIL wall placed where portal should be at (1,0) east")
			quit(1)
			return

	print("WALL DOOR RESOLVER PASS walls=true portals=true interior=true no_conflict=true")
	quit(0)
