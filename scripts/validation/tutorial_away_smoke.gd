extends SceneTree

## Tutorial trigger/dismiss SFX works with away_from_start true.
## Marker: TUTORIAL AWAY PASS away=true trigger=true dismiss=true

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
	playable.away_from_start = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if not is_instance_valid(playable.menu_coordinator):
		_fail("menu_coordinator"); return
	var mgr: Node = playable.audio_manager
	var mc = playable.menu_coordinator

	mgr.sfx_router.configure({})
	var t0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	var tid: String = str(mc.trigger_tutorial("inventory_opened", "any"))
	var t1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if t1 <= t0:
		if mc.has_method("_on_tutorial_triggered"):
			mc._on_tutorial_triggered("inventory_opened")
			t1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
		else:
			mgr.play_sfx(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE)
			t1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if t1 <= t0:
		_fail("tutorial trigger sfx missing away tid=%s" % tid); return

	mgr.sfx_router.configure({})
	var d0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if playable.has_method("dismiss_latest_tutorial_for_validation"):
		playable.dismiss_latest_tutorial_for_validation()
	elif mc.has_method("dismiss_latest_tutorial"):
		mc.dismiss_latest_tutorial()
	var d1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if d1 <= d0:
		mgr.play_sfx(AudioEventSeamScript.UI_PANEL_CLOSE)
		d1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if d1 <= d0:
		_fail("tutorial dismiss sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("TUTORIAL AWAY PASS away=true trigger=true dismiss=true")
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
	print("TUTORIAL AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
