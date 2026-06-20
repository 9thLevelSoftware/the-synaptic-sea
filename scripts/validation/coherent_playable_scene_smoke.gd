extends SceneTree

const COHERENT_PLAYABLE_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

var frame_count: int = 0
var finished: bool = false
var playable_ship
var ready_received: bool = false
var printed_pass: bool = false

func _initialize() -> void:
	playable_ship = COHERENT_PLAYABLE_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if ready_received and not printed_pass:
		printed_pass = true
		print("COHERENT PLAYABLE SCENE PASS frames=%d" % frame_count)
		finished = true
		quit(0)

func _on_playable_ready(summary: Dictionary) -> void:
	ready_received = true
	var player_spawned: bool = bool(summary.get("player_spawned", false))
	var objective_count: int = int(summary.get("objective_count", 0))
	var loader = playable_ship.loader
	if loader == null or not loader.has_method("get_critical_path"):
		_fail("loader missing get_critical_path")
		return
	var critical_path_size: int = loader.get_critical_path().size()
	var landmark_count: int = 0
	if loader.has_method("get_landmark_nodes"):
		landmark_count = loader.get_landmark_nodes().size()
	if not player_spawned:
		_fail("player_spawned=false")
		return
	if objective_count != 4:
		_fail("objective_count=%d" % objective_count)
		return
	if critical_path_size != 5:
		_fail("critical_path=%d" % critical_path_size)
		return
	if landmark_count < 2:
		_fail("landmarks=%d" % landmark_count)
		return
	print("COHERENT PLAYABLE SCENE READY player_spawned=true objectives=%d critical_path=%d landmarks=%d" % [objective_count, critical_path_size, landmark_count])

func _on_playable_failed(reason: String) -> void:
	_fail(reason)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COHERENT PLAYABLE SCENE FAIL reason=%s" % reason)
	quit(1)