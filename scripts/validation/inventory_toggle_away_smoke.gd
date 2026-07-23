extends SceneTree

## Inventory toggle works with away_from_start (derelict) true.
## Marker: INVENTORY TOGGLE AWAY PASS away=true open=true close=true

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
	if not is_instance_valid(playable.inventory_panel):
		_fail("panel"); return
	if playable.inventory_panel.is_open():
		playable.inventory_panel.close()
	playable._open_inventory_self()
	if not playable.inventory_panel.is_open():
		_fail("open failed away"); return
	playable._open_inventory_self()
	if playable.inventory_panel.is_open():
		_fail("toggle close failed away"); return
	if not bool(playable.away_from_start):
		_fail("away flag cleared"); return
	print("INVENTORY TOGGLE AWAY PASS away=true open=true close=true")
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
	print("INVENTORY TOGGLE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
