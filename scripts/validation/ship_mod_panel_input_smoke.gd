extends SceneTree

## PKG-D9b: ship-mod panel toggles via open validation seam + selection.
## Marker: SHIP MOD PANEL INPUT PASS open=true select=true close=true

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
	if playable.get_ship_modification_panel_for_validation() == null:
		_fail("panel missing"); return
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	if not panel.is_open():
		_fail("is_open"); return
	panel.move_selection(1)
	panel.move_selection(-1)
	if panel.get_selected_slot_id().is_empty() and panel.candidate_slots.size() > 0:
		_fail("selection"); return
	panel.close()
	if panel.is_open():
		_fail("close"); return
	# Wounds panel also openable
	if not playable.open_wounds_panel_for_validation():
		_fail("wounds open"); return
	playable.wounds_panel.close()
	print("SHIP MOD PANEL INPUT PASS open=true select=true close=true")
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
	print("SHIP MOD PANEL INPUT FAIL: %s" % msg)
	finished = true
	quit(1)
