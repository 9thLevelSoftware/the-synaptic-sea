extends SceneTree

## Chart denied SFX works with away_from_start true.
## Marker: CHART DENIED AWAY PASS away=true denied=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
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
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.inventory_state != null:
		var q: int = int(playable.inventory_state.get_quantity("web_chart"))
		if q > 0:
			playable.inventory_state.remove_item("web_chart", q)
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var opened: bool = bool(playable.open_chart_panel_for_validation())
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if opened:
		_fail("chart should refuse without web_chart away"); return
	if after <= before:
		_fail("deny sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("CHART DENIED AWAY PASS away=true denied=true sfx=true")
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
	print("CHART DENIED AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
