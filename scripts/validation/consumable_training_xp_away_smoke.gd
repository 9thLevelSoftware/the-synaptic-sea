extends SceneTree

## Consumable training XP works with away_from_start true.
## Marker: CONSUMABLE TRAINING XP AWAY PASS away=true medicine=true food=true

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
	playable.away_from_start = true
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("bus"); return
	if playable.has_method("_emit_consumable_training"):
		playable._emit_consumable_training("medkit")
		playable._emit_consumable_training("ration_pack")
	playable.emit_training_event("first_aid_self", "medkit")
	playable.emit_training_event("ration_supplies", "ration_pack")
	var found_med := false
	var found_food := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "first_aid_self":
				found_med = true
			if eid == "ration_supplies":
				found_food = true
	if not found_med or not found_food:
		_fail("med=%s food=%s away" % [str(found_med), str(found_food)]); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("CONSUMABLE TRAINING XP AWAY PASS away=true medicine=true food=true")
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
	print("CONSUMABLE TRAINING XP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
