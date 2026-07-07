extends SceneTree

const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

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

	if str(layout["schema_version"]) != "1.2.0":
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

	# --- Tranche 5 (audit LOW, layout_serializer.gd:71): portals must survive a
	# JSON round-trip as numeric data. The serializer used to copy the raw
	# portals array, so Vector3/Vector2i fields collapsed to opaque strings
	# ("(6.0, 0.0, 0.0)") under JSON.stringify.
	var reparsed: Variant = JSON.parse_string(JSON.stringify(layout))
	if not (reparsed is Dictionary):
		push_error("LAYOUT SERIALIZER FAIL layout did not survive JSON round-trip")
		quit(1)
		return
	var rp_rooms: Array = (reparsed as Dictionary).get("rooms", [])
	var rp_portals: Array = (rp_rooms[0] as Dictionary).get("portals", [])
	if rp_portals.size() != 1:
		push_error("LAYOUT SERIALIZER FAIL expected 1 portal on airlock after round-trip, got %d" % rp_portals.size())
		quit(1)
		return
	var rp_portal: Dictionary = rp_portals[0]
	var pp: Variant = rp_portal.get("position")
	if not (pp is Array) or (pp as Array).size() != 3 or float((pp as Array)[0]) != 6.0:
		push_error("LAYOUT SERIALIZER FAIL portal position stringified in JSON (got %s, expected [6,0,0])" % str(pp))
		quit(1)
		return
	var pfc: Variant = rp_portal.get("from_cell")
	var ptc: Variant = rp_portal.get("to_cell")
	if not (pfc is Array) or (pfc as Array).size() != 2 or int((pfc as Array)[0]) != 1 or int((pfc as Array)[1]) != 0:
		push_error("LAYOUT SERIALIZER FAIL portal from_cell stringified in JSON (got %s, expected [1,0])" % str(pfc))
		quit(1)
		return
	if not (ptc is Array) or (ptc as Array).size() != 2 or int((ptc as Array)[0]) != 2:
		push_error("LAYOUT SERIALIZER FAIL portal to_cell stringified in JSON (got %s, expected [2,0])" % str(ptc))
		quit(1)
		return

	# --- Tranche 5 (audit LOW, layout_serializer.gd:205): room_links must carry
	# the endpoint room's REAL deck, not a hardcoded 0. The loader's
	# _placement_matches_endpoint_cell reads endpoint[2] as the deck and matches
	# floor_cell_d<deck>_x_z placement names — a deck-1 link stamped 0 resolves
	# to Vector3.INF and silently drops the nav marker.
	var deck1_grid: Dictionary = {
		"rooms": {
			"upper_a": {
				"cells": [Vector2i(0, 0), Vector2i(1, 0)],
				"origin": Vector2i(0, 0), "footprint": Vector2i(2, 1), "deck": 1,
			},
			"upper_b": {
				"cells": [Vector2i(2, 0), Vector2i(3, 0)],
				"origin": Vector2i(2, 0), "footprint": Vector2i(2, 1), "deck": 1,
			},
		},
		"adjacencies": [
			{"from_room": "upper_a", "to_room": "upper_b",
			 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0)},
		],
	}
	var deck1_plan: Array[Dictionary] = [
		{"id": "upper_a", "role": "corridor", "zone_id": "upper", "deck": 1,
		 "position_hint": "bow", "target_cells": 2, "footprint": Vector2i(2, 1)},
		{"id": "upper_b", "role": "reactor", "zone_id": "upper", "deck": 1,
		 "position_hint": "stern", "target_cells": 2, "footprint": Vector2i(2, 1)},
	]
	var deck1_layout: Dictionary = serializer.serialize(deck1_grid, {}, deck1_plan, "stacked", 42, "test")
	var deck1_links: Array = deck1_layout.get("room_links", [])
	if deck1_links.size() != 1:
		push_error("LAYOUT SERIALIZER FAIL expected 1 deck-1 room_link, got %d" % deck1_links.size())
		quit(1)
		return
	var deck1_link: Dictionary = deck1_links[0]
	var from_arr: Array = deck1_link.get("from_cell", [])
	var to_arr: Array = deck1_link.get("to_cell", [])
	if from_arr.size() != 3 or int(from_arr[2]) != 1:
		push_error("LAYOUT SERIALIZER FAIL deck-1 link from_cell deck=%s expected 1 (hardcoded 0 at _build_room_links)" % str(from_arr))
		quit(1)
		return
	if to_arr.size() != 3 or int(to_arr[2]) != 1:
		push_error("LAYOUT SERIALIZER FAIL deck-1 link to_cell deck=%s expected 1 (hardcoded 0 at _build_room_links)" % str(to_arr))
		quit(1)
		return

	# Loader-side proof: the real endpoint resolver must find the deck-1 floor
	# placement (floor_cell_d1_x1_z0) instead of returning Vector3.INF.
	var loader := GeneratedShipLoaderScript.new()
	var resolved: Vector3 = loader._cell_world_from_link_endpoint(deck1_link, "from_cell", "from_room", deck1_layout)
	loader.free()
	if resolved == Vector3.INF:
		push_error("LAYOUT SERIALIZER FAIL loader could not resolve the deck-1 link endpoint (nav marker silently dropped)")
		quit(1)
		return
	if absf(resolved.x - 4.0) > 0.01 or absf(resolved.z - 0.0) > 0.01:
		push_error("LAYOUT SERIALIZER FAIL deck-1 endpoint resolved to wrong cell: %s" % str(resolved))
		quit(1)
		return

	print("LAYOUT SERIALIZER PASS keys=valid rooms=2 schema=1.2.0 golden_format=true prototype=valid critical_path=valid portals_json=true link_deck=true")
	quit(0)
