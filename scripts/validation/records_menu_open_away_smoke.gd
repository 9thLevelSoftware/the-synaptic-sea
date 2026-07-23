extends SceneTree

## Records menu open SFX works with away_from_start true.
## Marker: RECORDS MENU OPEN AWAY PASS away=true open=true sfx=true

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
	var mc = playable.menu_coordinator
	if mc == null:
		_fail("menu_coordinator"); return
	if mc._audio_manager == null:
		mc._audio_manager = playable.audio_manager
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	mc.menu_state.open_menu("records_menu")
	mc._emit_menu_open_sfx()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	if after <= before:
		_fail("open sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("RECORDS MENU OPEN AWAY PASS away=true open=true sfx=true")
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
	print("RECORDS MENU OPEN AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
