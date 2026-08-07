extends SceneTree

const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")

const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const SEED: int = 17

var loaded: bool = false
var failed_reason: String = ""


func _initialize() -> void:
	if not _run_loader_preflight_regressions():
		_fail("loader preflight regression cases failed")
		return

	var root_node: Node3D = Node3D.new()
	root_node.name = "LoaderPlayableContractSmokeRoot"
	get_root().add_child(root_node)

	var generator = ShipGeneratorScript.new()
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		SEED
	)
	var generated: Node3D = generator.generate(blueprint, {"template": "spine"})
	if generated == null:
		_fail("seed %d generation returned null" % SEED)
		return
	root_node.add_child(generated)
	var loader = generated
	loaded = true

	if not loader.has_loaded_ship():
		_fail("has_loaded_ship=false")
		return
	if loader.get_start_transform().origin == Vector3.INF:
		_fail("invalid start transform")
		return
	if loader.get_goal_position() == Vector3.INF:
		_fail("invalid goal position")
		return
	if loader.get_objective_specs_copy().is_empty():
		_fail("generated ship has no objectives")
		return
	if loader.count_collision_shapes() <= 0:
		_fail("collision shape count is zero")
		return

	var layout: Dictionary = loader.get_layout_copy()
	var structural_plan_variant: Variant = layout.get("structural_plan", null)
	if not (structural_plan_variant is Dictionary):
		_fail("layout missing structural_plan")
		return
	var structural_plan: Dictionary = structural_plan_variant
	var placements_variant: Variant = structural_plan.get("placements", null)
	if not (placements_variant is Array):
		_fail("structural_plan placements are not an Array")
		return
	var placements: Array = placements_variant

	var edge_records: Dictionary = {}
	var floor_records: Dictionary = {}
	var expected_wrapper_count: int = 0
	var north_seed_fixture_found: bool = false
	for record_variant in placements:
		if not (record_variant is Dictionary):
			_fail("structural placement is not a Dictionary")
			return
		var record: Dictionary = record_variant
		var kind: String = str(record.get("kind", ""))
		if kind == "OPEN":
			continue
		if kind == "FLOOR":
			_fail("floor placement must be declared in floor_placements, not placements")
			return
		var edge_key: String = str(record.get("edge_key", ""))
		if edge_key.is_empty():
			_fail("non-OPEN edge record is missing edge_key")
			return
		var placement_id: String = str(record.get("placement_id", ""))
		if placement_id.is_empty():
			_fail("non-OPEN edge record is missing placement_id")
			return
		if edge_records.has(placement_id) or floor_records.has(placement_id):
			_fail("duplicate expected structural placement_id %s" % placement_id)
			return
		for existing_variant in edge_records.values():
			if str((existing_variant as Dictionary).get("edge_key", "")) == edge_key:
				_fail("duplicate expected structural edge key %s" % edge_key)
				return
		edge_records[placement_id] = record
		expected_wrapper_count += 1
		if not north_seed_fixture_found and str(record.get("direction", "")) == "north":
			var seed_position: Vector3 = _read_record_position(record.get("position", null))
			if seed_position != Vector3.INF and is_equal_approx(seed_position.z, -2.0) and is_equal_approx(float(record.get("yaw_degrees", -1.0)), 180.0):
				north_seed_fixture_found = true

	var floor_placements_variant: Variant = structural_plan.get("floor_placements", null)
	if not (floor_placements_variant is Array) or (floor_placements_variant as Array).is_empty():
		_fail("structural_plan floor_placements are missing or empty")
		return
	for floor_record_variant in floor_placements_variant as Array:
		if not (floor_record_variant is Dictionary):
			_fail("floor placement is not a Dictionary")
			return
		var floor_record: Dictionary = floor_record_variant
		if str(floor_record.get("kind", "")) != "FLOOR":
			_fail("floor placement kind is not FLOOR")
			return
		if floor_record.has("edge_key"):
			_fail("canonical floor placement must not contain edge_key")
			return
		var floor_placement_id: String = str(floor_record.get("placement_id", ""))
		var floor_module_id: String = str(floor_record.get("module_id", ""))
		if floor_placement_id.is_empty() or floor_module_id.is_empty():
			_fail("floor placement must declare placement_id and module_id")
			return
		if edge_records.has(floor_placement_id) or floor_records.has(floor_placement_id):
			_fail("duplicate expected structural placement_id %s" % floor_placement_id)
			return
		floor_records[floor_placement_id] = floor_record
		expected_wrapper_count += 1

	if not north_seed_fixture_found:
		_fail("seed %d has no north z=-2 yaw=180 fixture" % SEED)
		return

	var fixture_layout: Dictionary = {
		"rooms": [{"id": "north_fixture_room", "deck": 0, "cells": [[0, 0]]}],
		"portals": [{
			"from_room": "north_fixture_room",
			"to_room": "",
			"type": "hatch",
			"required": true,
			"edge_key": "0|h|-1|0",
		}],
	}
	var fixture_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(fixture_layout)
	if not (fixture_plan.get("errors", []) as Array).is_empty():
		_fail("north portal fixture compiler errors: " + JSON.stringify(fixture_plan["errors"]))
		return
	var fixture_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(fixture_plan, fixture_layout)
	if not bool(fixture_verdict.get("ok", false)):
		_fail("north portal fixture validator errors: " + JSON.stringify(fixture_verdict["errors"]))
		return
	var north_portal_found: bool = false
	for fixture_record_variant in fixture_plan.get("placements", []):
		var fixture_record: Dictionary = fixture_record_variant
		if String(fixture_record.get("kind", "")) != "HATCH":
			continue
		if String(fixture_record.get("direction", "")) != "north":
			continue
		var fixture_position: Vector3 = fixture_record["position"]
		if not is_equal_approx(fixture_position.z, -2.0):
			_fail("north portal fixture z=%s expected z=-2" % str(fixture_position.z))
			return
		if not is_equal_approx(float(fixture_record.get("yaw_degrees", -1.0)), 180.0):
			_fail("north portal fixture yaw=%s expected yaw=180" % str(fixture_record.get("yaw_degrees", null)))
			return
		north_portal_found = true
	if not north_portal_found:
		_fail("north portal fixture was not emitted")
		return

	var structural_root: Node = loader.get_node_or_null("StructuralRoot")
	if structural_root == null:
		_fail("StructuralRoot is missing")
		return
	var wrapper_nodes: Array[Node3D] = []
	_collect_structural_wrappers(structural_root, wrapper_nodes)
	if wrapper_nodes.size() != expected_wrapper_count:
		_fail(
			"wrapper count=%d expected edge-plus-floor wrapper count=%d"
			% [wrapper_nodes.size(), expected_wrapper_count]
		)
		return

	var edge_keys: Dictionary = {}
	var actual_placement_ids: Dictionary = {}
	for wrapper in wrapper_nodes:
		for metadata_key in [
			"structural_edge_key",
			"structural_kind",
			"structural_placement_id",
			"structural_room_ids",
		]:
			if not wrapper.has_meta(metadata_key):
				_fail("wrapper %s is missing metadata %s" % [wrapper.name, metadata_key])
				return
		var placement_id: String = str(wrapper.get_meta("structural_placement_id"))
		if placement_id.is_empty() or actual_placement_ids.has(placement_id):
			_fail("duplicate or empty materialized structural_placement_id %s" % placement_id)
			return
		actual_placement_ids[placement_id] = true
		var kind: String = str(wrapper.get_meta("structural_kind"))
		var module_id: String = str(wrapper.get_meta("module_kind", ""))
		var edge_key: String = str(wrapper.get_meta("structural_edge_key"))
		if floor_records.has(placement_id):
			var floor_record: Dictionary = floor_records[placement_id]
			if kind != "FLOOR":
				_fail("floor wrapper %s has kind=%s" % [placement_id, kind])
				return
			if module_id != str(floor_record.get("module_id", "")):
				_fail("floor wrapper %s module=%s expected=%s" % [placement_id, module_id, floor_record.get("module_id", "")])
				return
			if not _has_matching_structural_room_ids(wrapper, floor_record):
				_fail("floor wrapper %s structural_room_ids do not match record" % placement_id)
				return
			if not _has_matching_structural_transform(wrapper, floor_record):
				_fail("floor wrapper %s transform does not match record" % placement_id)
				return
			if not edge_key.is_empty():
				_fail("floor wrapper %s has non-empty structural_edge_key" % placement_id)
				return
			if _count_collision_shapes(wrapper) <= 0:
				_fail("floor wrapper %s has no collision shape" % placement_id)
				return
		elif edge_records.has(placement_id):
			var edge_record: Dictionary = edge_records[placement_id]
			if kind != str(edge_record.get("kind", "")):
				_fail("edge wrapper %s kind=%s expected=%s" % [placement_id, kind, edge_record.get("kind", "")])
				return
			if module_id != str(edge_record.get("module_id", "")):
				_fail("edge wrapper %s module=%s expected=%s" % [placement_id, module_id, edge_record.get("module_id", "")])
				return
			if not _has_matching_structural_room_ids(wrapper, edge_record):
				_fail("edge wrapper %s structural_room_ids do not match record" % placement_id)
				return
			if not _has_matching_structural_transform(wrapper, edge_record):
				_fail("edge wrapper %s transform does not match record" % placement_id)
				return
			if edge_key.is_empty():
				_fail("edge wrapper %s has empty structural_edge_key" % placement_id)
				return
			if edge_keys.has(edge_key):
				_fail("duplicate wrapper edge key %s" % edge_key)
				return
			if edge_key != str(edge_record.get("edge_key", "")):
				_fail("edge wrapper %s edge_key=%s expected=%s" % [placement_id, edge_key, edge_record.get("edge_key", "")])
				return
			edge_keys[edge_key] = true
		else:
			_fail("unexpected materialized structural placement_id %s" % placement_id)
			return

	if actual_placement_ids.size() != expected_wrapper_count:
		_fail("materialized wrapper IDs=%d expected=%d" % [actual_placement_ids.size(), expected_wrapper_count])
		return
	for expected_id in edge_records:
		if not actual_placement_ids.has(expected_id):
			_fail("missing materialized edge wrapper %s" % expected_id)
			return
	for expected_id in floor_records:
		if not actual_placement_ids.has(expected_id):
			_fail("missing materialized floor wrapper %s" % expected_id)
			return

	var tracker = ObjectiveTrackerScript.new()
	tracker.name = "LoaderPlayableContractSmokeTracker"
	root_node.add_child(tracker)
	tracker.set_objectives(loader.get_objective_specs_copy())
	tracker.mark_completed(1)
	if tracker.get_completed_count() != 1 or not tracker.is_sequence_completed(1):
		_fail("tracker helper methods failed")
		return

	print(
		"PROCGEN_STRUCTURAL_LOADER_PASS PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=%d collision_shapes=%d edge_wrappers=%d floor_wrappers=%d wrappers=%d"
		% [loader.get_objective_specs_copy().size(), loader.count_collision_shapes(), edge_records.size(), floor_records.size(), wrapper_nodes.size()]
	)
	quit(0)


func _run_loader_preflight_regressions() -> bool:
	var topology: Dictionary = {
		"rooms": [{"id": "preflight_room", "deck": 0, "cells": [[0, 0]]}],
		"portals": [],
	}
	var base_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(topology)
	if not (base_plan.get("errors", []) as Array).is_empty():
		print("PROCGEN_STRUCTURAL_LOADER_PREFLIGHT_FAIL compiler: " + JSON.stringify(base_plan["errors"]))
		return false
	var wrapper_scene: PackedScene = load("res://scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn") as PackedScene
	if wrapper_scene == null:
		print("PROCGEN_STRUCTURAL_LOADER_PREFLIGHT_FAIL missing wall wrapper")
		return false
	var module_map: Dictionary = {"wall_straight_1x1": wrapper_scene}
	var malformed_module_map: Dictionary = {"wall_straight_1x1": "res://missing-wrapper-resource.tscn"}

	var malformed_cases: Array[Dictionary] = [
		{"label": "malformed-edge-position", "field": "position", "value": Vector3(123.0, 0.0, 456.0), "error": "canonical"},
		{"label": "malformed-yaw", "field": "yaw_degrees", "value": 45.0, "error": "canonical"},
		{"label": "malformed-edge-key", "field": "edge_key", "value": "not-a-canonical-edge-key", "error": ""},
	]
	for malformed_case in malformed_cases:
		var malformed_plan: Dictionary = base_plan.duplicate(true)
		var malformed_placement: Dictionary = (malformed_plan["placements"][0] as Dictionary)
		malformed_placement[String(malformed_case["field"])] = malformed_case["value"]
		var malformed_layout: Dictionary = topology.duplicate(true)
		malformed_layout["structural_plan"] = malformed_plan
		var malformed_loader = GeneratedShipLoaderScript.new()
		var malformed_root := Node3D.new()
		var malformed_result: Dictionary = malformed_loader._preflight_structural_wrappers(malformed_layout, malformed_module_map)
		var malformed_instance_count: int = malformed_loader._instance_structural_wrappers(malformed_layout, malformed_module_map, malformed_root)
		var malformed_ok: bool = not bool(malformed_result.get("ok", false))
		malformed_ok = malformed_ok and malformed_instance_count == -1
		malformed_ok = malformed_ok and malformed_root.get_child_count() == 0
		var malformed_error: String = String(malformed_result.get("error", ""))
		if not String(malformed_case["error"]).is_empty():
			malformed_ok = malformed_ok and malformed_error.contains(String(malformed_case["error"]))
		malformed_loader.free()
		malformed_root.free()
		if not malformed_ok:
			print("PROCGEN_STRUCTURAL_LOADER_PREFLIGHT_FAIL %s: %s" % [malformed_case["label"], JSON.stringify(malformed_result)])
			return false

	var mixed_plan: Dictionary = base_plan.duplicate(true)
	var mixed_placements: Array = mixed_plan["placements"]
	if mixed_placements.size() < 2:
		print("PROCGEN_STRUCTURAL_LOADER_PREFLIGHT_FAIL expected at least two placements")
		return false
	var invalid_record: Dictionary = mixed_placements[1]
	var invalid_edge_key: String = String(invalid_record.get("edge_key", ""))
	invalid_record["module_id"] = "missing_wrapper_module"
	var invalid_edge: Dictionary = mixed_plan["edges"][invalid_edge_key]
	invalid_edge["module_id"] = "missing_wrapper_module"
	mixed_plan["edges"][invalid_edge_key] = invalid_edge
	var mixed_layout: Dictionary = topology.duplicate(true)
	mixed_layout["structural_plan"] = mixed_plan
	var mixed_loader = GeneratedShipLoaderScript.new()
	var mixed_root := Node3D.new()
	var mixed_result: Dictionary = mixed_loader._preflight_structural_wrappers(mixed_layout, module_map)
	var mixed_instance_count: int = mixed_loader._instance_structural_wrappers(mixed_layout, module_map, mixed_root)
	var mixed_ok: bool = not bool(mixed_result.get("ok", false))
	mixed_ok = mixed_ok and mixed_instance_count == -1
	mixed_ok = mixed_ok and mixed_root.get_child_count() == 0
	mixed_ok = mixed_ok and String(mixed_result.get("error", "")).contains("unavailable wrapper")
	mixed_loader.free()
	mixed_root.free()
	if not mixed_ok:
		print("PROCGEN_STRUCTURAL_LOADER_PREFLIGHT_FAIL mixed module: " + JSON.stringify(mixed_result))
		return false
	return true


func _collect_structural_wrappers(node: Node, output: Array[Node3D]) -> void:
	if node is Node3D and node.has_meta("structural_placement_id"):
		output.append(node as Node3D)
	for child in node.get_children():
		_collect_structural_wrappers(child, output)


func _has_matching_structural_room_ids(wrapper: Node3D, record: Dictionary) -> bool:
	var actual_variant: Variant = wrapper.get_meta("structural_room_ids", null)
	var expected_variant: Variant = record.get("room_ids", null)
	if not (actual_variant is Array) or not (expected_variant is Array):
		return false
	var actual_room_ids: Array = actual_variant
	var expected_room_ids: Array = expected_variant
	return actual_room_ids == expected_room_ids


func _has_matching_structural_transform(wrapper: Node3D, record: Dictionary) -> bool:
	var expected_position: Vector3 = _read_record_position(record.get("position", null))
	if expected_position == Vector3.INF:
		return false
	if not wrapper.transform.origin.is_equal_approx(expected_position):
		return false
	var yaw_variant: Variant = record.get("yaw_degrees", null)
	if typeof(yaw_variant) != TYPE_INT and typeof(yaw_variant) != TYPE_FLOAT:
		return false
	# Compare the canonical forward vector instead of Euler angles so equivalent
	# rotations across the +/-180 degree wrap remain stable.
	var expected_forward: Vector3 = Basis(Vector3.UP, deg_to_rad(float(yaw_variant))) * Vector3.FORWARD
	var actual_forward: Vector3 = wrapper.transform.basis * Vector3.FORWARD
	return actual_forward.is_equal_approx(expected_forward)


func _count_collision_shapes(node: Node) -> int:
	var count: int = 0
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		count += 1
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _read_record_position(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array:
		var values: Array = raw
		if values.size() < 3:
			return Vector3.INF
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	if raw is String:
		var text: String = String(raw).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() < 3:
			return Vector3.INF
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.INF


func _fail(message: String) -> void:
	failed_reason = message
	print("PROCGEN_STRUCTURAL_LOADER_FAIL: %s" % message)
	quit(1)
