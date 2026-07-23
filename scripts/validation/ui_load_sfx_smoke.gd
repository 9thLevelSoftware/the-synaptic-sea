extends SceneTree

## request_load after a successful save routes UI_LOAD.
## Marker: UI LOAD SFX PASS save=true load=true

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
	var saved: bool = bool(playable.request_save())
	if not saved:
		_fail("request_save failed"); return
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_LOAD))
	var loaded: bool = bool(playable.request_load())
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_LOAD))
	if not loaded:
		_fail("request_load failed"); return
	if after <= before:
		_fail("UI_LOAD not routed before=%d after=%d" % [before, after]); return
	print("UI LOAD SFX PASS save=true load=true")
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
	print("UI LOAD SFX FAIL: %s" % msg)
	finished = true
	quit(1)
