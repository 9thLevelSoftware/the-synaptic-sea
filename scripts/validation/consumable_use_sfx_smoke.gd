extends SceneTree

## Consumable use success routes SFX_TOOL_USE; fail routes UI_PANEL_CLOSE.
## Marker: CONSUMABLE USE SFX PASS ok=true fail=true

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
	if playable.inventory_state == null:
		_fail("inventory"); return
	var mgr: Node = playable.audio_manager

	# Fail path: use missing item.
	mgr.sfx_router.configure({})
	var f0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var bad: Dictionary = playable.use_inventory_item_for_validation("no_such_item_xyz")
	var f1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if bool(bad.get("ok", false)):
		_fail("expected fail use"); return
	if f1 <= f0:
		_fail("fail SFX missing"); return

	# Success path: cooked_meal or medical item.
	playable.inventory_state.add_item("cooked_meal", 1)
	mgr.sfx_router.configure({})
	var s0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var good: Dictionary = playable.use_inventory_item_for_validation("cooked_meal")
	var s1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if not bool(good.get("ok", false)):
		# try bandage/medicine
		playable.inventory_state.add_item("field_bandage", 1)
		good = playable.use_inventory_item_for_validation("field_bandage")
		s1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if not bool(good.get("ok", false)):
		_fail("expected successful consumable use"); return
	if s1 <= s0:
		_fail("success SFX missing"); return

	print("CONSUMABLE USE SFX PASS ok=true fail=true")
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
	print("CONSUMABLE USE SFX FAIL: %s" % msg)
	finished = true
	quit(1)
