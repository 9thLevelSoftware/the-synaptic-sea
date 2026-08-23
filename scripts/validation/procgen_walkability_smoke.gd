extends SceneTree

## Stage A walkability (REQ-WALK-001 / ADR-0054).
## Marker: WALKABILITY PASS spine_seed_42 compiler_walls=true doorway=true no_void=true no_wall_through=true nav_kinds=true
## NavigationAgent is debug-only and is not the PASS contract.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const WalkabilityContractScript := preload("res://scripts/procgen/walkability_contract.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")


func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
	var label: String = "spine_seed_42"
	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		42)
	var layout: Dictionary = generator.generate(bp, {"template": "spine"})
	if layout.is_empty():
		_fail(label, "layout empty")
		return

	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
	var compiler_errors: Variant = structural_plan.get("errors", [])
	if not (compiler_errors is Array) or not (compiler_errors as Array).is_empty():
		_fail(label, "canonical compiler errors=%s" % JSON.stringify(compiler_errors))
		return
	var structural_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(structural_verdict.get("ok", false)):
		_fail(label, "canonical validator errors=%s" % JSON.stringify(structural_verdict.get("errors", [])))
		return

	var occupancy_variant: Variant = structural_plan.get("occupancy", null)
	var edges_variant: Variant = structural_plan.get("edges", null)
	if not (occupancy_variant is Dictionary) or (occupancy_variant as Dictionary).is_empty() \
			or not (edges_variant is Dictionary):
		_fail(label, "canonical occupancy/edges malformed")
		return
	var occupancy: Dictionary = occupancy_variant
	var edges: Dictionary = edges_variant

	var enclosure: Dictionary = WalkabilityContractScript.build_adjacency(occupancy, edges, layout, false)
	var start_key: String = str(occupancy.keys()[0])
	var enclosed: Dictionary = WalkabilityContractScript.flood_visited(enclosure, start_key)
	if enclosed.size() != occupancy.size():
		_fail(label, "enclosure flood connectivity=%d/%d" % [enclosed.size(), occupancy.size()])
		return

	var gameplay: Dictionary = slice_builder.build(layout)
	var start_room_id: String = str(gameplay.get("start_room", layout.get("prototype", {}).get("start_room", "")))
	var goal_room_id: String = str(gameplay.get("goal_room", layout.get("prototype", {}).get("goal_room", "")))
	if start_room_id.is_empty() or goal_room_id.is_empty():
		_fail(label, "missing start/goal room")
		return
	var standing: Dictionary = WalkabilityContractScript.build_adjacency(occupancy, edges, layout, true)
	if not WalkabilityContractScript.rooms_reachable(standing, occupancy, start_room_id, goal_room_id):
		_fail(label, "standing start→goal unreachable")
		return
	var path_keys: Array[String] = WalkabilityContractScript.standing_path_keys(
		standing, occupancy, start_room_id, goal_room_id)
	if path_keys.is_empty():
		_fail(label, "standing path empty")
		return
	var void_key: String = WalkabilityContractScript.standing_void_reason(structural_plan, occupancy, path_keys)
	if not void_key.is_empty():
		_fail(label, "void at %s" % void_key)
		return

	var doorway_ok: bool = false
	var solid_fixture_edge: Dictionary = {}
	for edge_variant in edges.values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = WalkabilityContractScript.edge_kind(edge)
		if kind == "SOLID":
			if not WalkabilityContractScript.capsule_hits_solid_slab(edge, occupancy):
				_fail(label, "wall_through edge=%s" % str(edge.get("edge_key", edge.get("key", ""))))
				return
			if solid_fixture_edge.is_empty():
				solid_fixture_edge = edge
		elif kind == "DOOR" or kind == "HATCH":
			if not WalkabilityContractScript.capsule_passes_door_opening(edge, occupancy):
				_fail(label, "doorway_clearance edge=%s" % str(edge.get("edge_key", edge.get("key", ""))))
				return
			doorway_ok = true
		elif kind == "LOCKED":
			if not WalkabilityContractScript.capsule_hits_solid_slab(edge, occupancy):
				_fail(label, "locked opening passable edge=%s" % str(edge.get("edge_key", edge.get("key", ""))))
				return
			if WalkabilityContractScript.capsule_passes_door_opening(edge, occupancy):
				_fail(label, "locked doorway hole passable edge=%s" % str(edge.get("edge_key", edge.get("key", ""))))
				return

	if not doorway_ok:
		_fail(label, "no DOOR/HATCH opening tested")
		return
	if solid_fixture_edge.is_empty():
		_fail(label, "no SOLID edge for extrusion fixtures")
		return
	if WalkabilityContractScript.capsule_hits_zero_thickness_fixture(solid_fixture_edge, occupancy):
		_fail(label, "zero-thickness slab fixture must FAIL")
		return
	if WalkabilityContractScript.capsule_hits_cell_center_aabb_fixture(solid_fixture_edge, occupancy):
		_fail(label, "cell-center AABB fixture must FAIL")
		return

	var graph = ShipNavGraphScript.new()
	layout["structural_plan"] = structural_plan
	var node_n: int = graph.build_from_layout(layout)
	if node_n < occupancy.size():
		_fail(label, "nav nodes %d < occupancy %d" % [node_n, occupancy.size()])
		return
	if not _nav_kinds_ok(graph, edges, occupancy):
		_fail(label, "nav_kinds mismatch")
		return

	print("WALKABILITY PASS %s compiler_walls=true doorway=true no_void=true no_wall_through=true nav_kinds=true" % label)
	quit(0)


func _nav_kinds_ok(graph, edges: Dictionary, occupancy: Dictionary) -> bool:
	for edge_variant in edges.values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = WalkabilityContractScript.edge_kind(edge)
		var pair: PackedStringArray = _graph_keys_for_edge(graph, edge, occupancy)
		if pair.size() != 2:
			if kind == "SOLID":
				continue
			if kind == "LOCKED" or kind == "BREACH" or kind == "OPEN" or kind == "DOOR" or kind == "HATCH":
				# Exterior / one-sided compiler edges have no standing graph hop.
				continue
			return false
		var cost: float = graph.edge_cost(pair[0], pair[1])
		if kind == "SOLID":
			if graph._base_edges.has(graph._edge_key(pair[0], pair[1])) \
					and cost < ShipNavGraphScript.BLOCKED_COST:
				return false
		elif kind == "LOCKED" or kind == "BREACH":
			if not graph._base_edges.has(graph._edge_key(pair[0], pair[1])):
				return false
			if cost < ShipNavGraphScript.BLOCKED_COST:
				return false
		elif kind == "OPEN" or kind == "DOOR" or kind == "HATCH":
			if cost >= ShipNavGraphScript.BLOCKED_COST:
				return false
	return true


func _graph_keys_for_edge(graph, edge: Dictionary, occupancy: Dictionary) -> PackedStringArray:
	var source_cells: Variant = edge.get("source_cells", [])
	if not (source_cells is Array) or (source_cells as Array).size() < 2:
		return PackedStringArray()
	var deck: int = int(edge.get("deck", 0))
	var a: String = graph._node_key_from_cell((source_cells as Array)[0], deck, occupancy)
	var b: String = graph._node_key_from_cell((source_cells as Array)[1], deck, occupancy)
	if a.is_empty() or b.is_empty() or a == b:
		return PackedStringArray()
	return PackedStringArray([a, b])


func _fail(label: String, reason: String) -> void:
	push_error("WALKABILITY FAIL %s reason=%s" % [label, reason])
	quit(1)
