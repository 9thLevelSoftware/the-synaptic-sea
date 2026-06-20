extends SceneTree

# RoomGraph smoke. Builds a connected 3-room graph (airlock → corridor
# → engineering), exercises every public method, verifies a
# disconnected graph is detected, and round-trips the graph through
# to_dict/from_dict. Prints a single PASS line on success; push_error +
# quit(1) on any failure path so a regression blocks the gate rather
# than silently passing.

const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")


func _initialize() -> void:
	# --- Case 1: connected 3-room graph ----------------------------
	var graph: RoomGraphScript = RoomGraphScript.new()
	graph.add_room("airlock_01", "airlock", 0)
	graph.add_room("corridor_01", "corridor", 0)
	graph.add_room("engineering_01", "engineering", 1)

	graph.add_link("airlock_01", "corridor_01")
	graph.add_link("corridor_01", "engineering_01")

	if graph.rooms.size() != 3:
		push_error("ROOM GRAPH FAIL rooms=%d expected=3" % graph.rooms.size())
		quit(1)
		return
	if graph.links.size() != 2:
		push_error("ROOM GRAPH FAIL links=%d expected=2" % graph.links.size())
		quit(1)
		return
	if not graph.is_fully_connected():
		push_error("ROOM GRAPH FAIL connected graph reported as disconnected")
		quit(1)
		return

	# Connected-room lookup. The corridor has two neighbours so both
	# must appear (order is unspecified; check membership not index).
	var corridor_neighbours: Array[String] = graph.get_connected_rooms("corridor_01")
	if corridor_neighbours.size() != 2:
		push_error("ROOM GRAPH FAIL corridor neighbours=%d expected=2" % corridor_neighbours.size())
		quit(1)
		return
	if not ("airlock_01" in corridor_neighbours):
		push_error("ROOM GRAPH FAIL airlock_01 missing from corridor neighbours=%s" % str(corridor_neighbours))
		quit(1)
		return
	if not ("engineering_01" in corridor_neighbours):
		push_error("ROOM GRAPH FAIL engineering_01 missing from corridor neighbours=%s" % str(corridor_neighbours))
		quit(1)
		return

	# Direct-room lookup and role filtering.
	var airlock_room: Dictionary = graph.get_room("airlock_01")
	if airlock_room.is_empty():
		push_error("ROOM GRAPH FAIL get_room(airlock_01) returned empty")
		quit(1)
		return
	if String(airlock_room["role"]) != "airlock":
		push_error("ROOM GRAPH FAIL airlock_01 role=%s expected=airlock" % str(airlock_room["role"]))
		quit(1)
		return

	var engineering_rooms: Array[Dictionary] = graph.get_rooms_by_role("engineering")
	if engineering_rooms.size() != 1:
		push_error("ROOM GRAPH FAIL engineering rooms=%d expected=1" % engineering_rooms.size())
		quit(1)
		return
	if String(engineering_rooms[0]["id"]) != "engineering_01":
		push_error("ROOM GRAPH FAIL engineering id=%s expected=engineering_01" % str(engineering_rooms[0]["id"]))
		quit(1)
		return

	# get_room on an unknown id returns {}; get_connected_rooms on an
	# unknown id returns [].
	if not graph.get_room("nope").is_empty():
		push_error("ROOM GRAPH FAIL get_room(unknown) did not return empty dict")
		quit(1)
		return
	if graph.get_connected_rooms("nope").size() != 0:
		push_error("ROOM GRAPH FAIL get_connected_rooms(unknown) did not return empty array")
		quit(1)
		return

	# --- Case 2: disconnected graph is detected -------------------
	var graph2: RoomGraphScript = RoomGraphScript.new()
	graph2.add_room("a", "airlock")
	graph2.add_room("b", "corridor")
	graph2.add_room("c", "engineering")  # intentionally isolated
	graph2.add_link("a", "b")
	if graph2.is_fully_connected():
		push_error("ROOM GRAPH FAIL disconnected graph reported as connected")
		quit(1)
		return

	# --- Case 3: empty graph is vacuously connected ---------------
	var graph_empty: RoomGraphScript = RoomGraphScript.new()
	if not graph_empty.is_fully_connected():
		push_error("ROOM GRAPH FAIL empty graph reported as disconnected")
		quit(1)
		return

	# --- Case 4: to_dict -> from_dict round-trip ------------------
	var payload: Dictionary = graph.to_dict()
	if not (payload.has("rooms") and payload.has("links")):
		push_error("ROOM GRAPH FAIL to_dict missing rooms/links keys")
		quit(1)
		return

	var rebuilt: RoomGraphScript = RoomGraphScript.from_dict(payload)
	if rebuilt.rooms.size() != 3:
		push_error("ROOM GRAPH FAIL round-trip rooms=%d expected=3" % rebuilt.rooms.size())
		quit(1)
		return
	if rebuilt.links.size() != 2:
		push_error("ROOM GRAPH FAIL round-trip links=%d expected=2" % rebuilt.links.size())
		quit(1)
		return
	if not rebuilt.is_fully_connected():
		push_error("ROOM GRAPH FAIL round-trip graph reported as disconnected")
		quit(1)
		return
	# Verify a specific field survived the round-trip (room role + deck).
	var rt_airlock: Dictionary = rebuilt.get_room("airlock_01")
	if String(rt_airlock["role"]) != "airlock" or int(rt_airlock["deck"]) != 0:
		push_error("ROOM GRAPH FAIL round-trip airlock role/deck drift: %s" % str(rt_airlock))
		quit(1)
		return
	var rt_eng: Dictionary = rebuilt.get_room("engineering_01")
	if int(rt_eng["deck"]) != 1:
		push_error("ROOM GRAPH FAIL round-trip engineering deck=%d expected=1" % int(rt_eng["deck"]))
		quit(1)
		return

	print("ROOM GRAPH PASS rooms=3 links=2 connected=true disconnected_detected=true serialization=true")
	quit(0)
