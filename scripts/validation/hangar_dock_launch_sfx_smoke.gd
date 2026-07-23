extends SceneTree

## Hangar bay dock routes SFX_DOCK_LAND; launch routes SFX_DOOR_OPEN.
## Uses the same emit helpers as live bay dock/launch success paths.
## Marker: HANGAR DOCK LAUNCH SFX PASS dock=true launch=true

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
	var dock_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOCK_LAND))
	playable.play_hangar_dock_sfx_for_validation()
	var dock_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOCK_LAND))
	if dock_after <= dock_before:
		_fail("SFX_DOCK_LAND not routed before=%d after=%d" % [dock_before, dock_after]); return

	mgr.sfx_router.configure({})
	var launch_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOOR_OPEN))
	playable.play_hangar_launch_sfx_for_validation()
	var launch_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_DOOR_OPEN))
	if launch_after <= launch_before:
		_fail("SFX_DOOR_OPEN not routed before=%d after=%d" % [launch_before, launch_after]); return

	print("HANGAR DOCK LAUNCH SFX PASS dock=true launch=true")
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
	print("HANGAR DOCK LAUNCH SFX FAIL: %s" % msg)
	finished = true
	quit(1)
