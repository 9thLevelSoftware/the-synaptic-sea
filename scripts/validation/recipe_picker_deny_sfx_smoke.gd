extends SceneTree

## Recipe picker confirm on blocked recipe routes UI_PANEL_CLOSE.
## Marker: RECIPE PICKER DENY SFX PASS deny=true sfx=true

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
	if playable.recipe_picker_panel == null:
		_fail("no recipe picker"); return
	var panel = playable.recipe_picker_panel
	if panel.has_method("bind"):
		panel.bind(playable)
	# Force blocked selection.
	panel._entries = [{"recipe_id": "field_splint", "craftable": false, "status": "missing_ingredients"}]
	panel._selected = 0
	panel._coordinator = playable
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var res: Dictionary = panel.confirm_selection()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if bool(res.get("ok", false)):
		_fail("expected blocked confirm"); return
	if after <= before:
		_fail("UI_PANEL_CLOSE not routed before=%d after=%d" % [before, after]); return
	print("RECIPE PICKER DENY SFX PASS deny=true sfx=true")
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
	print("RECIPE PICKER DENY SFX FAIL: %s" % msg)
	finished = true
	quit(1)
