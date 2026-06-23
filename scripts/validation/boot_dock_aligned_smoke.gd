extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const TIMEOUT_FRAMES: int = 300
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
	var home = p.get_home_ship_for_validation()
	var lb = p.get_lifeboat_ship_for_validation()
	if home == null or lb == null: _fail("missing home/lifeboat"); return
	if lb.parent_ship != home: _fail("lifeboat not docked to home"); return

	# Host dock port lifted to world, and lifeboat airlock port lifted to world via the
	# lifeboat's actual placed transform, must be coincident (flush dock — NOT the old
	# fixed -35 offset which left a ~30u gap).
	var home_local = DockPortsScript.for_derelict(home.blueprint_layout_for_validation())
	var host_world = DockingManagerScript.host_port_to_world(home, home_local)
	var lb_local = DockPortsScript.for_lifeboat(lb.blueprint_layout_for_validation())
	var lb_world: Vector3 = lb.scene_root.global_transform * (lb_local["position"] as Vector3)
	var gap: float = lb_world.distance_to(host_world["position"] as Vector3)
	if gap > 0.5:
		_fail("lifeboat airlock not flush to home dock (gap=%.2f)" % gap); return

	done = true
	print("BOOT DOCK ALIGNED PASS flush=true gap_lt_0p5=true")
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
	push_error("BOOT DOCK ALIGNED FAIL reason=%s" % r)
	_teardown(1)

func _teardown(c: int) -> void:
	code = c
	if main_node != null and is_instance_valid(main_node): main_node.free(); main_node = null
	call_deferred("_q")

func _q() -> void: quit(code)
