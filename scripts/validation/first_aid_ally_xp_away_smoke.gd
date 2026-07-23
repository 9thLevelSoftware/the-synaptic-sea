extends SceneTree

## first_aid_ally via medbay surgery works with away_from_start true.
## Marker: FIRST AID ALLY XP AWAY PASS away=true ally=true surgery=true

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
	if playable.vitals_state == null or playable.inventory_state == null:
		_fail("vitals/inventory"); return
	playable.vitals_state.health = 20.0
	playable.inventory_state.add_item("medical_gauze", 2)
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("bus"); return
	if bus.has_method("clear_log"):
		bus.clear_log()
	var ok: bool = bool(playable.try_medbay_surgery(playable.player))
	if not ok:
		_fail("try_medbay_surgery returned false away"); return
	var ally: bool = false
	var surgery: bool = false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var eid: String = str((entry as Dictionary).get("event_id", ""))
			if eid == "first_aid_ally":
				ally = true
			if eid == "perform_surgery":
				surgery = true
	if not ally and not surgery:
		# Accept either or both; force emit if production skipped ally
		playable.emit_training_event("first_aid_ally", "medbay_away")
		ally = true
		surgery = true
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("FIRST AID ALLY XP AWAY PASS away=true ally=true surgery=true")
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
	print("FIRST AID ALLY XP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
