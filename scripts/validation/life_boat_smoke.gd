extends SceneTree

# Life boat smoke. Verifies the fixed life boat layout:
#   1. Builds successfully
#   2. Has exactly 3 rooms (airlock, cockpit, engine_bay)
#   3. Structure has 3 room nodes
#   4. Graph is connected
#   5. Room roles are correct
#   6. Always identical (deterministic by design)

const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")


func _initialize() -> void:
	# Build the life boat.
	var life_boat: Node3D = LifeBoatBuilderScript.build()
	if life_boat == null:
		push_error("LIFE BOAT FAIL build returned null")
		quit(1)
		return

	if String(life_boat.name) != "LifeBoat":
		push_error("LIFE BOAT FAIL name=%s" % str(life_boat.name))
		quit(1)
		return

	# Check structure.
	var structure: Node = life_boat.get_child(0)
	if structure == null or String(structure.name) != "ShipStructure":
		push_error("LIFE BOAT FAIL no ShipStructure")
		quit(1)
		return

	if structure.get_child_count() != 3:
		push_error("LIFE BOAT FAIL rooms=%d expected=3" % structure.get_child_count())
		quit(1)
		return

	# Check room names.
	var expected_rooms: Array[String] = ["airlock_01", "cockpit_01", "engine_bay_01"]
	for i in range(3):
		var child: Node = structure.get_child(i)
		if child == null or String(child.name) != expected_rooms[i]:
			push_error("LIFE BOAT FAIL room[%d]=%s expected=%s" % [
				i, str(child.name) if child else "null", expected_rooms[i]])
			quit(1)
			return

	# Check graph.
	var graph = LifeBoatBuilderScript.build_graph()
	if not graph.is_fully_connected():
		push_error("LIFE BOAT FAIL graph disconnected")
		quit(1)
		return

	if graph.rooms.size() != 3:
		push_error("LIFE BOAT FAIL graph rooms=%d expected=3" % graph.rooms.size())
		quit(1)
		return

	if graph.links.size() != 2:
		push_error("LIFE BOAT FAIL graph links=%d expected=2" % graph.links.size())
		quit(1)
		return

	# Check airlock node accessor.
	var airlock: Node3D = LifeBoatBuilderScript.get_airlock_node(life_boat)
	if airlock == null:
		push_error("LIFE BOAT FAIL get_airlock_node returned null")
		quit(1)
		return
	if String(airlock.name) != "airlock_01":
		push_error("LIFE BOAT FAIL airlock name=%s" % str(airlock.name))
		quit(1)
		return

	# Build twice to verify determinism.
	var life_boat2: Node3D = LifeBoatBuilderScript.build()
	var s1: Node = life_boat.get_child(0)
	var s2: Node = life_boat2.get_child(0)
	for i in range(3):
		if String(s1.get_child(i).name) != String(s2.get_child(i).name):
			push_error("LIFE BOAT FAIL determinism room[%d]" % i)
			quit(1)
			return

	print("LIFE BOAT PASS rooms=3 connected=true airlock_accessible=true deterministic=true")
	quit(0)
