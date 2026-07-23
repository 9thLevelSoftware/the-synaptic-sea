extends SceneTree

## Quicksave cooldown refuse routes UI_PANEL_CLOSE; successful quicksave routes UI_SAVE.
## Marker: QUICKSAVE DENIED SFX PASS deny=true save=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 300

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

	# Success first.
	mgr.sfx_router.configure({})
	var s0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_SAVE))
	var ok: bool = bool(playable.request_quicksave())
	var s1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_SAVE))
	if not ok:
		_fail("first quicksave failed"); return
	if s1 <= s0:
		_fail("UI_SAVE not routed"); return

	# Immediate second request should hit cooldown deny.
	mgr.sfx_router.configure({})
	var d0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var denied: bool = not bool(playable.request_quicksave())
	var d1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if not denied:
		_fail("second quicksave should be cooldown-denied"); return
	if d1 <= d0:
		_fail("deny SFX missing"); return

	print("QUICKSAVE DENIED SFX PASS deny=true save=true")
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
	print("QUICKSAVE DENIED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
