extends SceneTree

## Inventory key toggles self-inventory open/close.
## Marker: INVENTORY TOGGLE PASS open=true close=true

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
	if not is_instance_valid(playable.inventory_panel):
		_fail("panel"); return
	if playable.inventory_panel.is_open():
		playable.inventory_panel.close()
	playable.inventory_open_self_for_validation()
	if not playable.inventory_panel.is_open():
		_fail("did not open"); return
	if str(playable.inventory_panel.get_mode()) != "self":
		_fail("mode not self"); return
	# Second open toggles closed.
	playable._open_inventory_self()
	if playable.inventory_panel.is_open():
		_fail("did not toggle closed"); return
	print("INVENTORY TOGGLE PASS open=true close=true")
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
	print("INVENTORY TOGGLE FAIL: %s" % msg)
	finished = true
	quit(1)
