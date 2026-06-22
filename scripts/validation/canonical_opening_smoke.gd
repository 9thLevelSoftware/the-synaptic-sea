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
	# Spatial-separation check: the player spawned on the derelict side — nearer the
	# derelict than the docked lifeboat. AABB-independent (does NOT call
	# recompute_occupancy, which falls back to home_ship in headless where the
	# lifeboat's interior_aabb is zero-size and cannot distinguish the two ships).
	if p.player == null: _fail("no player"); return
	var pp: Vector3 = (p.player as Node3D).global_position
	var d_to_derelict: float = pp.distance_to(derelict.scene_root.global_position)
	var d_to_lifeboat: float = pp.distance_to(lifeboat.scene_root.global_position)
	if d_to_derelict >= d_to_lifeboat: _fail("player not spawned on derelict side (nearer lifeboat)"); return
	# Lifeboat propulsion offline at boot (opening damage retained).
	var mgr = p.get_ship_systems_manager()
	if mgr.is_operational("propulsion"): _fail("lifeboat propulsion should be offline at boot"); return
	# Starting loot lives on the derelict and yields a circuit_board.
	if p.loot_containers.is_empty(): _fail("no starting loot on derelict"); return
	for lc in p.loot_containers:
		p.search_loot_container_for_validation(String(lc.container_id))
	if p.inventory_state.get_quantity("circuit_board") < 1: _fail("derelict loot did not yield circuit_board"); return

	# Phase 5a regression (Codex P1 re-review): the travel-gating propulsion repair point
	# must sit INSIDE the docked lifeboat (parented under lifeboat.scene_root at a lifeboat-
	# LOCAL position), not offset out into the void by a derelict-frame coordinate. The
	# lifeboat is a 3-cell (~12u) structure, so a correctly-placed point is within ~8u of
	# its root; the bug placed it up to ~24u away (derelict-frame + lifeboat offset).
	var lb_o: Vector3 = lifeboat.scene_root.global_position
	var found_rp := false
	for rp in p.repair_points:
		if rp.system_id == "propulsion" and rp.subcomponent_id == "nav_linkage":
			found_rp = true
			var dist: float = rp.global_position.distance_to(lb_o)
			if dist > 8.0: _fail("propulsion repair point not inside lifeboat (dist=%.1f)" % dist); return
	if not found_rp: _fail("no propulsion/nav_linkage repair point found"); return

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
