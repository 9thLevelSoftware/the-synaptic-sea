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
	var derelict = p.get_home_ship_for_validation()
	var lifeboat = p.get_lifeboat_ship_for_validation()
	if derelict == null or lifeboat == null: _fail("missing starting derelict or lifeboat"); return
	if lifeboat.parent_ship != derelict: _fail("lifeboat not docked to starting derelict"); return
	# Two ships co-present, separated.
	if p.active_ship_root_count_for_validation() < 2: _fail("pair not co-present"); return
	# Phase 5b: the lifeboat now PORT-DOCKS adjacent to the home airlock (not the old
	# -35 anchor), so the player-aboard-derelict invariant is checked via real occupancy
	# (Task 2 made interior_aabb/occupancy reliable in headless). The home ship is the
	# starting derelict, so occupancy == home derelict means "aboard the starting derelict".
	if p.player == null: _fail("no player"); return
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != derelict:
		_fail("player not aboard starting derelict (occupancy != home)"); return
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

	finished = true
	print("CANONICAL OPENING PASS docked=true aboard_derelict=true prop_offline=true loot=true repair_in_lifeboat=true")
	_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

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
