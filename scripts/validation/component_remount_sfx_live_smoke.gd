extends SceneTree

## Live timed remount commit stamps mount SFX and routes it through audio_manager.
## Marker: COMPONENT REMOUNT SFX LIVE PASS remount=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 600

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
	match phase:
		"wait": _setup()
		"dismount_tick": _tick_until("after_dismount")
		"after_dismount": _start_remount()
		"remount_tick": _tick_until("done")
		"done": _finish()


func _setup() -> void:
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
	if not playable.try_work_action_interact_for_validation():
		_fail("dismount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("dismount transaction missing"); return
	instance_id = str(playable.work_action_driver.work.get("target_id"))
	item_form = str(playable.component_placement_state.get_entry(instance_id).get("item_form", item_form))
	phase = "dismount_tick"


func _tick_until(next_phase: String) -> void:
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.has_active_ship_work_for_validation():
		if tick_accum > 40.0:
			_fail("timeout %s" % next_phase)
		return
	phase = next_phase
	tick_accum = 0.0


func _start_remount() -> void:
	if playable.inventory_state.get_quantity(item_form) < 1:
		_fail("dismount lot missing"); return
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	playable.audio_manager.sfx_router.configure({})
	sfx_before = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if not playable.try_work_action_interact_for_validation():
		_fail("remount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("remount transaction missing"); return
	if str(playable.work_action_driver.work.get("action_id")) != "mount_component":
		_fail("expected mount"); return
	phase = "remount_tick"


func _finish() -> void:
	if not playable.component_placement_state.is_mounted(instance_id):
		_fail("component not remounted"); return
	var after: int = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if after <= sfx_before:
		_fail("mount sfx not routed before=%d after=%d" % [sfx_before, after]); return
	print("COMPONENT REMOUNT SFX LIVE PASS remount=true sfx=true")
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
	print("COMPONENT REMOUNT SFX LIVE FAIL: %s" % msg)
	finished = true
	quit(1)
