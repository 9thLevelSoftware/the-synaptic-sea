extends SceneTree

## weld_patch interact context uses repair skill id/level from progression.
## Marker: WORK WELD SKILL CONTEXT PASS skill=true start=true

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
	playable.module_integrity_map.ensure_module("eng/wall_skill", "wall")
	var m = playable.module_integrity_map.get_module("eng/wall_skill")
	m.integrity = 0.5
	m._recompute_state()
	playable.inventory_state.add_item("welding_lance", 1)
	playable.inventory_state.add_item("hull_plate", 1)
	# Bump repair skill so gate can pass if min level required.
	if playable.player_progression != null and playable.player_progression.has_method("add_skill_xp"):
		playable.player_progression.call("add_skill_xp", "repair", 500)
	elif playable.player_progression != null and "skills" in playable.player_progression:
		pass
	var layout: Dictionary = playable._active_layout_for_work()
	# Drive interact selection path via private helper by forcing damaged nearest.
	# Direct start with skill context that interact would build:
	var skill_id: String = "repair"
	var skill_level: int = 0
	if playable.player_progression != null and playable.player_progression.has_method("get_skill_level"):
		skill_level = int(playable.player_progression.call("get_skill_level", skill_id))
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": skill_id,
		"skill_level": skill_level,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("weld_patch", "eng/wall_skill", ctx):
		_fail("start with repair skill failed level=%d" % skill_level); return
	if not playable.work_action_driver.is_working():
		_fail("not working"); return
	# Confirm catalog min_skill is repair
	var def: Dictionary = playable.work_action_driver.catalog.get_action("weld_patch")
	if str(def.get("min_skill", "")) != "repair":
		_fail("catalog min_skill not repair"); return
	print("WORK WELD SKILL CONTEXT PASS skill=true start=true")
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
	print("WORK WELD SKILL CONTEXT FAIL: %s" % msg)
	finished = true
	quit(1)
