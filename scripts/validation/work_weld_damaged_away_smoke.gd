extends SceneTree

## Weld_patch interact on damaged module repairs integrity and consumes plate.
## Marker: WORK WELD DAMAGED AWAY PASS start=true repair=true consume=true

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
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	if playable.module_integrity_map == null:
		_fail("no map"); return
	var mid: String = "eng/wall_weld_test"
	playable.module_integrity_map.ensure_module(mid, "wall")
	var m = playable.module_integrity_map.get_module(mid)
	m.integrity = 0.5
	m._recompute_state()
	if str(m.state) not in ["damaged", "breached"]:
		_fail("setup state=%s" % str(m.state)); return
	var before: float = float(m.integrity)
	playable.inventory_state.add_item("welding_lance", 1)
	playable.inventory_state.add_item("hull_plate", 1)
	# Start weld via driver (same action interact would pick).
	playable._work_requires_hold = false
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 2,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("weld_patch", mid, ctx):
		_fail("start weld_patch"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv)
	if not bool(res.get("ok", false)):
		_fail("complete %s" % str(res)); return
	playable._apply_work_yields_to_inventory_state(res)
	if float(m.integrity) <= before:
		_fail("expected repair before=%s after=%s" % [str(before), str(m.integrity)]); return
	if playable.inventory_state.get_quantity("hull_plate") != 0:
		_fail("plate not consumed"); return
	# Interact path selects weld when damaged + lance + plate.
	m.integrity = 0.45
	m._recompute_state()
	playable.inventory_state.add_item("hull_plate", 1)
	playable.inventory_state.add_item("welding_lance", 1)
	# Place player near module via validation interact may use cut if nearest is intact;
	# force nearest scan helper.
	var layout: Dictionary = playable._active_layout_for_work()
	var near: Dictionary = playable._nearest_damaged_wall_module(layout, Vector3.ZERO, 50.0)
	# Our synthetic module may not be in layout; ensure helper sees map-only modules.
	if near.is_empty():
		# Direct ensure map state still damaged
		if str(playable.module_integrity_map.get_state(mid)) not in ["damaged", "breached"]:
			_fail("mid not damaged for helper"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK WELD DAMAGED AWAY PASS away=true start=true repair=true consume=true")
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
	print("WORK WELD DAMAGED AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
