extends SceneTree

## Hold-to-work drains stamina while ticking a live WorkAction.
## Marker: WORK STAMINA DRAIN PASS start=true drain=true speed=true

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
	if playable.vitals_state == null or playable.work_action_driver == null:
		_fail("missing models"); return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.vitals_state.stamina = 100.0
	var before: float = float(playable.vitals_state.stamina)
	playable._work_requires_hold = false
	if playable.module_integrity_map == null:
		_fail("no integrity map"); return
	playable.module_integrity_map.ensure_module("eng/wall_a", "wall")
	if playable.inventory_state.get_quantity("welding_lance") < 1:
		playable.inventory_state.add_item("welding_lance", 1)
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 5,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("cut_wall", "eng/wall_a", ctx):
		_fail("start_action cut_wall failed"); return
	if not playable.work_action_driver.is_working():
		_fail("not working after start"); return
	playable._tick_work_action(1.0)
	var after: float = float(playable.vitals_state.stamina)
	if after >= before:
		_fail("expected stamina drain before=%s after=%s" % [str(before), str(after)]); return
	if after > before - 4.0:
		_fail("expected ~8 stamina/s drain got delta=%s" % str(before - after)); return
	print("WORK STAMINA DRAIN PASS start=true drain=true speed=true")
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
	print("WORK STAMINA DRAIN FAIL: %s" % msg)
	finished = true
	quit(1)
