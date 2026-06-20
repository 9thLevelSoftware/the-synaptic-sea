extends SceneTree

# Derelict generator smoke. Verifies:
#   1. Derelict archetype loads and produces valid graphs
#   2. Every generated derelict has exactly one dock room
#   3. All derelict rooms use derelict roles (no system roles)
#   4. Graph is connected
#   5. Room count is in range
#   6. Determinism: same seed = same graph

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const DERELICT_PATH: String = "res://data/procgen/archetypes/derelict.json"

const SYSTEM_ROLES: Array[String] = [
	"airlock", "engineering", "life_support", "bridge",
	"cargo", "crew_quarters", "medical", "maintenance",
]


func _initialize() -> void:
	# Load archetype.
	var file := FileAccess.open(DERELICT_PATH, FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var archetype: Dictionary = json.data
	var bp_data: Dictionary = archetype.get("blueprint", {})

	var graph_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var gen: ShipGeneratorScript = ShipGeneratorScript.new()

	# Test across many seeds.
	var failures: Array[String] = []
	for seed_val in range(100):
		bp_data["seed_value"] = seed_val
		var bp = ShipBlueprintScript.from_dict(bp_data)
		var graph: RoomGraphScript = graph_gen.generate(bp, archetype)

		# 1. Connected.
		if not graph.is_fully_connected():
			failures.append("seed=%d disconnected" % seed_val)
			continue

		# 2. Room count in range.
		var lo: int = int(bp.room_count_range.x)
		var hi: int = int(bp.room_count_range.y)
		if graph.rooms.size() < lo or graph.rooms.size() > hi:
			failures.append("seed=%d rooms=%d not in [%d,%d]" % [
				seed_val, graph.rooms.size(), lo, hi])
			continue

		# 3. Exactly one dock.
		var dock_count: int = 0
		for room in graph.rooms:
			if String(room["role"]) == "dock":
				dock_count += 1
		if dock_count != 1:
			failures.append("seed=%d docks=%d expected=1" % [seed_val, dock_count])
			continue

		# 4. No system roles.
		var bad_roles: Array[String] = []
		for room in graph.rooms:
			var role: String = String(room["role"])
			if role in SYSTEM_ROLES:
				bad_roles.append(role)
		if not bad_roles.is_empty():
			failures.append("seed=%d has system roles: %s" % [seed_val, str(bad_roles)])
			continue

		# 5. Full pipeline (ShipGenerator).
		var ship: Node3D = gen.generate(bp, archetype)
		if ship == null:
			failures.append("seed=%d ShipGenerator returned null" % seed_val)
			continue

		var structure: Node = ship.get_child(0)
		if structure == null or structure.get_child_count() != graph.rooms.size():
			failures.append("seed=%d structure mismatch" % seed_val)
			continue

		ship.queue_free()

	# 6. Determinism.
	for seed_val in [42, 999, 7777]:
		bp_data["seed_value"] = seed_val
		var bp1 = ShipBlueprintScript.from_dict(bp_data)
		var bp2 = ShipBlueprintScript.from_dict(bp_data)
		var g1: RoomGraphScript = graph_gen.generate(bp1, archetype)
		var g2: RoomGraphScript = graph_gen.generate(bp2, archetype)
		if g1.rooms.size() != g2.rooms.size():
			failures.append("determinism seed=%d count mismatch" % seed_val)
		for i in range(min(g1.rooms.size(), g2.rooms.size())):
			if String(g1.rooms[i]["id"]) != String(g2.rooms[i]["id"]):
				failures.append("determinism seed=%d room[%d] mismatch" % [seed_val, i])
				break

	if failures.is_empty():
		print("DERELICT GENERATOR PASS seeds=100 determinism=3")
	else:
		for f in failures:
			push_error("DERELICT FAIL: %s" % f)
		print("DERELICT GENERATOR FAIL failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
