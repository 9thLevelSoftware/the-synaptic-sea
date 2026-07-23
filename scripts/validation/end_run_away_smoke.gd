extends SceneTree

## End-run death/complete SFX works with away_from_start true.
## Marker: END RUN AWAY PASS away=true death=true complete=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
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
	playable.away_from_start = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	var mgr: Node = playable.audio_manager

	mgr.sfx_router.configure({})
	var death_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	playable.slice_complete = false
	playable.end_run("death")
	var death_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_VITALS_LOW))
	if death_after <= death_before:
		_fail("death UI_VITALS_LOW missing away"); return

	mgr.sfx_router.configure({})
	playable.slice_complete = false
	playable.away_from_start = true
	var complete_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	playable.end_run("completion")
	var complete_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if complete_after <= complete_before:
		_fail("completion UI_OBJECTIVE_ADVANCE missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("END RUN AWAY PASS away=true death=true complete=true")
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
	print("END RUN AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
