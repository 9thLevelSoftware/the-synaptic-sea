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
	var world = p.get_sargasso_world()
	var ir: Array = world.markers_in_range(p.scanner_state.range_radius)
	if ir.is_empty(): _fail("no markers"); return
	if not bool(p.travel_to_marker_id(String(ir[0].marker_id)).get("success", false)):
		_fail("travel failed"); return

	var home = p.get_home_ship_for_validation()
	var der = p.get_current_ship()
	# Stand inside the derelict.
	p.player.teleport_to(der.scene_root.global_position)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != der: _fail("not aboard derelict after teleport"); return
	# Walk back to the home ship.
	p.player.teleport_to(home.scene_root.global_position)
	p.recompute_occupancy()
	if p.get_current_occupancy_for_validation() != home: _fail("not aboard home after return"); return

	finished = true
	print("OCCUPANCY FLIP PASS derelict=true home=true")
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
	push_error("OCCUPANCY FLIP FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(_exit_code)
