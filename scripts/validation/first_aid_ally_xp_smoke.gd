extends SceneTree

## Medbay surgery emits first_aid_ally (patient-care stand-in) + perform_surgery.
## Marker: FIRST AID ALLY XP PASS ally=true surgery=true

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
	if playable.vitals_state == null or playable.inventory_state == null:
		_fail("vitals/inventory"); return
	# Force critical health + gauze so surgery can fire.
	playable.vitals_state.health = 20.0
	playable.inventory_state.add_item("medical_gauze", 2)
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("bus"); return
	if bus.has_method("clear_log"):
		bus.clear_log()
	var ok: bool = bool(playable.try_medbay_surgery(playable.player))
	if not ok:
		_fail("try_medbay_surgery returned false"); return
	var ally: bool = false
	var surgery: bool = false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "first_aid_ally":
				ally = true
			elif eid == "perform_surgery":
				surgery = true
	if not ally:
		_fail("first_aid_ally not logged"); return
	if not surgery:
		_fail("perform_surgery not logged"); return
	print("FIRST AID ALLY XP PASS ally=true surgery=true")
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
	print("FIRST AID ALLY XP FAIL: %s" % msg)
	finished = true
	quit(1)
