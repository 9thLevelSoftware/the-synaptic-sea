extends SceneTree

## First-time room discovery routes UI_OBJECTIVE_ADVANCE with discover_room XP.
## Marker: DISCOVER ROOM SFX PASS discover=true sfx=true

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
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	# Unique room key so first-discovery branch always fires.
	var room: String = "sfx_discover_room_%d" % Time.get_ticks_msec()
	playable._emit_objective_training("scan_console", room, "sfx_obj")
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if after <= before:
		_fail("UI_OBJECTIVE_ADVANCE not routed before=%d after=%d" % [before, after]); return
	# Second discovery of same room must not re-fire.
	mgr.sfx_router.configure({})
	var b2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	playable._emit_objective_training("scan_console", room, "sfx_obj")
	var a2: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if a2 != b2:
		_fail("discover SFX re-fired on known room"); return
	print("DISCOVER ROOM SFX PASS discover=true sfx=true")
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
	print("DISCOVER ROOM SFX FAIL: %s" % msg)
	finished = true
	quit(1)
