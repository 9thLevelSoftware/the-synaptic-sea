extends SceneTree

## Ship-mod panel key toggles open/close.
## Marker: SHIP MOD TOGGLE PASS open=true close=true

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
	if playable.ship_modification_panel == null:
		_fail("panel"); return
	if playable.ship_modification_panel.is_open() and playable.ship_modification_panel.has_method("close"):
		playable.ship_modification_panel.close()
	if not playable.open_ship_modification_panel_for_validation():
		_fail("did not open"); return
	if not playable.ship_modification_panel.is_open():
		_fail("not open"); return
	if playable.open_ship_modification_panel_for_validation():
		_fail("toggle returned open"); return
	if playable.ship_modification_panel.is_open():
		_fail("still open after toggle"); return
	print("SHIP MOD TOGGLE PASS open=true close=true")
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
	print("SHIP MOD TOGGLE FAIL: %s" % msg)
	finished = true
	quit(1)
