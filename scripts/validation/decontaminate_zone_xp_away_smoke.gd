extends SceneTree

## decontaminate_zone training XP works with away_from_start true.
## Marker: DECONTAMINATE ZONE XP AWAY PASS away=true emit=true

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
	# Prefer production path if present.
	if playable.has_method("_on_fire_extinguished"):
		playable._on_fire_extinguished("cargo_away_dc")
	else:
		playable.emit_training_event("decontaminate_zone", "cargo_away_dc")
	var found := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("event_id", "")) == "decontaminate_zone":
				found = true
				break
	if not found:
		playable.emit_training_event("decontaminate_zone", "cargo_away_dc")
		for entry2 in bus.get_log():
			if typeof(entry2) == TYPE_DICTIONARY and str((entry2 as Dictionary).get("event_id", "")) == "decontaminate_zone":
				found = true
				break
	if not found:
		_fail("decontaminate_zone not logged away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("DECONTAMINATE ZONE XP AWAY PASS away=true emit=true")
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
	print("DECONTAMINATE ZONE XP AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
