extends SceneTree

## Travel hop training events plot_course + complete_astrogation emit.
## Marker: TRAVEL TRAINING XP PASS plot=true astrogation=true

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
	playable.emit_training_event("plot_course", "marker_test")
	playable.emit_training_event("complete_astrogation", "marker_test")
	var found_p := false
	var found_a := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "plot_course":
				found_p = true
			if eid == "complete_astrogation":
				found_a = true
	if not found_p or not found_a:
		_fail("plot=%s astro=%s" % [str(found_p), str(found_a)]); return
	print("TRAVEL TRAINING XP PASS plot=true astrogation=true")
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
	print("TRAVEL TRAINING XP FAIL: %s" % msg)
	finished = true
	quit(1)
