extends SceneTree

## Live timed dismount commit stamps unbolt SFX and routes it through audio_manager.
## Marker: COMPONENT MOUNT SFX LIVE AWAY PASS away=true dismount=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 500

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""
var item_form: String = ""
var sfx_before: int = 0


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
	if phase == "wait":
		_setup()
	elif phase == "dismount_tick":
		_tick()


func _setup() -> void:
	playable.away_from_start = true
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	var fixture: Dictionary = playable.prepare_p12_component_work_fixture_for_validation()
	if not bool(fixture.get("ok", false)):
		_fail("fixture: %s" % str(fixture.get("reason", ""))); return
	instance_id = str(fixture.get("instance_id", ""))
	item_form = str(fixture.get("item_form", ""))
	var panel = playable.get_ship_modification_panel_for_validation()
	if panel != null and panel.is_open():
		panel.close()
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	playable.audio_manager.sfx_router.configure({})
	sfx_before = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_UNBOLT))
	if not playable.try_work_action_interact_for_validation():
		_fail("dismount start"); return
	if not playable.has_active_ship_work_for_validation():
		_fail("dismount transaction missing"); return
	phase = "dismount_tick"


func _tick() -> void:
	playable.away_from_start = true
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.has_active_ship_work_for_validation():
		if tick_accum > 40.0:
			_fail("timeout")
		return
	var after: int = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_UNBOLT))
	if after <= sfx_before:
		_fail("unbolt sfx not routed before=%d after=%d" % [sfx_before, after]); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("COMPONENT MOUNT SFX LIVE AWAY PASS away=true dismount=true sfx=true")
	finished = true
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
	print("COMPONENT MOUNT SFX LIVE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
