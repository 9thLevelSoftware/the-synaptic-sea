extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame_count := 0
var finished := false
var running := false
var _exit_code := 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

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
	var mgr = p.get_ship_systems_manager()
	for sid in ["power", "navigation", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents: mgr.force_repair(sid, sub.subcomponent_id)
	var world = p.get_synaptic_sea_world()
	var ir: Array = world.markers_in_range(p.scanner_state.range_radius)
	if ir.is_empty(): _fail("no markers"); return
	if not bool(p.travel_to_marker_id(String(ir[0].marker_id)).get("success", false)):
		_fail("travel failed"); return

	var home = p.get_home_ship_for_validation()
	var der = p.get_current_ship()
	var lb = p.get_lifeboat_ship_for_validation()
	# The real production controller crosses the authenticated away seam in both
	# directions. Closed collision denies the first attempt; endpoint-plane
	# ownership remains stable if the barrier closes behind either owner.
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("not aboard lifeboat after away dock"); return
	var host_endpoint: Dictionary = der.built_layout.boarding_endpoints_v1[0]
	var mobile_endpoint: Dictionary = lb.built_layout.boarding_endpoints_v1[0]
	var host_target: Vector3 = (der.scene_root as Node3D).global_transform \
		* _vector3(host_endpoint.interior_clearance_point_local)
	var mobile_target: Vector3 = (lb.scene_root as Node3D).global_transform \
		* _vector3(mobile_endpoint.interior_clearance_point_local)
	var closed_walk: Dictionary = await _walk_player(p, host_target, 60)
	if bool(closed_walk.get("reached", false)) \
			or p.get_current_occupancy_for_validation() != lb:
		_fail("away closed barrier allowed crossing"); return
	if not p.open_active_dock_barrier_for_validation():
		_fail("derelict barrier did not open"); return
	var host_walk: Dictionary = await _walk_player(p, host_target, 180)
	if not bool(host_walk.get("reached", false)) \
			or not bool(host_walk.get("grounded", false)) \
			or p.get_current_occupancy_for_validation() != der:
		_fail("away host traversal failed: %s" % JSON.stringify(host_walk)); return
	var barrier = p.dock_barriers[0] if not p.dock_barriers.is_empty() else null
	if barrier == null or str(barrier.connection_id).is_empty() \
			or str(barrier.host_endpoint_id) != str(host_endpoint.endpoint_id) \
			or str(barrier.mobile_endpoint_id) != str(mobile_endpoint.endpoint_id):
		_fail("away barrier endpoint pair is unauthenticated"); return
	barrier.set_opened(false)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != der:
		_fail("away close behind host rewrote ownership"); return
	var exact_plane: Vector3 = (der.scene_root as Node3D).global_transform \
		* _vector3(host_endpoint.local_position)
	if p._resolve_authenticated_dock_overlap(exact_plane, der) != lb:
		_fail("away exact threshold is not mobile-owned"); return
	barrier.set_opened(true)
	var mobile_walk: Dictionary = await _walk_player(p, mobile_target, 180)
	if not bool(mobile_walk.get("reached", false)) \
			or not bool(mobile_walk.get("grounded", false)) \
			or p.get_current_occupancy_for_validation() != lb:
		_fail("away mobile traversal failed: %s" % JSON.stringify(mobile_walk)); return
	barrier.set_opened(false)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("away close behind mobile rewrote ownership"); return
	if not p.travel_home():
		_fail("travel_home failed after physical return to lifeboat"); return
	p.recompute_occupancy()
	if p.get_current_ship() != home \
			or p.get_current_occupancy_for_validation() != lb \
			or lb.parent_ship != home:
		_fail("return-home did not retain lifeboat ownership and connection"); return
	var home_endpoint: Dictionary = home.built_layout.boarding_endpoints_v1[0]
	var home_barrier = p.dock_barriers[0] if not p.dock_barriers.is_empty() else null
	if home_barrier == null \
			or str(home_barrier.host_endpoint_id) != str(home_endpoint.endpoint_id) \
			or str(home_barrier.mobile_endpoint_id) != str(mobile_endpoint.endpoint_id):
		_fail("return-home barrier endpoint pair is unauthenticated"); return

	finished = true
	print("OCCUPANCY FLIP PASS away_bidirectional=true return_home_lifeboat=true")
	_teardown(0)

## Returns the global position of a room of `inst` that lies OUTSIDE `other`'s
## interior AABB (so occupancy resolves unambiguously to `inst`, not the overlapping
## docked piloted ship). Vector3.INF if none / structure unreadable.
func _room_outside(inst, other) -> Vector3:
	if inst == null or inst.scene_root == null or not is_instance_valid(inst.scene_root):
		return Vector3.INF
	var other_aabb: AABB = other.interior_aabb() if (other != null and other.scene_root != null and is_instance_valid(other.scene_root)) else AABB()
	var sr = inst.scene_root
	var st = sr.get_node_or_null("ShipStructure")
	if st == null:
		for c in sr.get_children():
			if c.get_child_count() > 0: st = c; break
	if st == null: return Vector3.INF
	for rn in st.get_children():
		if not (rn is Node3D): continue
		var gp: Vector3 = (rn as Node3D).global_position
		if not other_aabb.grow(0.001).has_point(gp):
			return gp
	return Vector3.INF

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

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
	push_error("OCCUPANCY FLIP FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(_exit_code)
