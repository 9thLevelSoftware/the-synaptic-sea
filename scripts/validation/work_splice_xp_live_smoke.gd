extends SceneTree

## Completing splice_conduit emits repair training XP.
## Marker: WORK SPLICE XP LIVE PASS start=true complete=true xp=true

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
	playable.module_integrity_map.ensure_module("eng/conduit_splice", "wall")
	if playable.inventory_state.get_quantity("multitool") < 1:
		playable.inventory_state.add_item("multitool", 1)
	if playable.inventory_state.get_quantity("wire_spool") < 1:
		playable.inventory_state.add_item("wire_spool", 1)
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	var res: Dictionary = playable.run_work_action_for_validation(
		"splice_conduit", "eng/conduit_splice", playable._inventory_qty_dict_for_work()
	)
	if not bool(res.get("ok", false)):
		_fail("complete %s" % str(res)); return
	var found := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid in ["repair", "repair_subcomponent"]:
				found = true
				break
	if not found:
		_fail("repair xp not logged"); return
	print("WORK SPLICE XP LIVE PASS start=true complete=true xp=true")
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
	print("WORK SPLICE XP LIVE FAIL: %s" % msg)
	finished = true
	quit(1)
