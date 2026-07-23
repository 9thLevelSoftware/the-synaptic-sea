extends SceneTree

## Voice log played emits decode_signal training XP.
## Marker: DECODE SIGNAL XP PASS emit=true catalog=true

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
	if text.find("decode_signal") < 0:
		_fail("catalog"); return
	playable._on_voice_log_played("log_test_001")
	var found := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("event_id", "")) == "decode_signal":
				found = true
				break
	if not found:
		_fail("decode_signal not logged"); return
	print("DECODE SIGNAL XP PASS emit=true catalog=true")
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
	print("DECODE SIGNAL XP FAIL: %s" % msg)
	finished = true
	quit(1)
