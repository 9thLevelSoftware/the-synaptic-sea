extends SceneTree

## Broken dock barrier: second interact while channeling is consumed (no fall-through).
## Marker: DOCK BARRIER CHANNEL CONSUME PASS start=true channeling=true second=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	if playable.player == null:
		_fail("player"); return
	var barrier = DockPortBarrierScript.new()
	var pos: Vector3 = (playable.player as Node3D).global_position
	playable.add_child(barrier)
	barrier.configure("channel_consume_test", "broken", playable.player_progression, pos, 6.0, 1.8)
	if not barrier.try_start(playable.player):
		_fail("first try_start failed"); return
	if not bool(barrier.channeling):
		_fail("not channeling after start"); return
	# Second interact must still return true (consume) while channeling.
	if not barrier.try_start(playable.player):
		_fail("second try_start did not consume while channeling"); return
	if bool(barrier.opened):
		_fail("opened early without complete"); return
	if not bool(barrier.channeling):
		_fail("channeling cleared on second interact"); return

	print("DOCK BARRIER CHANNEL CONSUME PASS start=true channeling=true second=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("DOCK BARRIER CHANNEL CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
