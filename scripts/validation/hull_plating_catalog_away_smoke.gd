extends SceneTree

## Catalog hull_plating maps plating_plate and install raises hull_plating_bonus.
## Marker: HULL PLATING CATALOG AWAY PASS catalog=true install=true bonus=true

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
	var cid: String = playable.component_catalog.component_id_for_item_form("plating_plate")
	if cid != "hull_plating":
		_fail("expected hull_plating got %s" % cid); return
	var def: Dictionary = playable.component_catalog.get_component("hull_plating")
	if not bool(def.get("plating", false)):
		_fail("catalog plating flag"); return
	if absf(float(def.get("power_draw", -1.0))) > 0.001:
		_fail("plating should draw 0 power"); return
	var before: float = float(playable.ship_modification_state.hull_plating_bonus)
	playable.inventory_state.add_item("plating_plate", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog, PackedStringArray(["plating_plate"])):
		_fail("install %s" % "\n".join(panel.get_status_lines())); return
	var after: float = float(playable.ship_modification_state.hull_plating_bonus)
	if after < before + 0.049:
		_fail("bonus not raised before=%s after=%s" % [str(before), str(after)]); return
	if playable.ship_modification_state.structure_damage_resist() < 0.09:
		_fail("resist after plating"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("HULL PLATING CATALOG AWAY PASS away=true catalog=true install=true bonus=true")
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
	print("HULL PLATING CATALOG AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
