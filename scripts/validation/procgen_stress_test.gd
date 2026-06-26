extends SceneTree

# Stress test: run the full ShipGenerator pipeline across 200 seed/size/condition
# combinations and verify structural invariants on each.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

var failures: Array[String] = []
var total_runs: int = 0
var total_rooms: int = 0
var total_modules: int = 0


func _initialize() -> void:
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()

	# Test all 9 size x condition combinations across many seeds
	var sizes := [0, 1, 2]  # LIFE_BOAT, SMALL, MEDIUM
	var conditions := [0, 1, 2]  # PRISTINE, DAMAGED, WRECKED
	var seeds := []
	for i in range(200):
		seeds.append(i * 7 + 13)  # spread seeds

	for size in sizes:
		for condition in conditions:
			for seed_val in seeds:
				total_runs += 1
				_test_case(generator, size, condition, seed_val)

	# Determinism: pick 10 seeds and verify double-generation identity
	for i in range(10):
		var seed_val: int = 1000 + i * 37
		_test_determinism(generator, seed_val)

	# Report
	if failures.is_empty():
		print("PROCGEN STRESS PASS runs=%d total_rooms=%d total_modules=%d determinism=10" % [
			total_runs, total_rooms, total_modules])
	else:
		for f in failures:
			push_error("STRESS FAIL: %s" % f)
		print("PROCGEN STRESS FAIL runs=%d failures=%d" % [total_runs, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_case(gen: ShipGeneratorScript, size: int, condition: int, seed_val: int) -> void:
	var bp = ShipBlueprintScript.new(size, condition, seed_val)
	var graph_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var graph: RoomGraphScript = graph_gen.generate(bp)

	# 1. Room count in range
	var lo: int = int(bp.room_count_range.x)
	var hi: int = int(bp.room_count_range.y)
	if graph.rooms.size() < lo or graph.rooms.size() > hi:
		failures.append("seed=%d size=%d cond=%d rooms=%d not in [%d,%d]" % [
			seed_val, size, condition, graph.rooms.size(), lo, hi])
		return

	# 2. Graph is connected
	if not graph.is_fully_connected():
		failures.append("seed=%d size=%d cond=%d DISCONNECTED" % [seed_val, size, condition])
		return

	# 3. Exactly one airlock
	var airlocks := graph.get_rooms_by_role("airlock")
	if airlocks.size() != 1:
		failures.append("seed=%d size=%d cond=%d airlocks=%d" % [seed_val, size, condition, airlocks.size()])
		return

	# 4. Exactly one engineering
	var engineering := graph.get_rooms_by_role("engineering")
	if engineering.size() != 1:
		failures.append("seed=%d size=%d cond=%d engineering=%d" % [seed_val, size, condition, engineering.size()])
		return

	# 5. No duplicate room ids
	var seen_ids: Dictionary = {}
	for room in graph.rooms:
		var rid: String = String(room["id"])
		if seen_ids.has(rid):
			failures.append("seed=%d size=%d cond=%d duplicate room id: %s" % [seed_val, size, condition, rid])
			return
		seen_ids[rid] = true

	# 6. ShipGenerator end-to-end
	var ship: Node3D = gen.generate(bp)
	if ship == null:
		failures.append("seed=%d size=%d cond=%d ShipGenerator returned null" % [seed_val, size, condition])
		return
	if String(ship.name) != "GeneratedShip":
		failures.append("seed=%d size=%d cond=%d ship.name=%s" % [seed_val, size, condition, str(ship.name)])
		return
	var structure: Node = ship.get_child(0)
	if structure == null or String(structure.name) != "ShipStructure":
		failures.append("seed=%d size=%d cond=%d no ShipStructure" % [seed_val, size, condition])
		return
	if structure.get_child_count() != graph.rooms.size():
		failures.append("seed=%d size=%d cond=%d structure_children=%d graph_rooms=%d" % [
			seed_val, size, condition, structure.get_child_count(), graph.rooms.size()])
		return

	total_rooms += graph.rooms.size()
	total_modules += structure.get_child_count()

	# Free the ship to avoid RID leaks
	ship.queue_free()


func _test_determinism(gen: ShipGeneratorScript, seed_val: int) -> void:
	var bp1 = ShipBlueprintScript.new(1, 1, seed_val)  # SMALL, DAMAGED
	var bp2 = ShipBlueprintScript.new(1, 1, seed_val)

	var graph_gen: RoomGraphGeneratorScript = RoomGraphGeneratorScript.new()
	var g1: RoomGraphScript = graph_gen.generate(bp1)
	var g2: RoomGraphScript = graph_gen.generate(bp2)

	if g1.rooms.size() != g2.rooms.size():
		failures.append("determinism seed=%d room count mismatch %d vs %d" % [
			seed_val, g1.rooms.size(), g2.rooms.size()])
		return

	if g1.links.size() != g2.links.size():
		failures.append("determinism seed=%d link count mismatch %d vs %d" % [
			seed_val, g1.links.size(), g2.links.size()])
		return

	# Compare room ids in order
	for i in range(g1.rooms.size()):
		if String(g1.rooms[i]["id"]) != String(g2.rooms[i]["id"]):
			failures.append("determinism seed=%d room[%d] id mismatch %s vs %s" % [
				seed_val, i, String(g1.rooms[i]["id"]), String(g2.rooms[i]["id"])])
			return
		if String(g1.rooms[i]["role"]) != String(g2.rooms[i]["role"]):
			failures.append("determinism seed=%d room[%d] role mismatch %s vs %s" % [
				seed_val, i, String(g1.rooms[i]["role"]), String(g2.rooms[i]["role"])])
			return
