extends SceneTree

## discover_room / extract_data training events emit cleanly.
## Marker: DISCOVER ROOM XP PASS discover=true extract=true

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
	playable.emit_training_event("discover_room", "ship_start|eng")
	playable.emit_training_event("extract_data", "download_logs")
	var found_d := false
	var found_e := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "discover_room":
				found_d = true
			if eid == "extract_data":
				found_e = true
	if not found_d or not found_e:
		_fail("discover=%s extract=%s" % [str(found_d), str(found_e)]); return
	print("DISCOVER ROOM XP PASS discover=true extract=true")
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
	print("DISCOVER ROOM XP FAIL: %s" % msg)
	finished = true
	quit(1)
