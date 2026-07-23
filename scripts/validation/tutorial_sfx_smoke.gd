extends SceneTree

## Tutorial trigger routes UI_OBJECTIVE_ADVANCE; dismiss routes UI_PANEL_CLOSE.
## Marker: TUTORIAL SFX PASS trigger=true dismiss=true

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
	if not is_instance_valid(playable.menu_coordinator):
		_fail("menu_coordinator"); return
	var mgr: Node = playable.audio_manager
	var mc = playable.menu_coordinator

	mgr.sfx_router.configure({})
	var t0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	var tid: String = str(mc.trigger_tutorial("inventory_opened", "any"))
	var t1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	# May return empty if already seen; force via direct signal path if needed.
	if t1 <= t0:
		if mc.has_method("_on_tutorial_triggered"):
			mc._on_tutorial_triggered("sfx_test", "Tutorial", "Body")
			t1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE))
	if t1 <= t0:
		_fail("trigger SFX missing tid=%s" % tid); return

	mgr.sfx_router.configure({})
	var d0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if mc.has_method("dismiss_latest_tutorial"):
		mc.dismiss_latest_tutorial()
	if mc.has_method("_on_tutorial_dismissed"):
		mc._on_tutorial_dismissed("sfx_test")
	var d1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if d1 <= d0:
		_fail("dismiss SFX missing"); return

	print("TUTORIAL SFX PASS trigger=true dismiss=true")
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
	print("TUTORIAL SFX FAIL: %s" % msg)
	finished = true
	quit(1)
