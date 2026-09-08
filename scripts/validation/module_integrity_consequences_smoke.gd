extends SceneTree

## PKG-B2.1b: fire→module damage, derived breaches, scene consequence contract.
## Marker: MODULE INTEGRITY CONSEQUENCES PASS fire=true breach_derived=true scene=true nav=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const LayoutMutatorScript := preload("res://scripts/procgen/layout_mutator.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")


func _initialize() -> void:
	# Consequence table
	var c_intact: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_INTACT)
	if not bool(c_intact.get("collision_enabled", false)):
		_fail("intact should collide")
		return
	var c_dest: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_DESTROYED)
	if bool(c_dest.get("collision_enabled", true)):
		_fail("destroyed should drop collision")
		return
	if not bool(c_dest.get("atmosphere_link", false)) or not bool(c_dest.get("nav_gap", false)):
		_fail("destroyed should open atmosphere + nav gap")
		return
	var c_breach: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_BREACHED)
	if not bool(c_breach.get("crawl_passable", false)):
		_fail("breached should be crawl-passable")
		return

	# Seed + fire damage
	var layout: Dictionary = {
		"rooms": [
			{
				"id": "eng_1",
				"room_role": "engineering",
				"structural_placements": [
					{"module_id": "wall_straight_1x1", "name": "wall_a", "world_position": [0, 0, 0]},
					{"module_id": "floor_1x1", "name": "floor_a", "world_position": [0, 0, 0]},
				],
			},
			{
				"id": "br_1",
				"room_role": "bridge",
				"structural_placements": [
					{"module_id": "bulkhead_portal_2x1", "name": "portal_a", "world_position": [4, 0, 0]},
				],
			},
		]
	}
	var map = ModuleIntegrityMapScript.new()
	var seeded: int = ModuleIntegrityConsequencesScript.seed_map_from_layout(map, layout)
	if seeded < 2:
		_fail("expected wall modules seeded, got %d" % seeded)
		return
	# floors should not be seeded as walls
	if map.has_module("eng_1/floor_a"):
		_fail("floor should not be wall-seeded")
		return

	var burning: Dictionary = {"engineering": 1.0}
	var roles: Dictionary = {"engineering": "engineering", "bridge": "bridge"}
	var changed: Array = []
	# Burn long enough to breach/destroy
	for _i in range(40):
		var step: Array = ModuleIntegrityConsequencesScript.apply_fire_damage(
			map, layout, burning, roles, 0.5, 0.2
		)
		for mid in step:
			if not changed.has(mid):
				changed.append(mid)
	if changed.is_empty():
		_fail("fire should change wall integrity")
		return
	var st: String = map.get_state("eng_1/wall_a")
	if st == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("engineering wall should not stay intact under fire")
		return

	# Compiler-keyed modules (edge/<key>) must take fire, not room/placement names.
	var compiled_layout: Dictionary = {
		"rooms": [{
			"id": "eng_1",
			"room_role": "engineering",
			"structural_placements": [
				{"module_id": "wall_straight_1x1", "name": "wall_a", "world_position": [0, 0, 0]},
			],
		}],
		"structural_plan": {
			"placements": [{
				"module_id": "wall_straight_1x1",
				"edge_key": "0|v|0|0",
				"room_id": "eng_1",
			}],
			"floor_placements": [],
			"ceiling_placements": [],
		},
	}
	var compiled_map = ModuleIntegrityMapScript.new()
	if ModuleIntegrityConsequencesScript.seed_map_from_compiled_layout(compiled_map, compiled_layout) < 1:
		_fail("compiled seed expected edge module")
		return
	var compiled_changed: Array = ModuleIntegrityConsequencesScript.apply_fire_damage(
		compiled_map, compiled_layout, burning, roles, 1.0, 1.0
	)
	if not compiled_changed.has("edge/0|v|0|0"):
		_fail("fire should damage compiler module_key edge/0|v|0|0, got %s" % str(compiled_changed))
		return
	if compiled_changed.has("eng_1/wall_a"):
		_fail("fire should not also stamp legacy placement id when compiled keys exist")
		return
	# Shared compiled wall: hotter neighboring compartment must win over room order.
	var shared_layout: Dictionary = {
		"rooms": [
			{"id": "eng_1", "room_role": "engineering"},
			{"id": "br_1", "room_role": "bridge"},
		],
		"structural_plan": {
			"placements": [{
				"module_id": "wall_straight_1x1",
				"edge_key": "shared|v|0|0",
				"room_id": "eng_1",
				"room_ids": ["eng_1", "br_1"],
			}],
			"floor_placements": [],
			"ceiling_placements": [],
		},
	}
	var shared_map = ModuleIntegrityMapScript.new()
	if ModuleIntegrityConsequencesScript.seed_map_from_compiled_layout(shared_map, shared_layout) < 1:
		_fail("shared compiled seed expected edge module")
		return
	var dual_burn: Dictionary = {"engineering": 0.1, "bridge": 1.0}
	ModuleIntegrityConsequencesScript.apply_fire_damage(shared_map, shared_layout, dual_burn, roles, 1.0, 1.0)
	var shared_mod = shared_map.get_module("edge/shared|v|0|0")
	if shared_mod == null:
		_fail("shared compiled wall missing after seed")
		return
	if float(shared_mod.integrity) > 0.05:
		_fail("shared wall should take max compartment intensity, integrity=%s" % str(shared_mod.integrity))
		return
	# Compile the vertex/span fixture through the production compiler. A two-cell
	# strip has corner placements and residual half-spans sharing a primary edge.
	var physical_source: Dictionary = {
		"schema_version": "ship-layout-v1",
		"kit_id": "ship_structural_v0",
		"rooms": [{
			"id": "strip",
			"deck": 0,
			"role": "room",
			"room_role": "room",
			"cells": [[0, 0, 0], [1, 0, 0]],
		}],
		"portals": [],
		"vertical_connections": [],
		"critical_path": [],
	}
	var physical_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(physical_source)
	var physical_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(physical_plan, physical_source)
	if not (physical_plan.get("errors", []) as Array).is_empty() or not bool(physical_verdict.get("ok", false)):
		_fail("physical compiler fixture should be valid")
		return
	var vertex_record: Dictionary = {}
	var span_record: Dictionary = {}
	var placements: Array = physical_plan.get("placements", []) as Array
	for candidate_v in placements:
		if not (candidate_v is Dictionary):
			continue
		var candidate: Dictionary = candidate_v
		if str(candidate.get("anchor_kind", "")) != "vertex":
			continue
		var primary_edge: String = str(candidate.get("edge_key", ""))
		for span_v in placements:
			if not (span_v is Dictionary):
				continue
			var span: Dictionary = span_v
			if str(span.get("anchor_kind", "")) == "half_span" \
					and str(span.get("edge_key", "")) == primary_edge:
				vertex_record = candidate
				span_record = span
				break
		if not span_record.is_empty():
			break
	if vertex_record.is_empty() or span_record.is_empty():
		_fail("compiler fixture should produce vertex/span placements sharing an edge")
		return
	var physical_layout: Dictionary = {"structural_plan": physical_plan}
	var physical_map = ModuleIntegrityMapScript.new()
	var expected_registered: int = placements.size() \
			+ (physical_plan.get("floor_placements", []) as Array).size() \
			+ (physical_plan.get("ceiling_placements", []) as Array).size()
	var physical_seeded: int = ModuleIntegrityConsequencesScript.seed_map_from_compiled_layout(physical_map, physical_layout, false)
	if physical_seeded != expected_registered:
		_fail("physical placement seed expected=%d got=%d" % [expected_registered, physical_seeded])
		return
	if physical_map.size() != expected_registered:
		_fail("physical placement map expected=%d got=%d" % [expected_registered, physical_map.size()])
		return
	var vertex_id: String = "edge/%s" % str(vertex_record.get("placement_id", ""))
	var span_id: String = "edge/%s" % str(span_record.get("placement_id", ""))
	var floor_record: Dictionary = _record_for_cell_key(
		physical_plan.get("floor_placements", []) as Array, "0|0|0")
	var ceiling_record: Dictionary = _record_for_cell_key(
		physical_plan.get("ceiling_placements", []) as Array, "0|0|0")
	if floor_record.is_empty() or ceiling_record.is_empty():
		_fail("physical compiler fixture should produce floor and ceiling records for 0|0|0")
		return
	var floor_id: String = "floor/0|0|0"
	var ceiling_id: String = "ceiling/0|0|0"
	var physical_identity_cases: Array[Dictionary] = [
		{
			"label": "vertex-owned half-span",
			"record": vertex_record,
			"layer": "edge",
			"expected": vertex_id,
		},
		{
			"label": "residual half-span",
			"record": span_record,
			"layer": "edge",
			"expected": span_id,
		},
		{
			"label": "floor",
			"record": floor_record,
			"layer": "floor",
			"expected": floor_id,
		},
		{
			"label": "ceiling",
			"record": ceiling_record,
			"layer": "ceiling",
			"expected": ceiling_id,
		},
	]
	for identity_case_v in physical_identity_cases:
		var identity_case: Dictionary = identity_case_v
		var identity_label: String = str(identity_case.get("label", ""))
		var identity_record: Dictionary = identity_case.get("record", {}) as Dictionary
		var identity_layer: String = str(identity_case.get("layer", ""))
		var expected_identity: String = str(identity_case.get("expected", ""))
		var public_identity: String = ModuleIntegrityConsequencesScript.compiled_module_id(
			identity_record, identity_layer)
		if public_identity != expected_identity or not physical_map.has_module(public_identity):
			_fail("public compiled identity should seed %s as %s, got %s" % [
				identity_label, expected_identity, public_identity])
			return
	if vertex_id == span_id or not physical_map.has_module(vertex_id) or not physical_map.has_module(span_id):
		_fail("physical placement seed lost distinct canonical identities")
		return
	var vertex_mod = physical_map.get_module(vertex_id)
	var span_mod = physical_map.get_module(span_id)
	if not _has_exact_compiler_owners(vertex_mod, vertex_record):
		_fail("vertex placement should retain every compiler owner room")
		return
	if not _has_exact_compiler_owners(span_mod, span_record):
		_fail("span placement should retain every compiler owner room")
		return
	physical_map.apply_damage(vertex_id, 0.30, str(vertex_record.get("module_id", "")))
	physical_map.apply_damage(span_id, 0.60, str(span_record.get("module_id", "")))
	var physical_summary: Dictionary = physical_map.get_summary()
	var sparse_deltas: Variant = physical_summary.get("deltas", [])
	if not (sparse_deltas is Array) or (sparse_deltas as Array).size() != 2:
		_fail("physical placement sparse deltas should retain two independent damages")
		return
	var physical_round_trip = ModuleIntegrityMapScript.new()
	if not physical_round_trip.apply_summary(physical_summary):
		_fail("physical placement sparse delta summary should load")
		return
	if physical_round_trip.get_state(vertex_id) != physical_map.get_state(vertex_id) or physical_round_trip.get_state(span_id) != physical_map.get_state(span_id):
		_fail("physical placement sparse deltas should round-trip independently")
		return
	# Deterministic one-record mutator fixtures preserve the compiler-produced
	# vertex/span records and prove each damage row uses the seeder's key.
	for mutator_record_v in [vertex_record, span_record]:
		var mutator_record: Dictionary = mutator_record_v as Dictionary
		var mutator_layout: Dictionary = {
			"structural_plan": {
				"placements": [mutator_record.duplicate(true)],
				"floor_placements": [],
				"ceiling_placements": [],
			},
		}
		if LayoutMutatorScript.apply_wreck_to_compiled_plan(mutator_layout, 19, null, 0.05) != 1:
			_fail("one-record mutator fixture should stamp its physical placement")
			return
		var mutator_damage: Variant = mutator_layout.get("module_damage", [])
		if not (mutator_damage is Array) or (mutator_damage as Array).size() != 1:
			_fail("one-record mutator should emit one physical damage row")
			return
		var mutator_row: Dictionary = (mutator_damage as Array)[0]
		var expected_mutator_id: String = "edge/%s" % str(mutator_record.get("placement_id", ""))
		if str(mutator_row.get("module_key", "")) != expected_mutator_id:
			_fail("mutator damage key should match its compiler placement identity")
			return
		var mutator_map = ModuleIntegrityMapScript.new()
		ModuleIntegrityConsequencesScript.seed_map_from_compiled_layout(mutator_map, mutator_layout)
		if mutator_map.get_state(expected_mutator_id) == ModuleIntegrityStateScript.STATE_INTACT:
			_fail("seeded mutator damage row should target its physical placement")
			return
	# A production-compiled portal retains the legacy full-edge identity.
	var canonical_source: Dictionary = {
		"schema_version": "ship-layout-v1",
		"kit_id": "ship_structural_v0",
		"rooms": [
			{"id": "port_a", "deck": 0, "role": "room", "room_role": "room", "cells": [[0, 0, 0]]},
			{"id": "port_b", "deck": 0, "role": "room", "room_role": "room", "cells": [[1, 0, 0]]},
		],
		"portals": [{
			"id": "canonical_portal",
			"from_room": "port_a",
			"to_room": "port_b",
			"from_cell": [0, 0, 0],
			"to_cell": [1, 0, 0],
			"state": "DOOR",
			"module_id": "doorway_frame_open_1x1",
			"edge_key": "0|v|0|0",
		}],
		"vertical_connections": [],
		"critical_path": [],
	}
	var canonical_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(canonical_source)
	var canonical_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(canonical_plan, canonical_source)
	if not (canonical_plan.get("errors", []) as Array).is_empty() or not bool(canonical_verdict.get("ok", false)):
		_fail("canonical full-edge compiler fixture should be valid compiler=%s validator=%s" % [
			JSON.stringify(canonical_plan.get("errors", [])),
			JSON.stringify(canonical_verdict.get("errors", [])),
		])
		return
	var canonical_record: Dictionary = {}
	for candidate_v in (canonical_plan.get("placements", []) as Array):
		if candidate_v is Dictionary and str((candidate_v as Dictionary).get("anchor_kind", "")) == "edge":
			canonical_record = candidate_v as Dictionary
			break
	var canonical_edge: String = str(canonical_record.get("edge_key", ""))
	var canonical_id: String = "edge/%s" % canonical_edge
	if canonical_record.is_empty() or str(canonical_record.get("placement_id", "")) != "edge:%s" % canonical_edge:
		_fail("canonical compiler fixture should emit a full-edge placement")
		return
	var canonical_map = ModuleIntegrityMapScript.new()
	ModuleIntegrityConsequencesScript.seed_map_from_compiled_layout(canonical_map, {"structural_plan": canonical_plan}, false)
	if not canonical_map.has_module(canonical_id) or canonical_map.has_module("edge/%s" % str(canonical_record.get("placement_id", ""))):
		_fail("canonical full edge should retain edge/<edge_key> identity")
		return
	var canonical_public_id: String = ModuleIntegrityConsequencesScript.compiled_module_id(canonical_record, "edge")
	if canonical_public_id != canonical_id or not canonical_map.has_module(canonical_public_id):
		_fail("public compiled identity should seed full edge as %s, got %s" % [
			canonical_id, canonical_public_id])
		return
	var breaches: int = ModuleIntegrityConsequencesScript.derived_breach_count(map)
	if breaches < 1 and st != ModuleIntegrityStateScript.STATE_DAMAGED:
		# damaged only is ok short-term; force more damage
		map.apply_damage("eng_1/wall_a", 1.0, "wall_straight_1x1")
		breaches = ModuleIntegrityConsequencesScript.derived_breach_count(map)
	if map.count_wall_breaches() < 1:
		map.apply_damage("eng_1/wall_a", 1.0, "wall_straight_1x1")
	if map.count_wall_breaches() < 1:
		_fail("expected wall breach count >= 1 after heavy damage")
		return

	# Scene node consequence
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	node.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "Col"
	node.add_child(col)
	get_root().add_child(node)
	ModuleIntegrityConsequencesScript.apply_to_node(node, ModuleIntegrityStateScript.STATE_DESTROYED)
	if not bool(node.get_meta("nav_gap", false)):
		_fail("node should have nav_gap meta")
		return
	if not col.disabled:
		_fail("destroyed should disable CollisionShape3D")
		return

	# Nav gap softens edges
	var nav = ShipNavGraphScript.new()
	var nav_layout: Dictionary = {
		"cell_size": 4.0,
		"deck_height": 4.0,
		"rooms": [
			{
				"id": "eng_1",
				"structural_placements": [
					{"module_id": "floor_1x1", "world_position": [0, 0, 0]},
					{"module_id": "floor_1x1", "world_position": [4, 0, 0]},
				],
			}
		]
	}
	nav.build_from_layout(nav_layout)
	if nav.node_count() >= 2:
		ModuleIntegrityConsequencesScript.apply_nav_gaps(nav, ["eng_1"])
	# snapshot includes module integrity via runtime
	var rt_script = load("res://scripts/systems/ship_runtime.gd")
	var ShipInstanceScript = load("res://scripts/systems/ship_instance.gd")
	var inst = ShipInstanceScript.create("mi", "m:1", null, null, null)
	var rt = rt_script.new()
	rt.configure(inst, {"is_home": false, "module_integrity": map})
	var snap: Dictionary = rt.to_snapshot()
	if typeof(snap.get("module_integrity", null)) != TYPE_DICTIONARY:
		_fail("runtime snapshot should carry module_integrity")
		return
	var map2 = ModuleIntegrityMapScript.new()
	var rt2 = rt_script.new()
	rt2.configure(inst, {"is_home": false, "module_integrity": map2})
	rt2.from_snapshot(snap)
	if map2.count_wall_breaches() != map.count_wall_breaches():
		_fail("module integrity snapshot round-trip")
		return

	print("MODULE INTEGRITY CONSEQUENCES PASS fire=true breach_derived=true scene=true nav=true")
	quit(0)


func _fail(msg: String) -> void:
	print("MODULE INTEGRITY CONSEQUENCES FAIL: %s" % msg)
	quit(1)


func _has_exact_compiler_owners(module: RefCounted, record: Dictionary) -> bool:
	if module == null:
		return false
	var expected: PackedStringArray = PackedStringArray()
	for room_v in (record.get("room_ids", []) as Array):
		var room_id: String = str(room_v)
		if not room_id.is_empty() and not expected.has(room_id):
			expected.append(room_id)
	var primary: String = str(record.get("room_id", ""))
	if not primary.is_empty() and not expected.has(primary):
		expected.insert(0, primary)
	var actual: PackedStringArray = PackedStringArray()
	var module_primary: String = str(module.get("room_id"))
	if not module_primary.is_empty():
		actual.append(module_primary)
	var shared: Variant = module.get("owner_rooms")
	if shared is PackedStringArray:
		for room_id in (shared as PackedStringArray):
			if not room_id.is_empty() and not actual.has(room_id):
				actual.append(room_id)
	return actual.size() == expected.size() and actual == expected


func _record_for_cell_key(records: Array, expected_cell_key: String) -> Dictionary:
	for record_v in records:
		if record_v is Dictionary and str((record_v as Dictionary).get("cell_key", "")) == expected_cell_key:
			return record_v as Dictionary
	return {}
