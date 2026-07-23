extends SceneTree

## Room discovery SFX works with away_from_start true.
## Marker: DISCOVER ROOM AWAY PASS away=true discover=true sfx=true

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
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	var room: String = "sfx_discover_room_away_%d" % Time.get_ticks_msec()
	playable._emit_objective_training("scan_console", room, "sfx_obj_away")
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if after <= before:
		_fail("discover sfx missing away"); return
	mgr.sfx_router.configure({})
	var b2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	playable._emit_objective_training("scan_console", room, "sfx_obj_away")
	var a2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if a2 != b2:
		_fail("discover SFX re-fired on known room away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("DISCOVER ROOM AWAY PASS away=true discover=true sfx=true")
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
	print("DISCOVER ROOM AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
