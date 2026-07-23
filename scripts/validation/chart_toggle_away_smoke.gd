extends SceneTree

## Chart toggle works with away_from_start true.
## Marker: CHART TOGGLE AWAY PASS away=true open=true close=true

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
	if playable.inventory_state == null or not is_instance_valid(playable.chart_panel):
		_fail("inventory/chart"); return
	playable.inventory_state.add_item("web_chart", 1)
	if playable.chart_panel.is_open() and playable.chart_panel.has_method("close"):
		playable.chart_panel.close()
	if not playable.open_chart_panel_for_validation():
		_fail("open failed away"); return
	if playable.open_chart_panel_for_validation():
		_fail("toggle close failed away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("CHART TOGGLE AWAY PASS away=true open=true close=true")
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
	print("CHART TOGGLE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
