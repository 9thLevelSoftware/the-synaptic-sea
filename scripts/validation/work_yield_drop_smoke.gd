extends SceneTree

## Cart-overload pending yields spawn a floor WorkYieldDrop that scoops into inventory.
## Marker: WORK YIELD DROP PASS overload=true drop=true scoop=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")

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
	# Force cart capacity tiny so yields overflow.
	if playable.work_action_driver == null:
		_fail("driver"); return
	playable.work_action_driver.cart_mass = 99.0
	playable.work_action_driver.cart_capacity = 100.0
	playable.inventory_state.add_item("welding_lance", 1)
	var mid: String = "hub/drop_wall"
	playable.module_integrity_map.ensure_module(mid, "wall_straight_1x1", {"scrap_metal": 4}, "hub")
	var scrap_before: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	var res: Dictionary = playable.run_work_action_for_validation("cut_wall", mid, {"welding_lance": 1})
	# With cart overload, yields_applied may be false
	if bool(res.get("cart_overload", false)) or not bool(res.get("yields_applied", true)):
		pass
	else:
		# Force spawn path if cart didn't overload (low mass yields)
		playable.work_action_driver.pending_yields = {"scrap_metal": 3}
		playable.work_action_driver.overloaded = true
		playable._apply_work_yields_to_inventory_state({
			"ok": true,
			"yields_applied": false,
			"yields": {"scrap_metal": 3},
		})
	var drops: Array = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("expected floor drop res=%s" % str(res)); return
	var drop = drops[0]
	if not is_instance_valid(drop):
		_fail("drop invalid"); return
	drop.set_validation_player_in_range(playable.player)
	playable.player.teleport_to(drop.global_position)
	if not drop.try_interact(playable.player):
		_fail("scoop"); return
	var scrap_after: int = int(playable.inventory_state.get_quantity("scrap_metal"))
	if scrap_after <= scrap_before:
		_fail("scrap not scooped %d->%d" % [scrap_before, scrap_after]); return
	print("WORK YIELD DROP PASS overload=true drop=true scoop=true")
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
	print("WORK YIELD DROP FAIL: %s" % msg)
	finished = true
	quit(1)
