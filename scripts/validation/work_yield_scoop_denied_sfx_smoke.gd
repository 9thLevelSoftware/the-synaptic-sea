extends SceneTree

## Max-stack scoop deny on a floor WorkYieldDrop routes UI_PANEL_CLOSE and keeps the pile.
## Marker: WORK YIELD SCOOP DENIED SFX PASS deny=true sfx=true remain=true

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

	playable.inventory_state.items["scrap_metal"] = 20  # max_stack
	playable._spawn_work_yield_drop({"scrap_metal": 2})
	var drops: Array = playable.get_work_yield_drops_for_validation()
	if drops.is_empty():
		_fail("no drop"); return
	var drop = drops[0]
	drop.set_validation_player_in_range(playable.player)

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var handled: bool = playable._try_work_yield_drop_interact(playable.player)
	if not handled:
		_fail("interact not consumed on stack-full deny"); return
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("deny sfx not routed before=%d after=%d" % [before, after]); return
	if not is_instance_valid(drop):
		_fail("drop freed on deny"); return
	if int(drop.items.get("scrap_metal", 0)) != 2:
		_fail("items mutated on deny"); return
	var tracked: Array = playable.get_work_yield_drops_for_validation()
	if tracked.is_empty():
		_fail("drop untracked on deny"); return

	print("WORK YIELD SCOOP DENIED SFX PASS deny=true sfx=true remain=true")
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
	print("WORK YIELD SCOOP DENIED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
