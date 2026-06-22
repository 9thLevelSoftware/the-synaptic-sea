extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
var main_node: Node
var frame := 0
var done := false
var code := 0

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
	_run(p)

func _run(p) -> void:
	p.force_repair_all_for_validation()
	p.board_piloted_ship_for_validation()
	p.recompute_occupancy()
	var ids: Array = p.scannable_marker_ids_for_validation()
	if ids.is_empty(): _fail("no markers"); return
	if not bool(p.travel_to_marker_id(String(ids[0])).get("success", false)): _fail("travel failed"); return

	var lb = p.get_lifeboat_ship_for_validation()
	var host = p.get_current_host_for_validation()

	# (a) Closed barrier + in lifeboat -> occupancy is the lifeboat.
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb: _fail("not in lifeboat pre-board"); return

	# (b) Open/breach the barrier deterministically (validation seam drives the channel).
	if not p.open_active_dock_barrier_for_validation(): _fail("barrier did not open"); return

	# (c) Cross into the derelict -> occupancy flips to the host.
	p.board_host_for_validation()
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != host: _fail("occupancy did not flip to host after boarding"); return

	done = true
	print("BOARDING FLIP PASS closed_in_lifeboat=true barrier_opens=true flips_to_host=true")
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
	push_error("BOARDING FLIP FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
