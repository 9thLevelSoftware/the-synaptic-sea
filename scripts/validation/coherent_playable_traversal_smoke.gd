extends SceneTree

# Playable traversal smoke for the coherent proof ship.
#
# Instantiates the sibling `res://scenes/procgen/playable_coherent_ship.tscn`
# scene (which reuses the seed-17 `PlayableGeneratedShip` script with the three
# fixture-path exports overridden to point at the coherent golden fixture),
# waits for `playable_ready`, and then validates:
#   * For every room on the critical path, the player can be teleported to the
#     room center and lands above the nearest floor placement (with a small
#     upward clearance).
#   * The same check holds for the three side rooms (cargo, medbay,
#     maintenance).
#   * At least one blocked-route marker node exists under the loader's
#     structural_root and its first descendant `CollisionShape3D` has a
#     non-null `shape`.
#   * The headless interaction-completion seam returns true (objective
#     completed >= 1).
#
# Pass marker:
#   COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
# Fail marker (matches Task 1-4 smokes):
#   COHERENT PLAYABLE TRAVERSAL FAIL reason=<reason>

const COHERENT_PLAYABLE_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

const READY_TIMEOUT_FRAMES: int = 240
const POST_READY_SETTLE_FRAMES: int = 30
const SIDE_ROOMS: Array[String] = ["cargo_01", "medbay_01", "maintenance_01"]
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
const FLOOR_COLLISION_HALF_HEIGHT: float = 0.125
const MIN_PLAYER_FLOOR_CLEARANCE: float = 0.05

var playable_ship
var ready_received: bool = false
var ready_summary: Dictionary = {}
var frame_count: int = 0
var finished: bool = false
var post_ready_settle_remaining: int = 0


func _initialize() -> void:
	playable_ship = COHERENT_PLAYABLE_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not ready_received:
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("ready timeout frames=%d" % frame_count)
		return
	if post_ready_settle_remaining > 0:
		post_ready_settle_remaining -= 1
		return
	_run_validation()


func _on_playable_ready(summary: Dictionary) -> void:
	if ready_received:
		return
	ready_received = true
	ready_summary = summary
	post_ready_settle_remaining = POST_READY_SETTLE_FRAMES


func _on_playable_failed(reason: String) -> void:
	_fail(reason)


func _run_validation() -> void:
	if not ready_received:
		return
	finished = true
	var player_spawned: bool = bool(ready_summary.get("player_spawned", false))
	if not player_spawned:
		_fail("player_spawned=false")
		return
	var loader = playable_ship.loader
	if loader == null:
		_fail("loader is null")
		return

	# 1) Critical path traversal.
	var critical_path: Array = loader.get_critical_path()
	if critical_path.size() < 5:
		_fail("critical_path_size=%d expected_at_least=5" % critical_path.size())
		return
	for room_id_variant in critical_path:
		var room_id: String = str(room_id_variant)
		if not playable_ship.teleport_player_to_room_for_validation(room_id):
			_fail("teleport_to_critical_room_failed room=%s" % room_id)
			return
		var check_failure: String = _check_player_above_nearest_floor(loader, room_id)
		if not check_failure.is_empty():
			_fail("critical_room=%s %s" % [room_id, check_failure])
			return

	# 2) Side room traversal.
	for room_id in SIDE_ROOMS:
		if not playable_ship.teleport_player_to_room_for_validation(room_id):
			_fail("teleport_to_side_room_failed room=%s" % room_id)
			return
		var side_check_failure: String = _check_player_above_nearest_floor(loader, room_id)
		if not side_check_failure.is_empty():
			_fail("side_room=%s %s" % [room_id, side_check_failure])
			return

	# 3) Blocked-route marker node has a collision shape.
	var blocked_nodes: Array = loader.get_blocked_route_nodes()
	if blocked_nodes.is_empty():
		_fail("blocked_route_nodes=0")
		return
	var first_blocked = blocked_nodes[0]
	var collision_shape: CollisionShape3D = _find_collision_shape(first_blocked)
	if collision_shape == null:
		_fail("blocked_route_node_missing_collision_shape room=%s" % first_blocked.name)
		return
	if collision_shape.shape == null:
		_fail("blocked_route_node_collision_shape_is_null room=%s" % first_blocked.name)
		return

	# 4) Interaction completes.
	if not playable_ship.complete_first_interaction_for_validation():
		_fail("complete_first_interaction_returned_false")
		return

	print("COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true")
	quit(0)


func _check_player_above_nearest_floor(loader, room_id: String) -> String:
	var player_position: Vector3 = playable_ship.player.global_position
	var nearest_top_y: float = _nearest_floor_collision_top_y(loader, room_id, player_position)
	if nearest_top_y == INF:
		return "nearest_floor_not_found player_pos=%s" % str(player_position)
	if player_position.y < nearest_top_y + MIN_PLAYER_FLOOR_CLEARANCE:
		return (
			"player_below_nearest_floor player_y=%.3f floor_top_y=%.3f"
			% [player_position.y, nearest_top_y]
		)
	return ""


func _nearest_floor_collision_top_y(loader, room_id: String, world_position: Vector3) -> float:
	var room: Dictionary = loader._find_room_in_layout(room_id)
	if room.is_empty():
		return INF
	var placements_variant: Variant = room.get("structural_placements", [])
	if typeof(placements_variant) != TYPE_ARRAY:
		return INF
	var placements: Array = placements_variant
	var best_distance: float = INF
	var best_top_y: float = INF
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_variant
		var module_id: String = str(placement.get("module_id", placement.get("module", "")))
		if not FLOOR_MODULES.has(module_id):
			continue
		# Read both `position` (seed-17) and `world_position` (golden fixture)
		# defensively, matching `_read_placement_position()` semantics in
		# GeneratedShipLoader.
		var pos_variant: Variant = placement.get("position", null)
		if pos_variant == null:
			pos_variant = placement.get("world_position", null)
		if typeof(pos_variant) != TYPE_ARRAY:
			continue
		var pos: Array = pos_variant
		if pos.size() < 3:
			continue
		var placement_position: Vector3 = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var dx: float = placement_position.x - world_position.x
		var dz: float = placement_position.z - world_position.z
		var distance: float = dx * dx + dz * dz
		if distance < best_distance:
			best_distance = distance
			best_top_y = placement_position.y + FLOOR_COLLISION_HALF_HEIGHT
	return best_top_y


func _find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found: CollisionShape3D = _find_collision_shape(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COHERENT PLAYABLE TRAVERSAL FAIL reason=%s" % reason)
	quit(1)
