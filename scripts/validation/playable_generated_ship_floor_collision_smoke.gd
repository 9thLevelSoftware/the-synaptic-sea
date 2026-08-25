extends SceneTree

## Regression smoke for playable procgen floor collision.
## Marker: PLAYABLE GENERATED SHIP FLOOR COLLISION SMOKE PASS

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const GENERATED_SHIP_LOADER_SCRIPT := preload("res://scripts/procgen/generated_ship_loader.gd")
const STRUCTURAL_PLAN_VALIDATOR_SCRIPT := preload("res://scripts/procgen/structural_plan_validator.gd")
const PLAYER_CONTROLLER_SCRIPT := preload("res://scripts/player/player_controller.gd")
const SETTLE_PHYSICS_FRAMES: int = 30
const FORWARD_PHYSICS_FRAMES: int = 60
const FORWARD_DIRECTION: Vector3 = Vector3(0.0, 0.0, -1.0)
const MAX_FALL_DISTANCE: float = 0.75

var playable_ship
var frame_count: int = 0
var settle_frames_remaining: int = SETTLE_PHYSICS_FRAMES
var forward_frames: int = 0
var ready_seen: bool = false
var finished: bool = false
var floor_coverage_error: String = ""
var start_position: Vector3 = Vector3.INF
var settle_floor_seen: bool = false


func _initialize() -> void:
	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	if playable_ship == null:
		_fail("could not instantiate playable_generated_ship.tscn")
		return
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)


func _on_playable_ready(_summary: Dictionary) -> void:
	ready_seen = true
	if playable_ship.player == null or not (playable_ship.player is CharacterBody3D):
		_fail("playable_ready fired before PlayerController existed")
		return
	var player_node: Node = playable_ship.player as Node
	if player_node.name != "PlayerController" or player_node.get_script() != PLAYER_CONTROLLER_SCRIPT or not player_node.has_method("set_scripted_move_direction"):
		_fail("playable_ready did not expose the actual PlayerController scripted-direction API")
		return
	var negative_preflight_error: String = _run_negative_loader_preflight_regressions()
	if not negative_preflight_error.is_empty():
		_fail(negative_preflight_error)
		return
	start_position = playable_ship.player.global_position
	floor_coverage_error = _floor_wrapper_coverage_error()


func _on_playable_failed(reason: String) -> void:
	_fail("playable_failed reason=%s" % reason)


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not ready_seen:
		if frame_count > 600:
			_fail("timed out waiting for playable_ready")
		return
	if playable_ship.player == null or not is_instance_valid(playable_ship.player):
		_fail("PlayerController disappeared during smoke")
		return

	var player: CharacterBody3D = playable_ship.player as CharacterBody3D
	if settle_frames_remaining > 0:
		settle_frames_remaining -= 1
		if player.global_position.y < start_position.y - MAX_FALL_DISTANCE:
			_fail(
				"player lost floor during settling frame=%d position=%s start=%s floor_wrapper_coverage=%s"
				% [frame_count, str(player.global_position), str(start_position), _coverage_summary()]
			)
			return
		if player.is_on_floor():
			settle_floor_seen = true
		elif settle_floor_seen:
			_fail(
				"player lost floor during settling frame=%d position=%s start=%s floor_wrapper_coverage=%s"
				% [frame_count, str(player.global_position), str(start_position), _coverage_summary()]
			)
			return
		if settle_frames_remaining == 0:
			if not settle_floor_seen:
				_fail(
					"PlayerController did not settle on floor position=%s floor_wrapper_coverage=%s"
					% [str(player.global_position), _coverage_summary()]
				)
				return
			player.set_scripted_move_direction(FORWARD_DIRECTION)
		return

	forward_frames += 1
	if not player.is_on_floor() or player.global_position.y < start_position.y - MAX_FALL_DISTANCE:
		_fail(
			"player lost floor during scripted forward movement frame=%d position=%s start=%s floor_wrapper_coverage=%s"
			% [forward_frames, str(player.global_position), str(start_position), _coverage_summary()]
		)
		return
	if forward_frames >= FORWARD_PHYSICS_FRAMES:
		if not floor_coverage_error.is_empty():
			_fail("floor wrapper coverage does not match structural_plan.floor_placements: %s" % floor_coverage_error)
			return
		print(
			"PLAYABLE GENERATED SHIP FLOOR COLLISION SMOKE PASS floor_wrapper_coverage=true player_controller=true settling_grounded=true negative_preflight_cases=4 validator_rejected=true attached_wrappers=0 forward_frames=%d start=%s end=%s"
			% [forward_frames, str(start_position), str(player.global_position)]
		)
		finished = true
		quit(0)


func _floor_wrapper_coverage_error() -> String:
	if playable_ship.loader == null or playable_ship.loader.structural_root == null:
		return "loader structural_root missing"
	var plan_variant: Variant = playable_ship.loader.layout_doc.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		return "structural_plan missing"
	var floor_variant: Variant = (plan_variant as Dictionary).get("floor_placements", null)
	if not (floor_variant is Array) or (floor_variant as Array).is_empty():
		return "structural_plan.floor_placements missing or empty"

	var expected: Dictionary = {}
	for floor_variant_record in floor_variant as Array:
		if not (floor_variant_record is Dictionary):
			return "floor placement record is not a Dictionary"
		var floor_record: Dictionary = floor_variant_record
		var placement_id: String = str(floor_record.get("placement_id", ""))
		if placement_id.is_empty():
			return "floor placement missing placement_id"
		if expected.has(placement_id):
			return "duplicate expected floor placement_id: %s" % placement_id
		expected[placement_id] = floor_record

	var actual: Dictionary = {}
	for child in playable_ship.loader.structural_root.get_children():
		if not (child is Node3D) or not child.has_meta("structural_floor_placement_id"):
			continue
		if str(child.get_meta("structural_kind", "")) != "FLOOR":
			continue
		var placement_id: String = str(child.get_meta("structural_floor_placement_id", ""))
		if actual.has(placement_id):
			return "duplicate materialized floor placement_id: %s" % placement_id
		actual[placement_id] = {
			"module_id": str(child.get_meta("module_kind", "")),
			"collision_shapes": _count_collision_shapes(child),
			"wrapper": child,
		}

	var missing: Array[String] = []
	var bad_module: Array[String] = []
	var missing_collision: Array[String] = []
	var bad_transform: Array[String] = []
	for placement_id in expected:
		if not actual.has(placement_id):
			missing.append(placement_id)
			continue
		var materialized: Dictionary = actual[placement_id]
		var expected_record: Dictionary = expected[placement_id]
		if str(materialized.get("module_id", "")) != str(expected_record.get("module_id", "")):
			bad_module.append("%s expected=%s got=%s" % [placement_id, expected_record.get("module_id", ""), materialized.get("module_id", "")])
		if int(materialized.get("collision_shapes", 0)) <= 0:
			missing_collision.append(placement_id)
		if not _has_matching_floor_transform(materialized.get("wrapper", null), expected_record):
			bad_transform.append(placement_id)
	var unexpected: Array[String] = []
	for placement_id in actual:
		if not expected.has(placement_id):
			unexpected.append(placement_id)
	if not missing.is_empty() or not bad_module.is_empty() or not missing_collision.is_empty() or not bad_transform.is_empty() or not unexpected.is_empty() or actual.size() != expected.size():
		return "expected=%d actual=%d missing=%s bad_module=%s missing_collision=%s bad_transform=%s unexpected=%s" % [expected.size(), actual.size(), str(missing), str(bad_module), str(missing_collision), str(bad_transform), str(unexpected)]
	return ""


func _coverage_summary() -> String:
	return "valid" if floor_coverage_error.is_empty() else floor_coverage_error


func _run_negative_loader_preflight_regressions() -> String:
	if playable_ship.loader == null:
		return "negative preflight fixture loader missing"
	var fixture_layout: Dictionary = playable_ship.loader.get_layout_copy()
	var plan_variant: Variant = fixture_layout.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		return "negative preflight fixture structural_plan missing"
	var plan: Dictionary = plan_variant
	var floors_variant: Variant = plan.get("floor_placements", null)
	if not (floors_variant is Array) or (floors_variant as Array).is_empty():
		return "negative preflight fixture floor_placements missing or empty"
	var module_map: Dictionary = playable_ship.loader._build_module_scene_map(
		playable_ship.loader.kit_doc,
		"res://data/kits/ship_structural_v0.json",
	)
	if module_map.is_empty():
		return "negative preflight fixture wrapper mapping is empty"

	var duplicate_plan: Dictionary = fixture_layout.get("structural_plan", {}).duplicate(true)
	var duplicate_floors: Array = duplicate_plan.get("floor_placements", [])
	duplicate_floors.append((duplicate_floors[0] as Dictionary).duplicate(true))
	duplicate_plan["floor_placements"] = duplicate_floors
	var duplicate_layout: Dictionary = fixture_layout.duplicate(true)
	duplicate_layout["structural_plan"] = duplicate_plan
	var duplicate_error: String = _expect_rejected_floor_preflight(
		duplicate_layout,
		module_map,
		"duplicate canonical floor record",
	)
	if not duplicate_error.is_empty():
		return duplicate_error

	var cross_group_plan: Dictionary = fixture_layout.get("structural_plan", {}).duplicate(true)
	var cross_group_edges: Array = cross_group_plan.get("placements", [])
	var cross_group_floors: Array = cross_group_plan.get("floor_placements", [])
	if cross_group_edges.is_empty() or cross_group_floors.is_empty():
		return "duplicate edge/floor placement_id fixture is incomplete"
	var cross_group_edge: Dictionary = (cross_group_edges[0] as Dictionary).duplicate(true)
	cross_group_edge["edge_key"] = String((cross_group_floors[0] as Dictionary).get("cell_key", ""))
	cross_group_edges[0] = cross_group_edge
	cross_group_plan["placements"] = cross_group_edges
	cross_group_plan["floor_placements"] = cross_group_floors
	var cross_group_layout: Dictionary = fixture_layout.duplicate(true)
	cross_group_layout["structural_plan"] = cross_group_plan
	var cross_group_error: String = _expect_rejected_floor_preflight(
		cross_group_layout,
		module_map,
		"duplicate edge/floor placement_id",
	)
	if not cross_group_error.is_empty():
		return cross_group_error

	var duplicate_edge_plan: Dictionary = fixture_layout.get("structural_plan", {}).duplicate(true)
	var duplicate_edge_placements: Array = duplicate_edge_plan.get("placements", [])
	if duplicate_edge_placements.size() < 2:
		return "duplicate edge placement_id fixture is incomplete"
	var duplicate_edge_record: Dictionary = (duplicate_edge_placements[1] as Dictionary).duplicate(true)
	duplicate_edge_record["edge_key"] = String((duplicate_edge_placements[0] as Dictionary).get("edge_key", ""))
	duplicate_edge_placements[1] = duplicate_edge_record
	duplicate_edge_plan["placements"] = duplicate_edge_placements
	var duplicate_edge_layout: Dictionary = fixture_layout.duplicate(true)
	duplicate_edge_layout["structural_plan"] = duplicate_edge_plan
	var duplicate_edge_error: String = _expect_rejected_floor_preflight(
		duplicate_edge_layout,
		module_map,
		"duplicate edge placement_id",
	)
	if not duplicate_edge_error.is_empty():
		return duplicate_edge_error

	var malformed_plan: Dictionary = fixture_layout.get("structural_plan", {}).duplicate(true)
	var malformed_floors: Array = malformed_plan.get("floor_placements", [])
	var malformed_floor: Dictionary = (malformed_floors[0] as Dictionary).duplicate(true)
	malformed_floor["yaw_degrees"] = 45.0
	malformed_floors[0] = malformed_floor
	malformed_plan["floor_placements"] = malformed_floors
	var malformed_layout: Dictionary = fixture_layout.duplicate(true)
	malformed_layout["structural_plan"] = malformed_plan
	return _expect_rejected_floor_preflight(
		malformed_layout,
		module_map,
		"malformed canonical floor record",
	)


func _expect_rejected_floor_preflight(
		fixture_layout: Dictionary,
		module_map: Dictionary,
		label: String) -> String:
	var plan_variant: Variant = fixture_layout.get("structural_plan", null)
	if not (plan_variant is Dictionary):
		return "%s fixture structural_plan missing" % label
	var validator_verdict: Dictionary = STRUCTURAL_PLAN_VALIDATOR_SCRIPT.new().validate(
		plan_variant as Dictionary,
		fixture_layout,
	)
	if bool(validator_verdict.get("ok", false)):
		return "%s was accepted by StructuralPlanValidator: %s" % [label, JSON.stringify(validator_verdict)]
	var test_loader = GENERATED_SHIP_LOADER_SCRIPT.new()
	var structural_root: Node3D = Node3D.new()
	test_loader.layout_doc = fixture_layout
	var result: Dictionary = test_loader._validate_structural_plan_for_loading()
	var rejected: bool = not bool(result.get("ok", false))
	var instance_count: int = 0
	rejected = rejected and structural_root.get_child_count() == 0
	var structural_children: int = structural_root.get_child_count()
	test_loader.free()
	structural_root.free()
	if rejected:
		return ""
	return "%s was accepted before attachment result=%s instance_count=%d structural_children=%d" % [
		label,
		JSON.stringify(result),
		instance_count,
		structural_children,
	]


func _has_matching_floor_transform(wrapper_variant: Variant, record: Dictionary) -> bool:
	if not (wrapper_variant is Node3D):
		return false
	var expected_position: Vector3 = _read_record_position(record.get("position", null))
	if expected_position == Vector3.INF:
		return false
	var wrapper: Node3D = wrapper_variant as Node3D
	if not wrapper.transform.origin.is_equal_approx(expected_position):
		return false
	var yaw_variant: Variant = record.get("yaw_degrees", null)
	if typeof(yaw_variant) != TYPE_INT and typeof(yaw_variant) != TYPE_FLOAT:
		return false
	var expected_forward: Vector3 = Basis(Vector3.UP, deg_to_rad(float(yaw_variant))) * Vector3.FORWARD
	var actual_forward: Vector3 = wrapper.transform.basis * Vector3.FORWARD
	return actual_forward.is_equal_approx(expected_forward)


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


func _count_collision_shapes(node: Node) -> int:
	var count: int = 0
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		count += 1
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PLAYABLE GENERATED SHIP FLOOR COLLISION SMOKE FAIL reason=%s" % reason)
	quit(1)
