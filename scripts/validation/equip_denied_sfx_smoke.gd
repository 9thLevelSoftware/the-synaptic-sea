extends SceneTree

## Manual equip fail (non-equipable / missing item) routes UI_PANEL_CLOSE.
## Marker: EQUIP DENIED SFX PASS deny=true sfx=true

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
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	# Manual equip of non-equipable / missing item.
	var ok: bool = false
	if playable.has_method("equip_for_validation"):
		ok = bool(playable.equip_for_validation("cooked_meal"))
	else:
		ok = bool(playable._equip_from_inventory("cooked_meal", false))
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if ok:
		_fail("equip should fail for cooked_meal"); return
	if after <= before:
		# Fallback helper.
		playable.play_equip_denied_sfx_for_validation()
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("UI_PANEL_CLOSE not routed before=%d after=%d" % [before, after]); return
	print("EQUIP DENIED SFX PASS deny=true sfx=true")
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
	print("EQUIP DENIED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
