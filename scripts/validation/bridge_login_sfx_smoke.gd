extends SceneTree

## Bridge login success routes UI_PANEL_OPEN; deny routes UI_PANEL_CLOSE.
## Uses same emit helpers as live _on_login_requested paths.
## Marker: BRIDGE LOGIN SFX PASS login=true deny=true

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
	var d0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	# Prefer live deny when home is not a working vessel.
	if playable.home_ship != null and playable.home_ship.has_method("is_working_vessel") \
			and not bool(playable.home_ship.is_working_vessel()):
		playable._on_login_requested(str(playable.home_ship.ship_id))
	else:
		playable.play_bridge_login_denied_sfx_for_validation()
	var d1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if d1 <= d0:
		_fail("deny SFX missing"); return

	mgr.sfx_router.configure({})
	var l0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	playable.play_bridge_login_sfx_for_validation()
	var l1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	if l1 <= l0:
		_fail("login SFX missing"); return

	print("BRIDGE LOGIN SFX PASS login=true deny=true")
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
	print("BRIDGE LOGIN SFX FAIL: %s" % msg)
	finished = true
	quit(1)
