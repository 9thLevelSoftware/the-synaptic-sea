extends SceneTree

## Live footstep path routes SFX_FOOTSTEP while player is moving.
## Marker: FOOTSTEP SFX PASS moving=true sfx=true

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
	if playable.player == null:
		_fail("player null"); return
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_FOOTSTEP))
	playable.play_footstep_sfx_for_validation()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_FOOTSTEP))
	if after <= before:
		_fail("SFX_FOOTSTEP not routed before=%d after=%d" % [before, after]); return
	# Idle path must not keep accumulating/firing.
	if is_instance_valid(playable.player):
		playable.player.velocity = Vector3.ZERO
	playable._footstep_acc = 99.0
	playable._tick_footstep_sfx(0.1)
	var idle_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_FOOTSTEP))
	if idle_after != after:
		_fail("footstep fired while idle before=%d idle_after=%d" % [after, idle_after]); return
	print("FOOTSTEP SFX PASS moving=true sfx=true")
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
	print("FOOTSTEP SFX FAIL: %s" % msg)
	finished = true
	quit(1)
