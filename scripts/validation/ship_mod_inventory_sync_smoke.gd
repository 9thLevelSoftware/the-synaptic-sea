extends SceneTree

## Ship-mod panel install/uninstall mirrors InventoryState.
## Marker: SHIP MOD INVENTORY SYNC PASS install=true uninstall=true inv=true

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
	playable.inventory_state.add_item("console_unit", 2)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	var before: int = int(playable.inventory_state.get_quantity("console_unit"))
	if not panel.install_into_selected("console_generic", "console_unit", 5.0, 12.0, false):
		_fail("install"); return
	# Signal should have removed one from InventoryState
	var mid: int = int(playable.inventory_state.get_quantity("console_unit"))
	if mid != before - 1:
		_fail("install inv %d -> %d" % [before, mid]); return
	if playable.ship_modification_state.installed_count() < 1:
		_fail("mod state empty"); return
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	var after: int = int(playable.inventory_state.get_quantity("console_unit"))
	if after != before:
		_fail("uninstall inv %d want %d" % [after, before]); return
	print("SHIP MOD INVENTORY SYNC PASS install=true uninstall=true inv=true")
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
	print("SHIP MOD INVENTORY SYNC FAIL: %s" % msg)
	finished = true
	quit(1)
