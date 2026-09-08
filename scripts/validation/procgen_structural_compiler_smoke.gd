extends SceneTree

## Multi-seed quality gate for the canonical structural compiler.
##
## This is deliberately a data-first smoke: every seed is generated through the
## production layout pipeline, compiled, validated, flood-filled, and checked
## against the complete wrapper catalog before the pass marker is printed.

const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript: GDScript = preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralEdgeCompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript: GDScript = preload("res://scripts/procgen/structural_plan_validator.gd")
const StructuralEdgePlanScript: GDScript = preload("res://scripts/procgen/structural_edge_plan.gd")

const SEEDS: Array[int] = [17, 23, 41, 73, 101]
const MIN_DERELICT_ROOMS: int = 5
const MAX_DERELICT_ROOMS: int = 8
const DERELICT_TEMPLATE: String = "derelict_a"
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const MATERIALIZED_EDGE_KINDS: Array[String] = ["SOLID", "DOOR", "LOCKED", "HATCH"]
const EXPECTED_WRAPPER_COUNT: int = 15

var failures: Array[String] = []
var total_placements: int = 0
var total_portals: int = 0
var wrapper_scenes: Dictionary = {}


func _initialize() -> void:
	wrapper_scenes = _load_wrapper_catalog()
	if wrapper_scenes.size() < EXPECTED_WRAPPER_COUNT:
		failures.append("full structural wrapper catalog incomplete: %d/%d" % [wrapper_scenes.size(), EXPECTED_WRAPPER_COUNT])
	else:
		for seed_value in SEEDS:
			_check_seed(seed_value)

	if not failures.is_empty():
		print("PROCGEN_STRUCTURAL_COMPILER_FAIL %s" % "; ".join(failures))
		quit(1)
		return

	print("PROCGEN_STRUCTURAL_COMPILER_PASS seeds=%d placements=%d portals=%d" % [
		SEEDS.size(), total_placements, total_portals])
	quit(0)


func _check_seed(seed_value: int) -> void:
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.WRECKED,
		seed_value)
	blueprint.room_count_range = Vector2i(MIN_DERELICT_ROOMS, MAX_DERELICT_ROOMS)
	var layout: Dictionary = ShipLayoutGeneratorScript.new().generate_with_options(
		blueprint,
		_derelict_archetype(),
		"",
		"",
		true,
	)
	if layout.is_empty():
		failures.append("seed=%d empty production layout" % seed_value)
		return

	var rooms: Array = layout.get("rooms", [])
	if rooms.size() < MIN_DERELICT_ROOMS or rooms.size() > MAX_DERELICT_ROOMS:
		failures.append("seed=%d room count=%d outside 5-8" % [seed_value, rooms.size()])
		return
	if not _check_room_footprints(seed_value, rooms):
		return

	var plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
	var compiler_errors: Variant = plan.get("errors", [])
	if not (compiler_errors is Array) or not (compiler_errors as Array).is_empty():
		failures.append("seed=%d compiler errors=%s" % [seed_value, JSON.stringify(compiler_errors)])
		return
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(plan, layout)
	if not bool(verdict.get("ok", false)):
		failures.append("seed=%d validator errors=%s" % [seed_value, JSON.stringify(verdict.get("errors", []))])
		return
	if not _check_physical_placement_coverage(seed_value, plan):
		return
	if not _check_flood_connectivity(seed_value, plan):
		return
	if not _check_full_wrappers(seed_value, plan):
		return

	total_placements += (plan.get("placements", []) as Array).size()
	total_portals += _portal_count(plan)


func _derelict_archetype() -> Dictionary:
	return {
		"name": "Derelict",
		"type": "derelict",
		"template": DERELICT_TEMPLATE,
		"guaranteed_roles": [],
		"role_weights": {},
		"max_duplicates": 3,
	}


func _check_room_footprints(seed_value: int, rooms: Array) -> bool:
	var ownership: Dictionary = {}
	for room_variant in rooms:
		if not (room_variant is Dictionary):
			failures.append("seed=%d room record is not a Dictionary" % seed_value)
			return false
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		var cells: Variant = room.get("cells", null)
		var footprint: Variant = room.get("footprint", null)
		if room_id.is_empty() or not (cells is Array) or (cells as Array).is_empty() or not (footprint is Vector2i):
			failures.append("seed=%d room=%s has incomplete explicit footprint" % [seed_value, room_id])
			return false
		var footprint_size: Vector2i = footprint
		if footprint_size.x <= 0 or footprint_size.y <= 0 or footprint_size.x * footprint_size.y != (cells as Array).size():
			failures.append("seed=%d room=%s footprint/cell count mismatch" % [seed_value, room_id])
			return false
		var deck: int = int(room.get("deck", -1))
		for cell_variant in cells:
			var cell_result: Dictionary = _read_cell(cell_variant)
			if not bool(cell_result.get("ok", false)):
				failures.append("seed=%d room=%s contains a non-integer cell" % [seed_value, room_id])
				return false
			var cell: Vector2i = cell_result["cell"]
			var key: String = StructuralEdgePlanScript.cell_key(deck, cell)
			if ownership.has(key):
				failures.append("seed=%d duplicate occupancy cell=%s" % [seed_value, key])
				return false
			ownership[key] = room_id
	return true


func _check_physical_placement_coverage(seed_value: int, plan: Dictionary) -> bool:
	var edges: Variant = plan.get("edges", null)
	var placements: Variant = plan.get("placements", null)
	if not (edges is Dictionary) or not (placements is Array):
		failures.append("seed=%d canonical edge/placement collections are malformed" % seed_value)
		return false
	var placement_ids: Dictionary = {}
	var half_span_owners: Dictionary = {}
	var materialized_counts: Dictionary = {}
	for placement_variant in placements:
		if not (placement_variant is Dictionary):
			failures.append("seed=%d placement record is not a Dictionary" % seed_value)
			return false
		var placement: Dictionary = placement_variant
		var placement_id: String = str(placement.get("placement_id", ""))
		if placement_id.is_empty() or placement_ids.has(placement_id):
			failures.append("seed=%d missing or duplicate physical placement_id=%s" % [seed_value, placement_id])
			return false
		placement_ids[placement_id] = true
		var edge_key: String = str(placement.get("edge_key", ""))
		if edge_key.is_empty():
			failures.append("seed=%d placement is missing edge_key" % seed_value)
			return false
		var kind: String = str(placement.get("kind", "")).to_upper()
		if kind == "OPEN":
			failures.append("seed=%d OPEN edge has a physical placement" % seed_value)
			return false
		var edge_keys_variant: Variant = placement.get("edge_keys", null)
		if not (edge_keys_variant is Array) or (edge_keys_variant as Array).is_empty() \
				or not (edge_keys_variant as Array).has(edge_key):
			failures.append("seed=%d placement=%s has malformed edge_keys" % [seed_value, placement_id])
			return false
		for edge_key_variant in edge_keys_variant as Array:
			var bound_edge_key: String = str(edge_key_variant)
			if not edges.has(bound_edge_key):
				failures.append("seed=%d placement=%s references missing edge=%s" % [seed_value, placement_id, bound_edge_key])
				return false
			var bound_edge: Dictionary = edges[bound_edge_key] as Dictionary
			if str(bound_edge.get("kind", bound_edge.get("state", ""))).to_upper() != kind:
				failures.append("seed=%d placement=%s kind disagrees with edge=%s" % [seed_value, placement_id, bound_edge_key])
				return false
			materialized_counts[bound_edge_key] = int(materialized_counts.get(bound_edge_key, 0)) + 1
		var covered_variant: Variant = placement.get("covered_half_spans", null)
		if not (covered_variant is Array):
			failures.append("seed=%d placement=%s has malformed half-span coverage" % [seed_value, placement_id])
			return false
		for span_variant in covered_variant as Array:
			var span_id: String = str(span_variant)
			var span_edge_key: String = span_id.get_slice("@", 0)
			if span_id.is_empty() or half_span_owners.has(span_id) or not edges.has(span_edge_key):
				failures.append("seed=%d placement=%s has duplicate or invalid half-span=%s" % [seed_value, placement_id, span_id])
				return false
			var span_edge: Dictionary = edges[span_edge_key] as Dictionary
			if str(span_edge.get("kind", "")).to_upper() != "SOLID" \
					or not (span_edge.get("half_span_ids", []) as Array).has(span_id):
				failures.append("seed=%d placement=%s claims non-canonical half-span=%s" % [seed_value, placement_id, span_id])
				return false
			half_span_owners[span_id] = placement_id

	for edge_key_variant in edges.keys():
		var edge_key: String = str(edge_key_variant)
		var edge_variant: Variant = edges[edge_key_variant]
		if not (edge_variant is Dictionary):
			failures.append("seed=%d edge record is not a Dictionary=%s" % [seed_value, edge_key])
			return false
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", ""))).to_upper()
		if kind == "SOLID":
			var half_span_ids: Variant = edge.get("half_span_ids", null)
			if not (half_span_ids is Array) or (half_span_ids as Array).size() != 2 \
					or str((half_span_ids as Array)[0]) != "%s@a" % edge_key \
					or str((half_span_ids as Array)[1]) != "%s@b" % edge_key:
				failures.append("seed=%d SOLID edge=%s lacks exact @a/@b authority" % [seed_value, edge_key])
				return false
			for span_variant in half_span_ids as Array:
				var span_id: String = str(span_variant)
				if not half_span_owners.has(span_id):
					failures.append("seed=%d SOLID edge=%s has uncovered half-span=%s" % [seed_value, edge_key, span_id])
					return false
		elif kind in MATERIALIZED_EDGE_KINDS and int(materialized_counts.get(edge_key, 0)) != 1:
			failures.append("seed=%d edge=%s expected one physical placement got=%d" % [
				seed_value, edge_key, int(materialized_counts.get(edge_key, 0))])
			return false
		elif kind == "OPEN" and int(materialized_counts.get(edge_key, 0)) != 0:
			failures.append("seed=%d OPEN edge=%s has physical placement" % [seed_value, edge_key])
			return false
	return true


func _check_flood_connectivity(seed_value: int, plan: Dictionary) -> bool:
	var occupancy: Variant = plan.get("occupancy", null)
	var edges: Variant = plan.get("edges", null)
	if not (occupancy is Dictionary) or not (edges is Dictionary) or (occupancy as Dictionary).is_empty():
		failures.append("seed=%d flood-fill input is malformed" % seed_value)
		return false
	var adjacency: Dictionary = {}
	for key_variant in (occupancy as Dictionary).keys():
		adjacency[str(key_variant)] = []
	for edge_variant in (edges as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
		if kind == "SOLID":
			continue
		var source_cells: Variant = edge.get("source_cells", null)
		if not (source_cells is Array) or (source_cells as Array).size() != 2:
			continue
		var deck: int = int(edge.get("deck", -1))
		var first: Dictionary = _read_cell((source_cells as Array)[0])
		var second: Dictionary = _read_cell((source_cells as Array)[1])
		if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
			continue
		var first_key: String = StructuralEdgePlanScript.cell_key(deck, first["cell"])
		var second_key: String = StructuralEdgePlanScript.cell_key(deck, second["cell"])
		if not adjacency.has(first_key) or not adjacency.has(second_key):
			continue
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
		failures.append("seed=%d flood-fill disconnected occupied cells=%d/%d" % [
			seed_value, visited.size(), (occupancy as Dictionary).size()])
		return false
	return true


func _check_full_wrappers(seed_value: int, plan: Dictionary) -> bool:
	var placements: Variant = plan.get("placements", null)
	var floors: Variant = plan.get("floor_placements", null)
	if not (placements is Array) or not (floors is Array) or (floors as Array).is_empty():
		failures.append("seed=%d full wrapper placement arrays are malformed" % seed_value)
		return false
	for record_variant in (placements as Array) + (floors as Array):
		if not (record_variant is Dictionary):
			failures.append("seed=%d full wrapper record is not a Dictionary" % seed_value)
			return false
		var record: Dictionary = record_variant
		var module_id: String = str(record.get("module_id", ""))
		if module_id.is_empty() or not wrapper_scenes.has(module_id):
			failures.append("seed=%d full wrapper missing module=%s" % [seed_value, module_id])
			return false
		if str(record.get("kind", "")) == "FLOOR" and not FLOOR_MODULES.has(module_id):
			failures.append("seed=%d floor placement uses non-floor wrapper=%s" % [seed_value, module_id])
			return false
	return true


func _portal_count(plan: Dictionary) -> int:
	var count: int = 0
	for edge_variant in (plan.get("edges", {}) as Dictionary).values():
		if not (edge_variant is Dictionary):
			continue
		var kind: String = str((edge_variant as Dictionary).get("kind", "")).to_upper()
		if kind in ["DOOR", "LOCKED", "HATCH", "BREACH"]:
			count += 1
	return count


func _load_wrapper_catalog() -> Dictionary:
	var catalog_path: String = "res://data/kits/ship_structural_v0.json"
	if not FileAccess.file_exists(catalog_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not (parsed is Dictionary):
		return {}
	var scenes: Dictionary = {}
	var modules: Variant = (parsed as Dictionary).get("modules", [])
	if not (modules is Array):
		return {}
	for module_variant in modules:
		if not (module_variant is Dictionary):
			continue
		var module: Dictionary = module_variant
		var module_id: String = str(module.get("module_id", ""))
		var scene_path: String = str(module.get("godot_wrapper_scene", ""))
		if module_id.is_empty() or scene_path.is_empty() or not FileAccess.file_exists(scene_path):
			continue
		var packed: Variant = load(scene_path)
		if packed is PackedScene:
			scenes[module_id] = packed
	return scenes


func _read_cell(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "cell": value}
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		if typeof(values[0]) == TYPE_INT and typeof(values[1]) == TYPE_INT:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	return {"ok": false}
