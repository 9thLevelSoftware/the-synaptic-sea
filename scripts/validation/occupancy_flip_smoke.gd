extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
var main_node: Node
var frame_count := 0
var finished := false
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
	# Phase 5b Task 5 (physical-travel contract): the piloted lifeboat physically docks
	# flush to the derelict's airlock, so its interior AABB overlaps the derelict's dock-
	# seam rooms (and occupancy prioritizes the piloted ship). Standing at the derelict
	# ROOT ORIGIN now reads as the docked lifeboat — that is the new ride-aboard reality.
	# To prove the host occupancy flip, stand in a host ROOM that lies OUTSIDE the docked
	# lifeboat's interior (i.e. a room the player reaches after crossing the dock seam).
	var der_pt = _room_outside(der, lb)
	if der_pt == Vector3.INF: _fail("no derelict room outside the docked lifeboat"); return
	# Phase 5b Task 6 ("must open the port to board"): the derelict's dock-seam barrier
	# spawns CLOSED on travel and now gates host occupancy — a closed-seam host is NOT
	# resolvable as occupied. Open it first so crossing into the host reads as boarded.
	if not p.open_active_dock_barrier_for_validation(): _fail("derelict barrier did not open"); return
	p.player.teleport_to(der_pt)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != der: _fail("not aboard derelict after teleport"); return
	# Walk back to a home ROOM outside the docked lifeboat — occupancy flips to home.
	var home_pt = _room_outside(home, lb)
	if home_pt == Vector3.INF: _fail("no home room outside the docked lifeboat"); return
	p.player.teleport_to(home_pt)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != home: _fail("not aboard home after return"); return

	finished = true
	print("OCCUPANCY FLIP PASS derelict=true home=true")
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
