extends SceneTree

## Live timed dismount + remount transactions emit salvage/repair training XP.
## Marker: COMPONENT MOUNT XP LIVE AWAY PASS away=true dismount=true remount=true xp=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 500

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""
var item_form: String = ""
var saw_salvage: bool = false
var saw_repair: bool = false


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
		"dismount_tick": _tick_until_idle("after_dismount")
		"after_dismount":
			_scan_xp()
			_start_remount()
		"remount_tick": _tick_until_idle("done")
		"done": _finish()


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
	if not playable.try_work_action_interact_for_validation():
		_fail("dismount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("dismount transaction missing"); return
	instance_id = str(playable.work_action_driver.work.get("target_id"))
	item_form = str(playable.component_placement_state.get_entry(instance_id).get("item_form", item_form))
	phase = "dismount_tick"


func _tick_until_idle(next_phase: String) -> void:
	playable.away_from_start = true
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.has_active_ship_work_for_validation():
		if tick_accum > 40.0:
			_fail("timeout %s" % next_phase)
		return
	phase = next_phase
	tick_accum = 0.0


func _scan_xp() -> void:
	var bus = playable.get_training_event_bus()
	if bus != null and bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			saw_salvage = saw_salvage or eid == "salvage"
			saw_repair = saw_repair or eid == "repair"


func _start_remount() -> void:
	if playable.component_placement_state.is_mounted(instance_id):
		_fail("should be stripped"); return
	if playable.inventory_state.get_quantity(item_form) < 1:
		_fail("dismount lot missing"); return
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	if not playable.try_work_action_interact_for_validation():
		_fail("remount start"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("remount transaction missing"); return
	if str(playable.work_action_driver.work.get("action_id")) != "mount_component":
		_fail("expected mount_component"); return
	phase = "remount_tick"


func _finish() -> void:
	_scan_xp()
	if not saw_salvage:
		_fail("dismount salvage xp missing"); return
	if not saw_repair:
		_fail("remount repair xp missing"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("COMPONENT MOUNT XP LIVE AWAY PASS away=true dismount=true remount=true xp=true")
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
	print("COMPONENT MOUNT XP LIVE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
