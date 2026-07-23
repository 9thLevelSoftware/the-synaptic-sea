extends SceneTree

## Social suite training events are catalogued and emit cleanly.
## Marker: SOCIAL TRAINING XP PASS inspire=true negotiate=true intimidate=true

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
		_fail("bus"); return
	var text: String = FileAccess.get_file_as_string("res://data/player/training_actions.json")
	for eid in ["inspire_crew", "negotiate_truce", "intimidate_threat", "transmit_relay"]:
		if text.find(eid) < 0:
			_fail("catalog missing %s" % eid); return
		playable.emit_training_event(eid, "test_target")
	var found: Dictionary = {}
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) == TYPE_DICTIONARY:
				found[str((entry as Dictionary).get("event_id", ""))] = true
	for eid2 in ["inspire_crew", "negotiate_truce", "intimidate_threat", "transmit_relay"]:
		if not found.has(eid2):
			_fail("not logged %s" % eid2); return
	print("SOCIAL TRAINING XP PASS inspire=true negotiate=true intimidate=true")
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
	print("SOCIAL TRAINING XP FAIL: %s" % msg)
	finished = true
	quit(1)
