extends SceneTree

## Structure cut destroys/damages module integrity and leaves non-pristine sparse delta.
## Marker: CUT MODULE SCENE AWAY PASS cut=true damaged=true sparse=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")

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
	playable.inventory_state.add_item("welding_lance", 1)
	var mid: String = "hub/cut_scene_wall"
	playable.module_integrity_map.ensure_module(mid, "wall_straight_1x1", {"scrap_metal": 2}, "bridge")
	var before: String = playable.module_integrity_map.get_state(mid)
	if before != ModuleIntegrityStateScript.STATE_INTACT:
		_fail("expected intact"); return
	var res: Dictionary = playable.run_work_action_for_validation("cut_wall", mid, {"welding_lance": 1})
	if not bool(res.get("ok", false)):
		_fail("cut %s" % str(res)); return
	var after: String = playable.module_integrity_map.get_state(mid)
	if after == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("should leave intact"); return
	var deltas: Array = playable.module_integrity_map.to_sparse_deltas()
	var found := false
	for d in deltas:
		if typeof(d) == TYPE_DICTIONARY and str((d as Dictionary).get("module_id", "")) == mid:
			found = true
			break
	if not found:
		_fail("sparse delta missing for cut module"); return
	# Coordinator leave flush should pack it
	playable._sync_current_ship_pillar_summaries()
	if playable.current_ship != null:
		var packed: Dictionary = playable.current_ship.module_integrity_summary
		var pd: Array = packed.get("deltas", []) if typeof(packed.get("deltas", [])) == TYPE_ARRAY else []
		if pd.is_empty() and not deltas.is_empty():
			_fail("flush should pack integrity deltas"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("CUT MODULE SCENE AWAY PASS away=true cut=true damaged=true sparse=true")
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
	print("CUT MODULE SCENE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
