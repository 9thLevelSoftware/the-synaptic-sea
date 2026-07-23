extends SceneTree

## Sealed hatch bypass routes SFX_DOOR_OPEN (live door-open call site).
## Marker: HATCH DOOR OPEN SFX PASS hatch=true sfx=true

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
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOOR_OPEN))
	playable._on_hatch_bypassed("sfx_hatch_test", "mechanical")
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOOR_OPEN))
	if after <= before:
		_fail("SFX_DOOR_OPEN not routed before=%d after=%d" % [before, after]); return
	print("HATCH DOOR OPEN SFX PASS hatch=true sfx=true")
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
	print("HATCH DOOR OPEN SFX FAIL: %s" % msg)
	finished = true
	quit(1)
