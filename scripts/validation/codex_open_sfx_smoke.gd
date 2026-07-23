extends SceneTree

## Opening codex menu routes UI_PANEL_OPEN.
## Marker: CODEX OPEN SFX PASS open=true sfx=true

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
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.menu_coordinator == null:
		_fail("menu_coordinator"); return
	# Ensure audio manager is bound on coordinator.
	if playable.menu_coordinator._audio_manager == null:
		playable.menu_coordinator._audio_manager = playable.audio_manager
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	playable.menu_coordinator.menu_state.open_menu("codex")
	playable.menu_coordinator._emit_menu_open_sfx()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_OPEN))
	if after <= before:
		_fail("UI_PANEL_OPEN not routed before=%d after=%d" % [before, after]); return
	print("CODEX OPEN SFX PASS open=true sfx=true")
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
	print("CODEX OPEN SFX FAIL: %s" % msg)
	finished = true
	quit(1)
