extends RefCounted
class_name RoomGraph

# Data class representing a ship's internal room topology as an
# undirected graph. The graph is the structural input consumed by
# StructuralPlacer (which lays down walls/floors per room) and
# GameplayPlacer (which drops systems/encounters by role). It carries
# no scene nodes — only room metadata and the links between rooms —
# so it can be serialised to JSON, regenerated deterministically from a
# ShipBlueprint seed, and unit-tested without instantiating a Node.
#
# Room dict schema: { "id": String, "role": String, "deck": int }
#   - id:   stable identifier unique within the graph (e.g. "airlock_01")
#   - role: gameplay category ("airlock", "corridor", "engineering", ...)
#   - deck: vertical deck index; 0 by default
#
# Link dict schema: { "from_room": String, "to_room": String, "type": String }
#   - from_room / to_room: room ids
#   - type:                "door" by default; "airlock", "ladder", etc. are
#                         reserved for Task 3+ placement semantics.

var rooms: Array[Dictionary] = []
var links: Array[Dictionary] = []


func add_room(room_id: String, role: String, deck: int = 0) -> void:
	rooms.append({"id": room_id, "role": role, "deck": deck})


func add_link(from_room: String, to_room: String, link_type: String = "door") -> void:
	links.append({"from_room": from_room, "to_room": to_room, "type": link_type})


# Returns the room dict for `room_id`, or an empty Dictionary if no such
# room exists. Callers should check `result.is_empty()` before reading
# fields; using a typed `Dictionary` return keeps the signature simple.
func get_room(room_id: String) -> Dictionary:
	for room in rooms:
		if room["id"] == room_id:
			return room
	return {}


# Returns the ids of every room directly linked to `room_id`, regardless
# of link direction (the graph is undirected for connectivity purposes).
# Returns an empty array if `room_id` is unknown or isolated.
func get_connected_rooms(room_id: String) -> Array[String]:
	var connected: Array[String] = []
	for link in links:
		if link["from_room"] == room_id:
			connected.append(link["to_room"])
		elif link["to_room"] == room_id:
			connected.append(link["from_room"])
	return connected


# True iff every room in the graph is reachable from the first room
# via links. The empty graph is vacuously connected. Implemented as a
# single BFS seeded at rooms[0] — O(V + E) over the small (≤ 12 room)
# ship graphs the generator produces.
#
# NOTE: named `is_fully_connected` rather than `is_connected` because
# `Object.is_connected(signal)` already exists on every RefCounted;
# reusing the name with a different signature would shadow the built-in
# and confuse both readers and the GDScript parser.
func is_fully_connected() -> bool:
	if rooms.is_empty():
		return true

	var visited: Dictionary = {}
	var queue: Array[String] = [rooms[0]["id"]]
	visited[rooms[0]["id"]] = true

	while not queue.is_empty():
		var current: String = queue.pop_front()
		for connected_id in get_connected_rooms(current):
			if not visited.has(connected_id):
				visited[connected_id] = true
				queue.append(connected_id)

	return visited.size() == rooms.size()


# Returns every room whose `role` matches the given string. Used by
# downstream placers that need, e.g., all "airlock" rooms to drop
# pressure seals.
func get_rooms_by_role(role: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room in rooms:
		if room["role"] == role:
			result.append(room)
	return result


# Serialises the graph to a plain Dictionary suitable for JSON.dump().
# The room and link dicts are stored verbatim, so to_dict/from_dict is
# the canonical fixture format.
func to_dict() -> Dictionary:
	return {"rooms": rooms, "links": links}


# Rebuilds a graph from a Dictionary produced by `to_dict()`. Missing
# fields fall back to safe defaults (deck=0, type="door") so a
# partially-corrupt fixture still loads. Self-reference to our own
# class_name isn't safe during initial compile, so we instantiate via
# load() with a cached script reference.
static func from_dict(data: Dictionary) -> RefCounted:
	var script: GDScript = load("res://scripts/procgen/room_graph.gd")
	var graph: RefCounted = script.new()
	var raw_rooms = data.get("rooms", [])
	if raw_rooms is Array:
		for room_data in raw_rooms:
			if not (room_data is Dictionary):
				continue
			var rid: String = String(room_data.get("id", ""))
			var rrole: String = String(room_data.get("role", ""))
			var rdeck: int = int(room_data.get("deck", 0))
			if rid.is_empty():
				continue
			graph.add_room(rid, rrole, rdeck)
	var raw_links = data.get("links", [])
	if raw_links is Array:
		for link_data in raw_links:
			if not (link_data is Dictionary):
				continue
			var fr: String = String(link_data.get("from_room", ""))
			var tr: String = String(link_data.get("to_room", ""))
			var lt: String = String(link_data.get("type", "door"))
			if fr.is_empty() or tr.is_empty():
				continue
			graph.add_link(fr, tr, lt)
	return graph
