extends SceneTree

const LifeBoatScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var builder: LifeBoatScript = LifeBoatScript.new()
	var layout: Dictionary = builder.build_layout()

	# Must have rooms array with exactly 3 rooms
	var rooms: Array = layout.get("rooms", [])
	if rooms.size() != 3:
		push_error("LIFE_BOAT_LAYOUT FAIL expected 3 rooms, got %d" % rooms.size())
		quit(1)
		return

	# Check expected roles
	var roles: Array[String] = []
	for room in rooms:
		roles.append(str(room.get("room_role", "")))
	var expected_roles: Array[String] = ["airlock", "bridge", "engineering"]
	for role in expected_roles:
		if role not in roles:
			push_error("LIFE_BOAT_LAYOUT FAIL missing role '%s', got %s" % [role, str(roles)])
			quit(1)
			return

	# Each room must have structural_placements
	for room in rooms:
		var placements: Array = room.get("structural_placements", [])
		if placements.is_empty():
			push_error("LIFE_BOAT_LAYOUT FAIL room '%s' has no structural_placements" % str(room.get("id", "")))
			quit(1)
			return
		# Each placement must have position array with 3 elements
		for p in placements:
			var pos: Variant = p.get("position", null)
			if not (pos is Array) or pos.size() < 3:
				push_error("LIFE_BOAT_LAYOUT FAIL bad position in room '%s'" % str(room.get("id", "")))
				quit(1)
				return

	# Must have room_links connecting all 3 rooms
	var links: Array = layout.get("room_links", [])
	if links.size() < 2:
		push_error("LIFE_BOAT_LAYOUT FAIL expected >=2 room_links, got %d" % links.size())
		quit(1)
		return

	# Must have prototype with start_room and goal_room
	var proto: Dictionary = layout.get("prototype", {})
	if str(proto.get("start_room", "")).is_empty():
		push_error("LIFE_BOAT_LAYOUT FAIL missing prototype.start_room")
		quit(1)
		return
	if str(proto.get("goal_room", "")).is_empty():
		push_error("LIFE_BOAT_LAYOUT FAIL missing prototype.goal_room")
		quit(1)
		return

	# Must have schema_version
	if str(layout.get("schema_version", "")).is_empty():
		push_error("LIFE_BOAT_LAYOUT FAIL missing schema_version")
		quit(1)
		return

	print("LIFE_BOAT_LAYOUT PASS 3 rooms, %d links, %d placements total" % [
		links.size(),
		rooms.reduce(func(acc, r): return acc + r.get("structural_placements", []).size(), 0)
	])
	quit(0)
