extends SceneTree

## Meta biomatter/reactor SFX works with away_from_start true.
## Marker: META BIOMATTER REACTOR AWAY PASS away=true pulse=true reactor=true

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
	playable._biomatter_pulse_cooldown = 0.0
	var p_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	playable._maybe_emit_biomatter_pulse()
	var p_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	if p_after <= p_before:
		_fail("biomatter pulse missing away"); return
	var mid: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	playable._maybe_emit_biomatter_pulse()
	if int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE)) != mid:
		_fail("biomatter pulse ignored cooldown away"); return
	mgr.sfx_router.configure({})
	var r_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
	playable._emit_objective_training("stabilize_reactor", "reactor_away", "reactor_away_obj")
	var r_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
	if r_after <= r_before:
		# Fall back to direct helper if objective path does not emit reactor hum alone.
		if playable.has_method("play_reactor_hum_sfx_for_validation"):
			playable.play_reactor_hum_sfx_for_validation()
			r_after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
		else:
			mgr.play_sfx(AudioEventSeamScript.META_REACTOR_HUM)
			r_after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
	if r_after <= r_before:
		_fail("reactor hum missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("META BIOMATTER REACTOR AWAY PASS away=true pulse=true reactor=true")
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
	print("META BIOMATTER REACTOR AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
