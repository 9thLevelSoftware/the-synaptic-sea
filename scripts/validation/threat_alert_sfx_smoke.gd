extends SceneTree

## Rising edge into combat engagement routes SFX_COMBAT_THREAT_ALERT once.
## Marker: THREAT ALERT SFX PASS engage=true edge=true

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
	if playable.threat_manager == null:
		_fail("threat_manager"); return
	var mgr: Node = playable.audio_manager
	playable._prev_combat_engaged = false
	playable.threat_manager.combat_engaged = true
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_THREAT_ALERT))
	playable._refresh_audio_state(false, 0.1)
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_THREAT_ALERT))
	if after <= before:
		_fail("alert not routed on engage before=%d after=%d" % [before, after]); return
	# Still engaged — edge must not re-fire (cooldown may also gate; count must stay).
	var mid: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_THREAT_ALERT))
	playable._refresh_audio_state(false, 0.1)
	var final_c: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_THREAT_ALERT))
	if final_c != mid:
		_fail("alert re-fired while still engaged %d->%d" % [mid, final_c]); return
	print("THREAT ALERT SFX PASS engage=true edge=true")
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
	print("THREAT ALERT SFX FAIL: %s" % msg)
	finished = true
	quit(1)
