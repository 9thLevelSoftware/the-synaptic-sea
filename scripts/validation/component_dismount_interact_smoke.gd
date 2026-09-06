extends SceneTree

## PKG-B2.3b: wrench interact starts a timed dismount and commits its exact returned lot.
## Marker: COMPONENT DISMOUNT INTERACT PASS start=true tick=true stripped=true yield=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""
var item_form: String = ""


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
		_start()
	elif phase == "tick":
		_tick()


func _start() -> void:
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
	var before_qty: int = playable.inventory_state.get_quantity(item_form)
	if not playable.try_work_action_interact_for_validation():
		_fail("interact start failed"); return
	if not playable.has_active_ship_work_for_validation() or playable.work_action_driver.work == null:
		_fail("not working"); return
	if not playable.component_placement_state.is_mounted(instance_id):
		_fail("dismount mutated before timed commit"); return
	var aid: String = str(playable.work_action_driver.work.get("action_id"))
	if aid != "dismount_component" and aid != "unbolt_component":
		_fail("expected dismount action got %s" % aid); return
	instance_id = str(playable.work_action_driver.work.get("target_id"))
	set_meta("before_qty", before_qty)
	phase = "tick"


func _tick() -> void:
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.has_active_ship_work_for_validation():
		if tick_accum > 40.0:
			_fail("timeout")
		return
	if playable.component_placement_state.is_mounted(instance_id):
		_fail("still mounted after complete id=%s" % instance_id); return
	if playable.inventory_state.get_quantity(item_form) <= int(get_meta("before_qty", 0)):
		_fail("exact dismount yield missing"); return
	print("COMPONENT DISMOUNT INTERACT PASS start=true tick=true stripped=true yield=true")
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
	print("COMPONENT DISMOUNT INTERACT FAIL: %s" % msg)
	finished = true
	quit(1)
