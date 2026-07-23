extends SceneTree

## Loot container search with zero grants routes deny SFX (not success tool-use).
## Marker: LOOT EMPTY GRANT SFX PASS empty=true deny=true no_tool=true

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
	mgr.sfx_router.configure({})
	var deny_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var tool_before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	# Direct production handler with empty grant list (bag full / empty roll).
	playable._on_loot_container_searched("empty_grant_test", [])
	var deny_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var tool_after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if deny_after <= deny_before:
		_fail("deny sfx not routed before=%d after=%d" % [deny_before, deny_after]); return
	if tool_after != tool_before:
		_fail("tool-use should not route on empty grant before=%d after=%d" % [tool_before, tool_after]); return

	# Control: non-empty grant still routes tool-use.
	mgr.sfx_router.configure({})
	tool_before = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	playable._on_loot_container_searched("granted_test", [{"item_id": "scrap_metal", "quantity": 1}])
	tool_after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if tool_after <= tool_before:
		_fail("tool-use not routed on non-empty grant"); return

	print("LOOT EMPTY GRANT SFX PASS empty=true deny=true no_tool=true")
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
	print("LOOT EMPTY GRANT SFX FAIL: %s" % msg)
	finished = true
	quit(1)
