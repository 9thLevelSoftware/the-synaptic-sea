extends SceneTree

## R04 positive-path probe. It begins at the real title menu and uses the same
## player input signal, movement and interact priority as a fresh player. It
## deliberately contains no inventory, skill, repair, teleport, or snapshot seam.

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const TIMEOUT_FRAMES: int = 1800
const INTERACT_DISTANCE: float = 1.45

var title: Node
var frame_count: int = 0
var target_index: int = 0
var opening_dock: bool = true
var target_ids: Array[String] = ["start_supply_a", "start_supply_b"]
var searched_ids: Array[String] = []
var started: bool = false
var finished: bool = false
var waypoint_index: int = 0
var portal_interaction_attempts: Dictionary = {}


func _initialize() -> void:
	title = TITLE_SCENE.instantiate()
	if title == null:
		_fail("title scene could not instantiate")
		return
	get_root().add_child(title)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		var playable = title.get("playable_instance") if title != null else null
		var player = playable.get("player") if playable != null else null
		var target = _dock_barrier_for(playable) if playable != null and opening_dock else _container_for(playable, target_ids[target_index]) if playable != null and target_index < target_ids.size() else null
		var collision: KinematicCollision3D = _horizontal_slide_collision(player)
		var collider_name: String = str(collision.get_collider().name) if collision != null and collision.get_collider() != null else "none"
		var collider_path: String = str(collision.get_collider().get_path()) if collision != null and collision.get_collider() != null else "none"
		var collider_owner = collision.get_collider().get_parent() if collision != null and collision.get_collider() != null else null
		var collider_edge: String = str(collider_owner.get_meta("structural_edge_key", "")) if collider_owner != null else ""
		var collider_module: String = str(collider_owner.get_meta("module_kind", "")) if collider_owner != null else ""
		_fail("timed out title=%s dock_opening=%s searched=%s player=%s target=%s collider=%s collider_path=%s edge=%s module=%s normal=%s travel=%s remainder=%s slide_count=%d" % [
			str(started), str(opening_dock), str(searched_ids),
			str(player.global_position) if player != null else "none",
			str(target.global_position) if target != null else "none", collider_name, collider_path, collider_edge, collider_module,
			str(collision.get_normal()) if collision != null else "none",
			str(collision.get_travel()) if collision != null else "none",
			str(collision.get_remainder()) if collision != null else "none",
			player.get_slide_collision_count() if player != null else 0])
		return
	if not started:
		_start_new_game_through_title_input()
		return
	var playable = title.get("playable_instance")
	if playable == null or not bool(playable.get("playable_started")):
		return
	if opening_dock:
		_walk_and_open_dock(playable)
		return
	if target_index < target_ids.size():
		_walk_and_interact(playable, target_ids[target_index])
		return
	_observe_cold_route(playable)


func _start_new_game_through_title_input() -> void:
	if title == null or not is_instance_valid(title) or not title.has_method("_unhandled_input"):
		_fail("title input handler unavailable")
		return
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	title.call("_unhandled_input", accept)
	started = true


func _walk_and_interact(playable, container_id: String) -> void:
	var player = playable.get("player")
	var container = _container_for(playable, container_id)
	if player == null or container == null:
		_fail("missing live player/container id=%s" % container_id)
		return
	if _open_in_range_authored_portal(playable, player):
		return
	var delta: Vector3 = container.global_position - player.global_position
	delta.y = 0.0
	if delta.length() > INTERACT_DISTANCE:
		var next: Vector3 = _next_authored_waypoint(container_id, player.global_position, container.global_position)
		var step: Vector3 = next - player.global_position
		step.y = 0.0
		if step.length_squared() <= 0.0001:
			_fail("navigation produced no movement id=%s player=%s target=%s" % [
				container_id, str(player.global_position), str(container.global_position)])
			return
		# This drives PlayerController's production _physics_process and
		# move_and_slide path across the authored airlock, corridor, and ramp; it does not set
		# position or bypass range.
		player.set_scripted_move_direction(step.normalized())
		return
	player.clear_scripted_move_direction()
	var before: int = int(playable.inventory_state.get_quantity("circuit_board"))
	player.request_interact()
	if not bool(container.get("searched")):
		_fail("production interact did not search id=%s distance=%.3f" % [container_id, delta.length()])
		return
	if container_id == "start_supply_a" and int(playable.inventory_state.get_quantity("circuit_board")) <= before:
		_fail("starter container did not grant opening circuit board")
		return
	searched_ids.append(container_id)
	target_index += 1


func _walk_and_open_dock(playable) -> void:
	var player = playable.get("player")
	var barrier = _dock_barrier_for(playable)
	if player == null or barrier == null:
		_fail("fresh title route has no live player/dock barrier")
		return
	var delta: Vector3 = barrier.global_position - player.global_position
	delta.y = 0.0
	if delta.length() > INTERACT_DISTANCE:
		var next: Vector3 = barrier.global_position
		var step: Vector3 = next - player.global_position
		step.y = 0.0
		if step.length_squared() <= 0.0001:
			_fail("navigation produced no movement dock=%s player=%s target=%s" % [
				str(barrier.get("marker_id")), str(player.global_position), str(barrier.global_position)])
			return
		player.set_scripted_move_direction(step.normalized())
		return
	player.clear_scripted_move_direction()
	player.request_interact()
	if not bool(barrier.get("opened")):
		_fail("production interact did not open intact dock=%s distance=%.3f" % [
			str(barrier.get("marker_id")), delta.length()])
		return
	opening_dock = false
	waypoint_index = 0
	print("R04 NATURAL ROUTE DOCK OPENED marker=%s position=%s" % [str(barrier.get("marker_id")), str(barrier.global_position)])


func _container_for(playable, container_id: String):
	for candidate in playable.get("loot_containers") as Array:
		if is_instance_valid(candidate) and str(candidate.get("container_id")) == container_id:
			return candidate
	return null


func _dock_barrier_for(playable):
	for candidate in playable.get("dock_barriers") as Array:
		if is_instance_valid(candidate) and not bool(candidate.get("opened")):
			return candidate
	return null


func _open_in_range_authored_portal(playable, player) -> bool:
	var active_loader = playable.get("loader")
	if active_loader == null or not active_loader.has_method("get_authored_portal_nodes"):
		return false
	var collision: KinematicCollision3D = _portal_blocker_slide_collision(player)
	var collider = collision.get_collider() if collision != null else null
	if collider == null:
		return false
	var blocking_portal = collider.get_parent()
	for portal in active_loader.get_authored_portal_nodes() as Array:
		if not is_instance_valid(portal) or portal != blocking_portal or bool(portal.get("is_open")):
			continue
		player.clear_scripted_move_direction()
		player.request_interact()
		if not bool(portal.get("is_open")):
			var portal_id: String = str(portal.get("portal_id"))
			var attempts: int = int(portal_interaction_attempts.get(portal_id, 0)) + 1
			portal_interaction_attempts[portal_id] = attempts
			if attempts > 3:
				_fail("ordinary interactions did not open blocking authored portal=%s distance=%.3f attempts=%d" % [
					portal_id, portal.global_position.distance_to(player.global_position), attempts])
			else:
				print("R04 NATURAL ROUTE PORTAL PREEMPTED id=%s attempt=%d" % [portal_id, attempts])
			return true
		print("R04 NATURAL ROUTE PORTAL OPENED id=%s position=%s" % [
			str(portal.get("portal_id")), str(portal.global_position)])
		return true
	return false


func _horizontal_slide_collision(player) -> KinematicCollision3D:
	if player == null or not player.has_method("get_slide_collision_count"):
		return null
	for index in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		if collision != null and absf(collision.get_normal().y) < 0.5:
			return collision
	return player.get_last_slide_collision() if player.has_method("get_last_slide_collision") else null


func _portal_blocker_slide_collision(player) -> KinematicCollision3D:
	if player == null or not player.has_method("get_slide_collision_count"):
		return null
	for index in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		var collider = collision.get_collider() if collision != null else null
		if collider != null and str(collider.name) == "PortalBlocker":
			return collision
	return null


func _next_authored_waypoint(container_id: String, player_position: Vector3, target: Vector3) -> Vector3:
	# The generated home has no NavigationRegion3D. These are the authored, open
	# airlock -> corridor -> ramp -> spine cells from coherent_ship_001; every
	# leg is traversed by PlayerController.move_and_slide, including the ramp.
	var route: Array[Vector3] = [
		Vector3(4.0, 0.0, 2.0),
		Vector3(4.0, 0.0, 0.4),
		Vector3(6.0, 0.0, 0.4),
		Vector3(12.0, 0.0, 0.4),
		Vector3(18.0, 4.0, 0.4),
		Vector3(22.0, 4.0, 0.4),
	]
	if container_id == "start_supply_a":
		route.append(Vector3(22.0, 4.0, 4.0))
	while waypoint_index < route.size():
		var waypoint: Vector3 = route[waypoint_index]
		var flat_delta: Vector3 = waypoint - player_position
		flat_delta.y = 0.0
		if flat_delta.length() > 0.75:
			return waypoint
		waypoint_index += 1
	return target


func _lot_origins_for(inventory, item_id: String) -> Array:
	var lots: Array = []
	var summary: Dictionary = inventory.get_lot_summary()
	for lot_v in summary.get("lots", []) as Array:
		if lot_v is Dictionary and str((lot_v as Dictionary).get("item_id", "")) == item_id:
			lots.append((lot_v as Dictionary).duplicate(true))
	return lots


func _observe_cold_route(playable) -> void:
	var inventory = playable.inventory_state
	var board_lots: Array = _lot_origins_for(inventory, "circuit_board")
	var book_lots: Array = _lot_origins_for(inventory, "fabrication_schematic_basic")
	var nozzle_lots: Array = _lot_origins_for(inventory, "thruster_nozzle")
	var cutter_lots: Array = _lot_origins_for(inventory, "plasma_cutter")
	print("R04 NATURAL ROUTE OBSERVATION searched=%s circuit_lots=%s book_lots=%s nozzle_lots=%s cutter_lots=%s" % [
		str(searched_ids), str(board_lots), str(book_lots), str(nozzle_lots), str(cutter_lots)])
	if board_lots.is_empty():
		_fail("opening repair has no authored starter lot")
		return
	# Start supplies prove the opening circuit only. The fabrication book and
	# titanium donor are later ordinary repair/boarding/exploration legs, so an
	# absent early roll is observation rather than an acquisition failure.
	_fail("starter checkpoint reached; later book/donor and craft/consumer legs are not implemented")


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	print("FAIL: FC P09 NATURAL ROUTE %s" % reason)
	quit(1)
