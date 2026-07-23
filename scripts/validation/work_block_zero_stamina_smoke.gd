extends SceneTree

## Zero stamina blocks starting a new WorkAction via interact path.
## Marker: WORK BLOCK ZERO STAMINA PASS block=true start_ok=true

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
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.module_integrity_map.ensure_module("eng/wall_a", "wall")
	if playable.inventory_state.get_quantity("welding_lance") < 1:
		playable.inventory_state.add_item("welding_lance", 1)
	playable.vitals_state.stamina = 0.0
	if playable.try_work_action_interact_for_validation():
		_fail("should block interact start at zero stamina"); return
	if playable.work_action_driver.is_working():
		_fail("should not be working"); return
	# Recover stamina and allow start via driver (interact may still need range).
	playable.vitals_state.stamina = 80.0
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 5,
		"inventory": playable._inventory_qty_dict_for_work(),
	}
	if not playable.work_action_driver.start_action("cut_wall", "eng/wall_a", ctx):
		_fail("start with stamina should work"); return
	print("WORK BLOCK ZERO STAMINA PASS block=true start_ok=true")
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
	print("WORK BLOCK ZERO STAMINA FAIL: %s" % msg)
	finished = true
	quit(1)
