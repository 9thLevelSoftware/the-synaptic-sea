extends SceneTree

## Closing wounds / ship-mod / chart / scanner / recipe panels routes UI_PANEL_CLOSE.
## Marker: PANEL CLOSE SFX PASS wounds=true shipmod=true chart=true scanner=true recipe=true

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
	var mgr: Node = playable.audio_manager
	var checks: Array = [
		["wounds", Callable(playable, "_on_wounds_panel_closed")],
		["shipmod", Callable(playable, "_on_ship_modification_panel_closed")],
		["chart", Callable(playable, "_on_chart_panel_closed")],
		["scanner", Callable(playable, "_on_scanner_panel_closed")],
		["recipe", Callable(playable, "_on_recipe_picker_panel_closed")],
	]
	var flags: Dictionary = {}
	for pair in checks:
		var key: String = str(pair[0])
		var cb: Callable = pair[1]
		mgr.sfx_router.configure({})
		var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
		cb.call()
		var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
		if after <= before:
			_fail("%s close sfx not routed" % key); return
		flags[key] = true
	print("PANEL CLOSE SFX PASS wounds=%s shipmod=%s chart=%s scanner=%s recipe=%s" % [
		str(flags.get("wounds", false)).to_lower(),
		str(flags.get("shipmod", false)).to_lower(),
		str(flags.get("chart", false)).to_lower(),
		str(flags.get("scanner", false)).to_lower(),
		str(flags.get("recipe", false)).to_lower(),
	])
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
	print("PANEL CLOSE SFX FAIL: %s" % msg)
	finished = true
	quit(1)
