extends SceneTree

# Generate ships from all 3 archetypes WITH role weights and dump
# the room graph so we can inspect the improved role distributions.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const ARCHETYPES: Array[Dictionary] = [
	{"path": "res://data/procgen/archetypes/life_boat.json", "name": "life_boat"},
	{"path": "res://data/procgen/archetypes/small_freighter.json", "name": "small_freighter"},
	{"path": "res://data/procgen/archetypes/medium_cruiser.json", "name": "medium_cruiser"},
]


func _initialize() -> void:
	var graph_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var gen: ShipGeneratorScript = ShipGeneratorScript.new()

	# --- Archetypes with weights ---
	for archetype_def in ARCHETYPES:
		var file := FileAccess.open(archetype_def["path"], FileAccess.READ)
		var json := JSON.new()
		json.parse(file.get_as_text())
		file.close()
		var data: Dictionary = json.data
		var bp = ShipBlueprintScript.from_dict(data["blueprint"])
		var graph: RoomGraphScript = graph_gen.generate(bp, data)
		var ship: Node3D = gen.generate(bp, data)

		print("=== %s ===" % archetype_def["name"])
		print("  Rooms: %d  Links: %d  Connected: %s" % [
			graph.rooms.size(), graph.links.size(), str(graph.is_fully_connected())])

		# Role summary
		var role_counts: Dictionary = {}
		for room in graph.rooms:
			var role: String = String(room["role"])
			role_counts[role] = int(role_counts.get(role, 0)) + 1
		var role_str := ""
		for role in role_counts:
			if role_str != "":
				role_str += ", "
			role_str += "%s×%d" % [role, int(role_counts[role])]
		print("  Roles: %s" % role_str)

		# Room list with grid positions
		if ship != null:
			var structure: Node = ship.get_child(0)
			if structure != null:
				print("  Layout:")
				for room_node in structure.get_children():
					var pos: Vector3 = (room_node as Node3D).position
					print("    %s  world=(%.1f, %.1f, %.1f)  modules=%d" % [
						str(room_node.name), pos.x, pos.y, pos.z, room_node.get_child_count()])
			ship.queue_free()
		print("")

	# --- Medium cruiser seed variations ---
	print("=== medium_cruiser seed variations (with weights) ===")
	var cruiser_file := FileAccess.open("res://data/procgen/archetypes/medium_cruiser.json", FileAccess.READ)
	var cruiser_json := JSON.new()
	cruiser_json.parse(cruiser_file.get_as_text())
	cruiser_file.close()
	var cruiser_data: Dictionary = cruiser_json.data

	for seed_val in [42, 99, 777, 12345]:
		var bp = ShipBlueprintScript.new(2, 1, seed_val)
		var graph: RoomGraphScript = graph_gen.generate(bp, cruiser_data)
		var role_counts: Dictionary = {}
		for room in graph.rooms:
			var role: String = String(room["role"])
			role_counts[role] = int(role_counts.get(role, 0)) + 1
		var role_str := ""
		for role in role_counts:
			if role_str != "":
				role_str += ", "
			role_str += "%s×%d" % [role, int(role_counts[role])]
		print("  seed=%d rooms=%d roles=[%s]" % [
			seed_val, graph.rooms.size(), role_str])

	print("")
	print("SHIP DUMP v2 COMPLETE")
	quit(0)
