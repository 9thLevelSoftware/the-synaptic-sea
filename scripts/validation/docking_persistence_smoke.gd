extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 900
var main_node: Node
var frame := 0
var done := false
var code := 0
var phase := 0
var target_id := ""

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if done: return
	frame += 1
	var p = _find(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame > TIMEOUT_FRAMES: _fail("no playable")
		return
	if phase == 0:
		p.force_repair_all_for_validation()
		p.board_piloted_ship_for_validation()
		p.recompute_occupancy()
		var ids: Array = p.scannable_marker_ids_for_validation()
		if ids.is_empty(): _fail("no markers"); return
		target_id = String(ids[0])
		if not bool(p.travel_to_marker_id(target_id).get("success", false)): _fail("travel failed"); return
		p.open_active_dock_barrier_for_validation()
		if not p.save_world_for_validation(): _fail("save failed"); return
		phase = 1
		return
	if phase == 1:
		if not p.load_world_for_validation(): _fail("load failed"); return
		phase = 2
		return
	if phase == 2:
		# Restored: piloted ship docked to the same host, aboard piloted ship, port opened.
		var host = p.get_current_host_for_validation()
		if host == null or String(host.marker_id) != target_id: _fail("host not restored"); return
		var lb = p.get_lifeboat_ship_for_validation()
		if lb == null or lb.parent_ship != host: _fail("piloted not re-docked to host"); return

		# dock_edge=true: the edge must ROUND-TRIP from the snapshot, not just happen to
		# exist. _apply_docking_snapshot consumed ws.dock_edges on load; the live edge set
		# must now be non-empty and name the saved host (marker_id) + mobile (ship_id).
		var edges: Array = p.current_dock_edges_for_validation()
		if edges.is_empty(): _fail("dock_edge: edge set empty after load"); return
		var edge: Dictionary = edges[0]
		if String(edge.get("host", "")) != target_id:
			_fail("dock_edge: restored edge host '%s' != saved host '%s'" % [String(edge.get("host", "")), target_id]); return
		if String(edge.get("mobile", "")) != String(lb.ship_id):
			_fail("dock_edge: restored edge mobile '%s' != piloted ship id '%s'" % [String(edge.get("mobile", "")), String(lb.ship_id)]); return

		# occupancy=true: _apply_docking_snapshot restored current_occupancy from
		# ws.aboard_ship_id (the lifeboat the player rode at save). Assert it directly —
		# the player was aboard the piloted ship when they breached + saved.
		var occ = p.get_current_occupancy_for_validation()
		if occ != lb:
			_fail("occupancy: current_occupancy != piloted ship after load (got %s)" % str(occ)); return

		# opened_port=true: a fresh barrier rebuild spawns CLOSED; only the restore opens it.
		if not p.restored_port_opened_for_validation(target_id): _fail("opened-port flag not restored"); return
		done = true
		print("DOCKING PERSISTENCE PASS dock_edge=true occupancy=true opened_port=true")
		_teardown(0)

func _find(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if done: return
	done = true
	push_error("DOCKING PERSISTENCE FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
