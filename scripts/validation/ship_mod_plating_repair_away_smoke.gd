extends SceneTree

## Installing plating via ship-mod repairs a damaged hub module.
## Marker: SHIP MOD PLATING REPAIR AWAY PASS install=true repair=true

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
	playable.module_integrity_map.ensure_module("hub/wall_plate", "wall")
	var m = playable.module_integrity_map.get_module("hub/wall_plate")
	m.integrity = 0.5
	m._recompute_state()
	var before: float = float(m.integrity)
	playable.inventory_state.add_item("plating_plate", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog, PackedStringArray(["plating_plate"])):
		_fail("install"); return
	if float(m.integrity) <= before:
		_fail("expected plating install to repair module before=%s after=%s" % [str(before), str(m.integrity)]); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SHIP MOD PLATING REPAIR AWAY PASS away=true install=true repair=true")
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
	print("SHIP MOD PLATING REPAIR AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
