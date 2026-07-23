extends SceneTree

## Ship-mod panel install_from_inventory installs using bag item forms.
## Marker: SHIP MOD INSTALL KEY AWAY PASS install=true catalog=true uninstall=true

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
	playable.inventory_state.add_item("console_unit", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install_from_inventory status=%s" % "\n".join(panel.get_status_lines())); return
	if playable.ship_modification_state.installed_count() < 1:
		_fail("not installed"); return
	if int(playable.inventory_state.get_quantity("console_unit")) != 0:
		_fail("inventory not consumed"); return
	# Select occupied and uninstall
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if int(playable.inventory_state.get_quantity("console_unit")) < 1:
		_fail("uninstall return"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SHIP MOD INSTALL KEY AWAY PASS away=true install=true catalog=true uninstall=true")
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
	print("SHIP MOD INSTALL KEY AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
