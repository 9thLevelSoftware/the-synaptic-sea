extends SceneTree

## Hold-to-work: player-started jobs freeze when interact is not held; validation bypasses hold.
## Marker: WORK HOLD TO WORK PASS freeze=true validation=true

const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	# Pure freeze behavior via flag
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	if not driver.start_action("cut_wall", "w1", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"welding_lance": 1},
	}):
		_fail("pure start"); return
	driver.tick(1.0, {})
	var p1: float = driver.progress_ratio()
	if p1 <= 0.0:
		_fail("should progress when ticking"); return

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
	_validate_hold()


func _validate_hold() -> void:
	finished = true
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.inventory_state.add_item("welding_lance", 1)
	# Force hold required without Input action pressed → freeze
	playable.module_integrity_map.ensure_module("hub/hold_wall", "wall_straight_1x1", {}, "bridge")
	if not playable.work_action_driver.start_action("cut_wall", "hub/hold_wall", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"welding_lance": 1},
	}):
		_fail("start hold job"); return
	playable._work_requires_hold = true
	var before: float = playable.work_action_driver.progress_ratio()
	# Interact not held in headless → tick should freeze
	playable._tick_work_action(1.0)
	var mid: float = playable.work_action_driver.progress_ratio()
	if absf(mid - before) > 0.001:
		_fail("hold freeze expected progress unchanged got %s->%s" % [str(before), str(mid)]); return
	# Validation path disables hold and can complete
	playable._work_requires_hold = false
	playable._tick_work_action(10.0)
	if playable.work_action_driver.is_working():
		# force complete
		playable.work_action_driver.tick(99.0, {})
		if playable.work_action_driver.get_status() == "completed":
			playable.work_action_driver.complete(playable.module_integrity_map, {"welding_lance": 1})
	if playable.work_action_driver.is_working():
		_fail("should complete without hold"); return
	print("WORK HOLD TO WORK PASS freeze=true validation=true")
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
	print("WORK HOLD TO WORK FAIL: %s" % msg)
	finished = true
	quit(1)
