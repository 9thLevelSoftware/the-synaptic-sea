extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	var p = _find_playable(main_node)
	if p == null or p.loader == null or not p.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("no playable/loader")
		return
	_validate(p)

func _validate(p) -> void:
	# Pick any in-range marker and travel.
	var world = p.get_sargasso_world()
	var in_range: Array = world.markers_in_range(p.scanner_state.range_radius)
	if in_range.is_empty(): _fail("no markers in range"); return
	# Force propulsion operational so travel is allowed (foundation test, not gate test).
	var mgr = p.get_ship_systems_manager()
	for sid in ["power", "navigation", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				mgr.force_repair(sid, sub.subcomponent_id)
	var res: Dictionary = p.travel_to_marker_id(String(in_range[0].marker_id))
	if not bool(res.get("success", false)): _fail("travel failed: %s" % str(res.get("reason",""))); return

	if p.active_ship_root_count_for_validation() < 2:
		_fail("home + derelict not co-present (count<2)"); return
	var home = p.get_home_ship_for_validation()
	var cur = p.get_current_ship()
	if home == null or cur == null or home == cur: _fail("home/current not distinct"); return
	var home_o: Vector3 = home.scene_root.global_position
	var der_o: Vector3 = cur.scene_root.global_position
	if home_o.distance_to(der_o) < 10.0:
		_fail("ships not spatially separated (%.1f)" % home_o.distance_to(der_o)); return
	# Derelict loot containers (if any) must sit nearer the derelict than the home origin.
	for lc in p.loot_containers:
		if lc.global_position.distance_to(der_o) > lc.global_position.distance_to(home_o):
			_fail("derelict loot not parented under moved derelict root"); return

	finished = true
	print("DOCK COPRESENCE PASS roots=%d separated=true loot_aligned=true" % p.active_ship_root_count_for_validation())
	_teardown(0)

func _find_playable(n: Node):
	if n is PlayableGeneratedShip: return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null: return f
	return null

func _fail(r: String) -> void:
	if finished: return
	finished = true
	push_error("DOCK COPRESENCE FAIL reason=%s" % r)
	_teardown(1)

func _teardown(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_quit")

func _quit() -> void:
	quit(_exit_code)
