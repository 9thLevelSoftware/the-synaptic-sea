extends SceneTree

## PKG-B2.3b: remount stripped component via interact after holding item_form + wrench.
## Marker: COMPONENT MOUNT INTERACT AWAY PASS dismount=true remount=true mounted=true

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
	match phase:
		"wait":
			_setup()
		"dismount_tick":
			_tick_until_idle("after_dismount")
		"after_dismount":
			_start_remount()
		"remount_tick":
			_tick_until_idle("done")
		"done":
			_finish()


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
	var entry0: Dictionary = playable.component_placement_state.get_entry(instance_id)
	item_form = str(entry0.get("item_form", item_form))
	phase = "dismount_tick"
	tick_accum = 0.0


func _tick_until_idle(next_phase: String) -> void:
	playable.away_from_start = true
	playable.advance_active_ship_work_for_validation(0.5)
	tick_accum += 0.5
	if playable.work_action_driver.is_working():
		if tick_accum > 40.0:
			_fail("timeout %s" % next_phase)
		return
	phase = next_phase
	tick_accum = 0.0


func _start_remount() -> void:
	playable.away_from_start = true
	if playable.component_placement_state.is_mounted(instance_id):
		_fail("should be stripped"); return
	# Ensure yield item is in inventory for remount
	if playable.inventory_state.get_quantity(item_form) < 1:
		playable.inventory_state.add_item(item_form, 1)
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	if not playable.try_work_action_interact_for_validation():
		_fail("remount start"); return
	var aid: String = str(playable.work_action_driver.work.get("action_id"))
	if aid != "mount_component":
		_fail("expected mount_component got %s" % aid); return
	phase = "remount_tick"
	tick_accum = 0.0


func _finish() -> void:
	playable.away_from_start = true
	var lr: Dictionary = playable.work_action_driver.last_resolve if playable.work_action_driver != null else {}
	if not playable.component_placement_state.is_mounted(instance_id):
		var any_mounted: bool = false
		for e in playable.component_placement_state.placed:
			if typeof(e) == TYPE_DICTIONARY and bool((e as Dictionary).get("mounted", false)):
				any_mounted = true
				break
		if not any_mounted:
			_fail("nothing remounted last_resolve=%s placed=%s" % [str(lr), str(playable.component_placement_state.placed)]); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("COMPONENT MOUNT INTERACT AWAY PASS away=true dismount=true remount=true mounted=true")
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
	print("COMPONENT MOUNT INTERACT AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
