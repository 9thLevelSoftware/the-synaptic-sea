extends SceneTree

## Repair / extinguish / seal blocked routes UI_PANEL_CLOSE deny cue.
## Marker: HAZARD BLOCKED SFX PASS repair=true extinguish=true seal=true

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
	var r0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	playable._on_repair_blocked("power", "main_board", "missing_parts")
	var r1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if r1 <= r0:
		_fail("repair blocked SFX missing"); return
	mgr.sfx_router.configure({})
	var e0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	playable._on_extinguish_blocked("cargo", "missing_extinguisher")
	var e1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if e1 <= e0:
		_fail("extinguish blocked SFX missing"); return
	mgr.sfx_router.configure({})
	var s0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	playable._on_seal_blocked("cargo", "missing_sealant")
	var s1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if s1 <= s0:
		_fail("seal blocked SFX missing"); return
	print("HAZARD BLOCKED SFX PASS repair=true extinguish=true seal=true")
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
	print("HAZARD BLOCKED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
