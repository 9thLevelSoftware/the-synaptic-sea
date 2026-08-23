extends SceneTree

# Stress test: run the full ShipGenerator pipeline across 200 seed/size/condition
# combinations and verify structural invariants on each.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const StructuralEdgePlanScript := preload("res://scripts/procgen/structural_edge_plan.gd")

const CANONICAL_DERELICT_ARCHETYPE: Dictionary = {
	"name": "Derelict",
	"type": "derelict",
	"template": "derelict_a",
	"guaranteed_roles": [],
	"role_weights": {},
	"max_duplicates": 3,
}

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

	# 6. Canonical structural plan compilation and validation.
	var canonical_layout: Dictionary = ShipLayoutGeneratorScript.new().generate_with_options(
		bp, CANONICAL_DERELICT_ARCHETYPE, "", "", true)
	if canonical_layout.is_empty():
		failures.append("seed=%d size=%d cond=%d canonical layout empty" % [seed_val, size, condition])
		return
	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(canonical_layout)
	var compiler_errors: Variant = structural_plan.get("errors", [])
	if not (compiler_errors is Array) or not (compiler_errors as Array).is_empty():
		failures.append("seed=%d size=%d cond=%d canonical compiler errors=%s" % [
			seed_val, size, condition, JSON.stringify(compiler_errors)])
		return
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, canonical_layout)
	if not bool(verdict.get("ok", false)):
		failures.append("seed=%d size=%d cond=%d canonical validator errors=%s" % [
			seed_val, size, condition, JSON.stringify(verdict.get("errors", []))])
		return
	if not _canonical_plan_invariants(structural_plan, seed_val, size, condition):
		return

	total_rooms += graph.rooms.size()
	total_modules += (structural_plan.get("placements", []) as Array).size()


func _canonical_plan_invariants(plan: Dictionary, seed_val: int, size: int, condition: int) -> bool:
	var placements: Variant = plan.get("placements", null)
	var floor_placements: Variant = plan.get("floor_placements", null)
	var occupancy: Variant = plan.get("occupancy", null)
	var edges: Variant = plan.get("edges", null)
	if not (placements is Array) or not (floor_placements is Array) or (floor_placements as Array).is_empty():
		failures.append("seed=%d size=%d cond=%d missing floor_placements" % [seed_val, size, condition])
		return false
	if not (occupancy is Dictionary) or (occupancy as Dictionary).is_empty() or not (edges is Dictionary):
		failures.append("seed=%d size=%d cond=%d canonical occupancy/edges malformed" % [seed_val, size, condition])
		return false

	var seen_edges: Dictionary = {}
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			failures.append("seed=%d size=%d cond=%d placement is not a Dictionary" % [seed_val, size, condition])
			return false
		var placement: Dictionary = placement_variant
		var edge_key: String = str(placement.get("edge_key", ""))
		if edge_key.is_empty() or seen_edges.has(edge_key):
			failures.append("seed=%d size=%d cond=%d duplicate edge=%s" % [seed_val, size, condition, edge_key])
			return false
		seen_edges[edge_key] = true
	for floor_variant in floor_placements:
		if not (floor_variant is Dictionary) or str((floor_variant as Dictionary).get("module_id", "")).is_empty():
			failures.append("seed=%d size=%d cond=%d incomplete floor wrapper" % [seed_val, size, condition])
			return false

	# Canonical flood: every non-SOLID edge contributes a bidirectional cell link.
	var adjacency: Dictionary = {}
	for cell_key_variant in (occupancy as Dictionary).keys():
		adjacency[str(cell_key_variant)] = []
	for edge_variant in (edges as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("kind", edge.get("state", "SOLID"))).to_upper() == "SOLID":
			continue
		var source_cells: Variant = edge.get("source_cells", [])
		if not (source_cells is Array) or (source_cells as Array).size() != 2:
			continue
		var first: Dictionary = _read_cell((source_cells as Array)[0])
		var second: Dictionary = _read_cell((source_cells as Array)[1])
		if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
			continue
		var deck: int = int(edge.get("deck", -1))
		var first_key: String = StructuralEdgePlanScript.cell_key(deck, first["cell"])
		var second_key: String = StructuralEdgePlanScript.cell_key(deck, second["cell"])
		if adjacency.has(first_key) and adjacency.has(second_key):
			(adjacency[first_key] as Array).append(second_key)
			(adjacency[second_key] as Array).append(first_key)
	var start_key: String = str((occupancy as Dictionary).keys()[0])
	var visited: Dictionary = {start_key: true}
	var queue: Array[String] = [start_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_variant in (adjacency.get(current, []) as Array):
			var neighbor: String = str(neighbor_variant)
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	if visited.size() != (occupancy as Dictionary).size():
		failures.append("seed=%d size=%d cond=%d flood connectivity=%d/%d" % [
			seed_val, size, condition, visited.size(), (occupancy as Dictionary).size()])
		return false
	return true


func _read_cell(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "cell": value}
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		if typeof(values[0]) == TYPE_INT and typeof(values[1]) == TYPE_INT:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	return {"ok": false}


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
