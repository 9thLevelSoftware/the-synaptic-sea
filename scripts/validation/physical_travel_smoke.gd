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
	# Repair lifeboat propulsion so travel is permitted (validation seam).
	p.force_repair_all_for_validation()
	# Board the lifeboat (validation seam: teleport into the piloted ship interior).
	p.board_piloted_ship_for_validation()
	p.recompute_occupancy()
	var lb = p.get_lifeboat_ship_for_validation()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("not aboard piloted ship before travel"); return

	var ids: Array = p.scannable_marker_ids_for_validation()
	if ids.is_empty(): _fail("no scannable markers"); return
	var res: Dictionary = p.travel_to_marker_id(String(ids[0]))
	if not bool(res.get("success", false)): _fail("travel failed: %s" % str(res.get("reason",""))); return

	# (a) Player still inside the lifeboat (NOT teleported into the derelict).
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != lb:
		_fail("player not aboard lifeboat after travel (was teleported into derelict)"); return

	# (b) Lifeboat repositioned flush to the new host (gap small) — proves a real dock, not a parked offset.
	var host = p.get_current_host_for_validation()
	if host == null or host == lb: _fail("no distinct host after travel"); return
	if not p.piloted_flush_to_host_for_validation():
		_fail("lifeboat airlock not flush to target dock after travel"); return

	# (c) A closed dock barrier exists for the target.
	if not p.has_closed_dock_barrier_for_validation():
		_fail("no closed dock barrier spawned at target"); return

	done = true
	print("PHYSICAL TRAVEL PASS aboard_lifeboat=true flush=true barrier_closed=true")
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
	push_error("PHYSICAL TRAVEL FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
