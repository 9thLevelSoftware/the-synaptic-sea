extends SceneTree

## Chart key toggles web chart panel open/close when web_chart is held.
## Marker: CHART TOGGLE PASS open=true close=true

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
	if playable.inventory_state == null or not is_instance_valid(playable.chart_panel):
		_fail("inventory/chart"); return
	playable.inventory_state.add_item("web_chart", 1)
	if playable.chart_panel.is_open() and playable.chart_panel.has_method("close"):
		playable.chart_panel.close()
	if not playable.open_chart_panel_for_validation():
		_fail("did not open"); return
	if not playable.chart_panel.is_open():
		_fail("panel not open"); return
	# Toggle closed.
	var still: bool = playable.open_chart_panel_for_validation()
	if still:
		_fail("toggle returned open"); return
	if playable.chart_panel.is_open():
		_fail("panel still open after toggle"); return
	print("CHART TOGGLE PASS open=true close=true")
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
	print("CHART TOGGLE FAIL: %s" % msg)
	finished = true
	quit(1)
