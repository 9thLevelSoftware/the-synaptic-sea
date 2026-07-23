extends SceneTree

## Ship-mod install restores linked hub sub; uninstall damages it; catalog power_draw bites.
## Marker: SHIP MOD SYSTEM EFFECT AWAY PASS restore=true power=true uninstall_damage=true

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
	var mgr = playable.ship_systems_manager
	if mgr == null:
		_fail("no systems manager"); return
	var sub = mgr.systems["life_support"].get_subcomponent("air_recycler")
	if sub == null:
		_fail("air_recycler missing"); return
	sub.health = 0.1
	var draw_before: float = float(playable.ship_modification_state.total_power_draw())
	playable.inventory_state.add_item("air_recycler_unit", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install status=%s" % "\n".join(panel.get_status_lines())); return
	if float(sub.health) < 0.54:
		_fail("expected restore floor got %s" % str(sub.health)); return
	if float(sub.health) > 0.56:
		_fail("should not full-heal got %s" % str(sub.health)); return
	var draw_after: float = float(playable.ship_modification_state.total_power_draw())
	if draw_after <= draw_before + 0.5:
		_fail("expected power_draw increase before=%s after=%s" % [str(draw_before), str(draw_after)]); return
	# Catalog-authored draw for air_recycler_unit is 10.0
	if absf(draw_after - draw_before - 10.0) > 0.01:
		_fail("expected +10 power_draw got delta=%s" % str(draw_after - draw_before)); return
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if float(sub.health) > 0.1:
		_fail("expected uninstall damage got %s" % str(sub.health)); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SHIP MOD SYSTEM EFFECT AWAY PASS away=true restore=true power=true uninstall_damage=true")
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
	print("SHIP MOD SYSTEM EFFECT AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
