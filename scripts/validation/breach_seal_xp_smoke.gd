extends SceneTree

## Breach seal emits weld_panel + build_shelter training XP.
## Marker: BREACH SEAL XP PASS weld=true shelter=true

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
	playable._on_breach_sealed("cargo_01")
	var found_w := false
	var found_s := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "weld_panel":
				found_w = true
			if eid == "build_shelter":
				found_s = true
	if not found_w or not found_s:
		_fail("weld=%s shelter=%s" % [str(found_w), str(found_s)]); return
	print("BREACH SEAL XP PASS weld=true shelter=true")
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
	print("BREACH SEAL XP FAIL: %s" % msg)
	finished = true
	quit(1)
