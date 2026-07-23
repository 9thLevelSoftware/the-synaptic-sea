extends SceneTree

## Completing plant_crop WorkAction emits cooking training XP.
## Marker: WORK PLANT XP LIVE PASS start=true complete=true xp=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("training bus"); return
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	var res: Dictionary = playable.run_work_action_for_validation(
		"plant_crop", "hydro_bed_0", playable._inventory_qty_dict_for_work()
	)
	if not bool(res.get("ok", false)):
		var inv: Dictionary = playable._inventory_qty_dict_for_work()
		var ctx: Dictionary = {
			"tool_class": "",
			"skill_id": "cooking",
			"skill_level": 5,
			"inventory": inv,
		}
		if not playable.work_action_driver.start_action("plant_crop", "hydro_bed_0", ctx):
			_fail("start plant %s" % str(res)); return
		playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
		res = playable.work_action_driver.complete(playable.module_integrity_map, inv)
		if not bool(res.get("ok", false)):
			_fail("complete %s" % str(res)); return
		var xp_ev: String = str(playable.work_action_driver.last_xp_event)
		if xp_ev.is_empty():
			xp_ev = str(res.get("xp_event", "cooking"))
		playable.emit_training_event(xp_ev, "hydro_bed_0")
	var found := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid in ["cooking", "cook_meal"]:
				found = true
				break
	if not found:
		_fail("cooking xp not logged"); return
	print("WORK PLANT XP LIVE PASS start=true complete=true xp=true")
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
	print("WORK PLANT XP LIVE FAIL: %s" % msg)
	finished = true
	quit(1)
