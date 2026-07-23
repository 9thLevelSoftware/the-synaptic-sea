extends SceneTree

## Bandage/treat emit first_aid training events via TrainingEventBus.
## Marker: BANDAGE TRAINING PASS bandage_xp=true treat_xp=true catalog=true

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
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("training bus"); return
	# Catalog must know bandage_wound
	var has_band := false
	var has_treat := false
	if bus.has_method("get_action") or true:
		# Peek training_actions data
		var text: String = FileAccess.get_file_as_string("res://data/player/training_actions.json")
		has_band = text.find("bandage_wound") >= 0
		has_treat = text.find("treat_wound") >= 0
	if not has_band or not has_treat:
		_fail("catalog missing events"); return

	var log_before: int = 0
	if bus.has_method("get_log"):
		log_before = bus.get_log().size()

	playable.wound_state.apply_wound({
		"kind": "laceration", "body_part": "arm", "severity": 0.5,
	})
	playable.inventory_state.add_item("bandage_kit", 1)
	var res: Dictionary = playable.bandage_wound_with_inventory_for_validation()
	if not bool(res.get("ok", false)):
		_fail("bandage %s" % str(res)); return

	var found_band := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("event_id", "")) == "bandage_wound":
				found_band = true
				break
	if not found_band:
		_fail("bandage_wound not in training log"); return

	playable.wound_state.apply_wound({
		"kind": "puncture", "body_part": "leg", "severity": 0.4,
	})
	playable.inventory_state.add_item("medkit", 1)
	if not playable.open_wounds_panel_for_validation():
		_fail("panel"); return
	# Select newest wound if possible
	playable.wounds_panel.move_selection(1)
	if not playable._try_treat_selected_wound():
		_fail("treat"); return
	var found_treat := false
	for entry2 in bus.get_log():
		if typeof(entry2) == TYPE_DICTIONARY and str((entry2 as Dictionary).get("event_id", "")) == "treat_wound":
			found_treat = true
			break
	if not found_treat:
		_fail("treat_wound not in training log"); return

	print("BANDAGE TRAINING PASS bandage_xp=true treat_xp=true catalog=true")
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
	print("BANDAGE TRAINING FAIL: %s" % msg)
	finished = true
	quit(1)
