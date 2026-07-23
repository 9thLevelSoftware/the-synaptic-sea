extends SceneTree

## MetaEventState due events route META_BEACON_DISTRESS via play_sfx/router.
## Marker: META SCHEDULE ROUTER PASS beacon=true routed=true

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
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	var mgr: Node = playable.audio_manager
	if mgr.meta_event_state == null:
		_fail("meta_event_state"); return
	# Force schedule: beacon at t=0.1 so one tick fires it.
	mgr.meta_event_state.configure({
		"run_seed": 1,
		"initial_elapsed": 0.0,
		"events": [
			{"id": "beacon_distress", "trigger_time": 0.05, "voice_log_id": "", "volume_db": -3.0},
		],
	})
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BEACON_DISTRESS))
	var due: Array = mgr.tick(0.2)
	if due.is_empty():
		_fail("no due meta events"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BEACON_DISTRESS))
	if after <= before:
		_fail("META_BEACON_DISTRESS not routed before=%d after=%d due=%s" % [before, after, str(due)]); return
	print("META SCHEDULE ROUTER PASS beacon=true routed=true")
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
	print("META SCHEDULE ROUTER FAIL: %s" % msg)
	finished = true
	quit(1)
