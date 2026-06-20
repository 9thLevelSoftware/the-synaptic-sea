extends SceneTree

# Archetype loading smoke. Loads all three archetype JSON files
# (life_boat, small_freighter, medium_cruiser), rebuilds a
# ShipBlueprint from each, runs the full ShipGenerator pipeline, and
# verifies the resulting ship is well-formed. Also round-trips each
# blueprint through to_dict / from_dict and confirms the rebuilt
# blueprint produces an identical ship (determinism across serialise
# boundary).
#
# This validates the contract that archetype JSON files are valid
# inputs to the procgen pipeline — something no other smoke covers.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const ARCHETYPES: Array[Dictionary] = [
	{"path": "res://data/procgen/archetypes/life_boat.json", "name": "life_boat", "min_rooms": 2, "max_rooms": 4, "size": 0},
	{"path": "res://data/procgen/archetypes/small_freighter.json", "name": "small_freighter", "min_rooms": 4, "max_rooms": 8, "size": 1},
	{"path": "res://data/procgen/archetypes/medium_cruiser.json", "name": "medium_cruiser", "min_rooms": 8, "max_rooms": 12, "size": 2},
]


func _initialize() -> void:
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	var graph_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()

	for archetype in ARCHETYPES:
		var path: String = archetype["path"]
		var name_str: String = archetype["name"]
		var min_rooms: int = archetype["min_rooms"]
		var max_rooms: int = archetype["max_rooms"]
		var expected_size: int = archetype["size"]

		# Load the JSON
		if not ResourceLoader.exists(path):
			push_error("ARCHETYPE SMOKE FAIL %s file not found: %s" % [name_str, path])
			quit(1)
			return

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("ARCHETYPE SMOKE FAIL %s cannot open: %s" % [name_str, path])
			quit(1)
			return
		var json_text: String = file.get_as_text()
		file.close()

		var json := JSON.new()
		var err := json.parse(json_text)
		if err != OK:
			push_error("ARCHETYPE SMOKE FAIL %s JSON parse error: %s" % [name_str, json.get_error_message()])
			quit(1)
			return

		var data: Dictionary = json.data
		if not data.has("blueprint"):
			push_error("ARCHETYPE SMOKE FAIL %s missing 'blueprint' key" % name_str)
			quit(1)
			return

		# Build blueprint from archetype
		var bp = ShipBlueprintScript.from_dict(data["blueprint"])
		if bp == null:
			push_error("ARCHETYPE SMOKE FAIL %s from_dict returned null" % name_str)
			quit(1)
			return

		if int(bp.size) != expected_size:
			push_error("ARCHETYPE SMOKE FAIL %s size=%d expected=%d" % [name_str, int(bp.size), expected_size])
			quit(1)
			return

		# Generate and validate
		var graph: RoomGraphScript = graph_gen.generate(bp)
		if not graph.is_fully_connected():
			push_error("ARCHETYPE SMOKE FAIL %s graph disconnected" % name_str)
			quit(1)
			return

		if graph.rooms.size() < min_rooms or graph.rooms.size() > max_rooms:
			push_error("ARCHETYPE SMOKE FAIL %s rooms=%d not in [%d,%d]" % [
				name_str, graph.rooms.size(), min_rooms, max_rooms])
			quit(1)
			return

		var ship: Node3D = generator.generate(bp)
		if ship == null:
			push_error("ARCHETYPE SMOKE FAIL %s ShipGenerator returned null" % name_str)
			quit(1)
			return

		if String(ship.name) != "GeneratedShip":
			push_error("ARCHETYPE SMOKE FAIL %s ship.name=%s" % [name_str, str(ship.name)])
			quit(1)
			return

		var structure: Node = ship.get_child(0)
		if structure == null or structure.get_child_count() != graph.rooms.size():
			push_error("ARCHETYPE SMOKE FAIL %s structure_children=%d graph_rooms=%d" % [
				name_str, structure.get_child_count() if structure else 0, graph.rooms.size()])
			quit(1)
			return

		# Round-trip: to_dict -> from_dict -> generate -> compare
		var bp_dict: Dictionary = bp.to_dict()
		var bp2 = ShipBlueprintScript.from_dict(bp_dict)
		var graph2: RoomGraphScript = graph_gen.generate(bp2)
		if graph2.rooms.size() != graph.rooms.size():
			push_error("ARCHETYPE SMOKE FAIL %s round-trip room count mismatch %d vs %d" % [
				name_str, graph2.rooms.size(), graph.rooms.size()])
			quit(1)
			return

		# Compare room ids in order (deterministic)
		for i in range(graph.rooms.size()):
			if String(graph.rooms[i]["id"]) != String(graph2.rooms[i]["id"]):
				push_error("ARCHETYPE SMOKE FAIL %s round-trip room[%d] mismatch %s vs %s" % [
					name_str, i, String(graph.rooms[i]["id"]), String(graph2.rooms[i]["id"])])
				quit(1)
				return

		ship.queue_free()

	print("ARCHETYPE LOAD PASS archetypes=3 round_trip=3")
	quit(0)
