extends SceneTree

## META_BIOMATTER_PULSE on web growth and META_REACTOR_HUM on stabilize path.
## Marker: META BIOMATTER REACTOR SFX PASS pulse=true reactor=true

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
	# Biomatter pulse: force web coverage growth path.
	playable._biomatter_pulse_cooldown = 0.0
	var p_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	playable._maybe_emit_biomatter_pulse()
	var p_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	if p_after <= p_before:
		_fail("biomatter pulse not routed"); return
	# Cooldown must suppress immediate re-fire.
	var mid: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE))
	playable._maybe_emit_biomatter_pulse()
	if int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_BIOMATTER_PULSE)) != mid:
		_fail("biomatter pulse ignored cooldown"); return
	# Reactor hum on stabilize objective type path.
	mgr.sfx_router.configure({})
	var r_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
	playable.emit_meta_reactor_hum_for_validation()
	var r_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.META_REACTOR_HUM))
	if r_after <= r_before:
		_fail("reactor hum not routed"); return
	print("META BIOMATTER REACTOR SFX PASS pulse=true reactor=true")
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
	print("META BIOMATTER REACTOR SFX FAIL: %s" % msg)
	finished = true
	quit(1)
