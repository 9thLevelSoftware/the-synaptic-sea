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
	# The walkability contract depends on the compiler's floor placement
	# bijection. Surface the floor_placements contract here so the smoke
	# doubles as a regression check that the canonical plan still exposes
	# a non-empty floor_placements array.
	var floor_placements_variant: Variant = structural_plan.get("floor_placements", null)
	if not (floor_placements_variant is Array) or (floor_placements_variant as Array).is_empty():
		_fail(label, "canonical floor_placements missing")
		return
	# Reject duplicate edge placements — the compiler guarantees a unique
	# edge_key per placement, so any duplicate here is a regression in the
	# canonical plan. Surface it so the smoke doubles as a duplicate-edge
	# regression check.
	var seen_edge_keys: Dictionary = {}
	for placement_variant in structural_plan.get("placements", []):
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var placement_edge_key: String = str((placement_variant as Dictionary).get("edge_key", ""))
		if placement_edge_key.is_empty():
			continue
		if seen_edge_keys.has(placement_edge_key):
			_fail(label, "duplicate edge placement=%s" % placement_edge_key)
			return
		seen_edge_keys[placement_edge_key] = true

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
	var void_key: String = WalkabilityContractScript.standing_void_reason(
		structural_plan, occupancy, path_keys, layout)
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
	if not _nav_kinds_ok(graph, edges, occupancy, layout):
		_fail(label, "nav_kinds mismatch")
		return

	print("WALKABILITY PASS %s compiler_walls=true doorway=true no_void=true no_wall_through=true nav_kinds=true" % label)
	quit(0)


func _nav_kinds_ok(graph, edges: Dictionary, occupancy: Dictionary, layout: Dictionary) -> bool:
	for edge_variant in edges.values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = WalkabilityContractScript.edge_kind(edge)
		var pair: PackedStringArray = graph.node_keys_for_edge(edge, occupancy, layout)
		if pair.size() != 2:
			if kind == "SOLID":
				continue
			var other_room: String = str(edge.get("other_room", ""))
			if other_room.is_empty() and (kind == "LOCKED" or kind == "BREACH" or kind == "OPEN" or kind == "DOOR" or kind == "HATCH"):
				# Exterior / one-sided compiler edges have no standing graph hop.
				continue
			return false
		var cost: float = graph.edge_cost(pair[0], pair[1])
		if kind == "SOLID":
			if graph.has_base_edge(pair[0], pair[1]) \
					and cost < ShipNavGraphScript.BLOCKED_COST:
				return false
		elif kind == "LOCKED" or kind == "BREACH":
			if not graph.has_base_edge(pair[0], pair[1]):
				return false
			if cost < ShipNavGraphScript.BLOCKED_COST:
				return false
		elif kind == "OPEN" or kind == "DOOR" or kind == "HATCH":
			if cost >= ShipNavGraphScript.BLOCKED_COST:
				return false
	return true


func _fail(label: String, reason: String) -> void:
	push_error("WALKABILITY FAIL %s reason=%s" % [label, reason])
	quit(1)
