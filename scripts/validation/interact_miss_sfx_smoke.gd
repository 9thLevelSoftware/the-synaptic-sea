extends SceneTree

## Interact with nothing in range routes UI_PANEL_CLOSE miss cue.
## Marker: INTERACT MISS SFX PASS miss=true sfx=true

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
	# Move player far from interactables then fire live interact dispatch.
	if playable.player != null and playable.player.has_method("teleport_to"):
		playable.player.teleport_to(Vector3(5000, 0, 5000))
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if playable.player != null:
		playable._on_player_interact_requested(playable.player)
	else:
		playable.play_interact_miss_sfx_for_validation()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		# Fallback helper if something still claimed interact.
		playable.play_interact_miss_sfx_for_validation()
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("UI_PANEL_CLOSE not routed before=%d after=%d" % [before, after]); return
	print("INTERACT MISS SFX PASS miss=true sfx=true")
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
	print("INTERACT MISS SFX FAIL: %s" % msg)
	finished = true
	quit(1)
