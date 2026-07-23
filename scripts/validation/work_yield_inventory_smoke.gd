extends SceneTree

## REQ-WA-002: structure WorkAction yields land in InventoryState.
## Marker: WORK YIELD INVENTORY PASS cut=true scrap=true qty=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var scrap_before: int = 0


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
	if phase == "wait":
		_start()
	elif phase == "tick":
		_tick()


func _start() -> void:
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.inventory_state.add_item("welding_lance", 1)
	scrap_before = int(playable.inventory_state.get_quantity("scrap_metal"))
	var layout: Dictionary = playable._active_layout_for_work()
	ModuleIntegrityConsequencesScript.seed_map_from_layout(playable.module_integrity_map, layout)
	playable.player.teleport_to(Vector3(0.5, 0.0, 0.5))
	if not playable.try_work_action_interact_for_validation():
		_fail("start cut"); return
	if str(playable.work_action_driver.work.get("action_id")) != "cut_wall":
		# Force cut via validation seam
		var mid: String = "hub/yield_wall"
		playable.module_integrity_map.ensure_module(mid, "wall_straight_1x1", {"scrap_metal": 2}, "hub")
		var res: Dictionary = playable.run_work_action_for_validation("cut_wall", mid, {
			"welding_lance": 1,
		})
		if not bool(res.get("ok", false)):
			_fail("forced cut %s" % str(res)); return
		var after: int = int(playable.inventory_state.get_quantity("scrap_metal"))
		if after <= scrap_before:
			_fail("scrap not added got %d from %d yields=%s" % [after, scrap_before, str(res.get("yields", {}))])
			return
		print("WORK YIELD INVENTORY PASS cut=true scrap=true qty=true")
		finished = true
		quit(0)
		return
	phase = "tick"
	tick_accum = 0.0


func _tick() -> void:
	playable._process(0.5)
	tick_accum += 0.5
	if playable.work_action_driver.is_working():
		if tick_accum > 40.0:
			_fail("timeout"); return
		return
	var after: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	if after <= scrap_before:
		_fail("scrap not added via tick path %d->%d resolve=%s" % [
			scrap_before, after, str(playable.work_action_driver.last_resolve)
		]); return
	print("WORK YIELD INVENTORY PASS cut=true scrap=true qty=true")
	finished = true
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
	print("WORK YIELD INVENTORY FAIL: %s" % msg)
	finished = true
	quit(1)
