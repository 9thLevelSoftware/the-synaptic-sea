extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame_count := 0
var finished := false
var running := false
var _exit_code := 0
var opening_publication_events: Array[String] = []

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	# Main creates the playable during its own _ready(). Observe the child as it
	# enters the tree so this connection exists before the playable's _ready()
	# synchronously publishes the fresh opening transaction.
	main_node.child_entered_tree.connect(_on_main_child_entered_tree)
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_main_child_entered_tree(child: Node) -> void:
	if not child is PlayableGeneratedShip:
		return
	child.fresh_opening_publication_event.connect(
		func(kind: String, owner_ship_id: String) -> void:
			opening_publication_events.append("%s:%s" % [kind, owner_ship_id]))

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("no playable")
		return
	if not running:
		running = true
		_run(p)

func _run(p) -> void:
	var derelict = p.get_home_ship_for_validation()
	var lifeboat = p.get_lifeboat_ship_for_validation()
	if derelict == null or lifeboat == null: _fail("missing starting derelict or lifeboat"); return
	if lifeboat.parent_ship != derelict: _fail("lifeboat not docked to starting derelict"); return
	# Two ships co-present, separated.
	if p.active_ship_root_count_for_validation() < 2: _fail("pair not co-present"); return
	# R10-A physical-travel contract: the player boots inside the docked lifeboat
	# (their ride), which is port-docked to the starting derelict's airlock. The two
	# hulls meet without any positive cross-hull overlap, and occupancy resolves the player
	# from their actual fresh lifeboat spawn to the lifeboat — the new
	# "aboard your ride, docked to the starting derelict" semantics. (Pre-5b this asserted
	# occupancy == home derelict; the ride-aboard model supersedes teleport-into-derelict.)
	if p.player == null: _fail("no player"); return
	if opening_publication_events != ["fresh_spawn_placed:lifeboat",
			"occupancy_published:lifeboat"]:
		_fail("fresh opening placement/publication order invalid: %s" % str(
			opening_publication_events)); return
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lifeboat:
		_fail("player not aboard docked lifeboat at boot (occupancy != lifeboat) pos=%s bounds=%s" % [
			str((p.player as Node3D).global_position), str(lifeboat.interior_aabb())]); return
	var spawn_layout: Dictionary = lifeboat.built_layout.duplicate(true)
	var spawn_valid: Dictionary = p.validate_initial_lifeboat_spawn_for_validation(
		spawn_layout)
	if not bool(spawn_valid.get("ok", false)):
		_fail("authored initial lifeboat spawn is not collision-clear"); return
	var missing_spawn: Dictionary = spawn_layout.duplicate(true)
	missing_spawn.erase("initial_player_spawn_v1")
	var event_count_before_denial: int = opening_publication_events.size()
	if str(p.validate_initial_lifeboat_spawn_for_validation(
			missing_spawn).get("reason", "")) != "spawn_missing":
		_fail("missing initial spawn did not fail closed"); return
	if opening_publication_events.size() != event_count_before_denial:
		_fail("failed spawn validation partially published opening state"); return
	var malformed_spawn: Dictionary = spawn_layout.duplicate(true)
	malformed_spawn.initial_player_spawn_v1.local_position = [4.0, 0.55]
	if str(p.validate_initial_lifeboat_spawn_for_validation(
			malformed_spawn).get("reason", "")) != "spawn_position_invalid":
		_fail("malformed initial spawn did not fail closed"); return
	var foreign_spawn: Dictionary = spawn_layout.duplicate(true)
	foreign_spawn.initial_player_spawn_v1.owner_ship_id = "foreign-owner"
	if str(p.validate_initial_lifeboat_spawn_for_validation(
			foreign_spawn).get("reason", "")) != "spawn_owner_mismatch":
		_fail("foreign initial spawn owner did not fail closed"); return
	var blocked_spawn: Dictionary = spawn_layout.duplicate(true)
	var blocked_fixture: Dictionary = _blocked_spawn_fixture(spawn_layout)
	if not bool(blocked_fixture.get("ok", false)):
		_fail("could not derive blocked spawn from compiled wall placement"); return
	blocked_spawn.initial_player_spawn_v1.local_position = blocked_fixture.position
	var authority_verdict: Dictionary = p.validate_initial_lifeboat_spawn_for_validation(
		blocked_spawn)
	if str(authority_verdict.get("reason", "")) != "spawn_layout_invalid" \
			or str(authority_verdict.get("detail", "")) != "spawn_authority":
		_fail("moved spawn bypassed authored authority: %s" % JSON.stringify(
			authority_verdict)); return
	var blocked_verdict: Dictionary = DockingManagerScript.validate_registered_spawn_clear(
		spawn_layout, (lifeboat.scene_root as Node3D).global_transform,
		_vector3(blocked_fixture.position))
	if str(blocked_verdict.get("reason", "")) != "spawn_capsule_blocked" \
			or str(blocked_verdict.get("placement_id", "")) \
				!= str(blocked_fixture.placement_id):
		_fail("blocked initial spawn did not fail closed: %s fixture=%s" % [
			JSON.stringify(blocked_verdict), JSON.stringify(blocked_fixture)]); return
	# Lifeboat propulsion offline at boot (opening damage retained).
	var mgr = p.get_ship_systems_manager()
	if mgr.is_operational("propulsion"): _fail("lifeboat propulsion should be offline at boot"); return
	# Starting loot lives on the derelict and yields a circuit_board.
	if p.loot_containers.is_empty(): _fail("no starting loot on derelict"); return
	for lc in p.loot_containers:
		p.search_loot_container_for_validation(String(lc.container_id))
	if p.inventory_state.get_quantity("circuit_board") < 1: _fail("derelict loot did not yield circuit_board"); return

	# Phase 5a regression (Codex P1 re-reviews): every home repair point must sit ON an
	# ACTUAL lifeboat room floor, not (a) offset into the void by a derelict-frame coordinate,
	# nor (b) at a hardcoded grid that StructuralPlacer's BFS layout doesn't honor. Read the
	# real room positions from the built lifeboat structure and require each repair point to
	# be within ~1 cell of one — and the travel-gating propulsion/nav_linkage point to exist.
	var structure = lifeboat.scene_root.get_node_or_null("ShipStructure")
	if structure == null:
		for c in lifeboat.scene_root.get_children():
			if c.get_child_count() > 0: structure = c; break
	var lb_rooms: Array = []
	if structure != null:
		for rn in structure.get_children():
			if rn is Node3D: lb_rooms.append((rn as Node3D).global_position)
	if lb_rooms.is_empty(): _fail("could not read lifeboat room positions"); return
	if p.repair_points.is_empty(): _fail("no home repair points built"); return
	var found_prop := false
	for rp in p.repair_points:
		var nearest := 1.0e9
		for rpos in lb_rooms:
			nearest = min(nearest, rp.global_position.distance_to(rpos))
		if nearest > 3.0:
			_fail("repair point %s/%s off lifeboat floor (nearest room %.1f)" % [str(rp.system_id), str(rp.subcomponent_id), nearest]); return
		if rp.system_id == "propulsion" and rp.subcomponent_id == "nav_linkage": found_prop = true
	if not found_prop: _fail("no propulsion/nav_linkage repair point found"); return

	# R10-A baseline: drive the real production PlayerController through its
	# ordinary scripted-input seam. The closed barrier must deny crossing; after
	# opening, the same body must remain floor-supported and change authoritative
	# occupancy in both directions without a teleport.
	if p.player.get_script() != preload("res://scripts/player/player_controller.gd"):
		_fail("boot player is not the production PlayerController"); return
	var home_endpoint: Dictionary = derelict.built_layout.boarding_endpoints_v1[0]
	var mobile_endpoint: Dictionary = lifeboat.built_layout.boarding_endpoints_v1[0]
	var home_target: Vector3 = (derelict.scene_root as Node3D).global_transform \
		* _vector3(home_endpoint.interior_clearance_point_local)
	var mobile_target: Vector3 = (lifeboat.scene_root as Node3D).global_transform \
		* _vector3(mobile_endpoint.interior_clearance_point_local)
	var closed_walk: Dictionary = await _walk_player(p, home_target, 60)
	if bool(closed_walk.get("reached", false)) \
			or p.get_current_occupancy_for_validation() != lifeboat:
		_fail("closed dock barrier allowed production traversal"); return
	if not p.open_active_dock_barrier_for_validation():
		_fail("could not open boot dock barrier"); return
	var outward_walk: Dictionary = await _walk_player(p, home_target, 180)
	if not bool(outward_walk.get("reached", false)) \
			or not bool(outward_walk.get("grounded", false)) \
			or p.get_current_occupancy_for_validation() != derelict:
		_fail("production traversal into home failed: %s" % JSON.stringify(
			outward_walk)); return
	var active_barrier = p.dock_barriers[0] if not p.dock_barriers.is_empty() else null
	if active_barrier == null or str(active_barrier.connection_id).is_empty() \
			or str(active_barrier.host_endpoint_id) != str(
				home_endpoint.endpoint_id) \
			or str(active_barrier.mobile_endpoint_id) != str(
				mobile_endpoint.endpoint_id):
		_fail("boot barrier does not authenticate the active endpoint pair"); return
	active_barrier.set_opened(false)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != derelict:
		_fail("closing barrier behind host-side player rewrote ownership"); return
	var exact_plane: Vector3 = (derelict.scene_root as Node3D).global_transform \
		* _vector3(home_endpoint.local_position)
	if p._resolve_authenticated_dock_overlap(exact_plane, derelict) != lifeboat:
		_fail("exact shared threshold is not mobile-owned"); return
	active_barrier.set_opened(true)
	var return_walk: Dictionary = await _walk_player(p, mobile_target, 180)
	if not bool(return_walk.get("reached", false)) \
			or not bool(return_walk.get("grounded", false)) \
			or p.get_current_occupancy_for_validation() != lifeboat:
		_fail("production traversal into lifeboat failed: %s" % JSON.stringify(
			return_walk)); return
	active_barrier.set_opened(false)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lifeboat:
		_fail("closing barrier behind mobile-side player rewrote ownership"); return

	finished = true
	print("CANONICAL OPENING PASS docked=true aboard_lifeboat=true prop_offline=true loot=true repair_in_lifeboat=true traversal=production_bidirectional")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null


func _blocked_spawn_fixture(layout: Dictionary) -> Dictionary:
	var structural_plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	for placement_variant in structural_plan.get("placements", []):
		if not placement_variant is Dictionary:
			continue
		var placement: Dictionary = placement_variant
		var module_id: String = str(placement.get("module_id", ""))
		var position_variant: Variant = placement.get("position", null)
		if not module_id.begins_with("wall_") or not position_variant is Vector3:
			continue
		var wall_position: Vector3 = position_variant as Vector3
		return {"ok": true,
			"placement_id": str(placement.get("placement_id", "")),
			"position": [wall_position.x, 0.55, wall_position.z]}
	return {"ok": false}

func _walk_player(p, target: Vector3, max_frames: int) -> Dictionary:
	var body = p.player
	for settle_frame in range(90):
		await physics_frame
		p.recompute_occupancy()
		if body.is_on_floor():
			break
	var grounded: bool = body.is_on_floor()
	var reached: bool = false
	for move_frame in range(max_frames):
		var offset: Vector3 = target - body.global_position
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		if horizontal.length() <= 0.14:
			reached = true
			break
		body.set_scripted_move_direction(horizontal.normalized())
		await physics_frame
		p.recompute_occupancy()
		grounded = grounded and body.is_on_floor()
	body.clear_scripted_move_direction()
	await physics_frame
	p.recompute_occupancy()
	return {"reached": reached, "grounded": grounded,
		"final_position": body.global_position}

func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _fail(r: String) -> void:
	if finished: return
	finished = true
	push_error("CANONICAL OPENING FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(_exit_code)
