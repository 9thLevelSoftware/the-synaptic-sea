extends SceneTree

## Work start block/success SFX works with away_from_start true.
## Marker: WORK START AWAY PASS away=true start=true blocked=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 300

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
	if playable.work_action_driver == null or playable.module_integrity_map == null:
		_fail("work/map"); return
	var mgr: Node = playable.audio_manager

	if playable.vitals_state != null:
		playable.vitals_state.stamina = 0.0
	playable.module_integrity_map.ensure_module("eng/wall_start_away", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	if playable.inventory_state != null:
		playable.inventory_state.add_item("welding_lance", 1)
	mgr.sfx_router.configure({})
	var b0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if playable.has_method("_try_work_action_interact") and playable.player != null:
		playable._try_work_action_interact(playable.player)
	var b1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if b1 <= b0:
		playable.vitals_state.stamina = 0.0
		if playable.player != null:
			playable._try_work_action_interact(playable.player)
		b1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if b1 <= b0:
		_fail("block SFX missing away"); return

	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	mgr.sfx_router.configure({})
	var s0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var started: bool = false
	if playable.player != null:
		started = bool(playable._try_work_action_interact(playable.player))
	if not started:
		var ctx: Dictionary = {
			"tool_class": "welding_lance",
			"skill_id": "salvage",
			"skill_level": 5,
			"inventory": {"welding_lance": 1},
		}
		started = bool(playable.work_action_driver.start_action("cut_wall", "eng/wall_start_away", ctx))
		if started:
			if playable.work_action_driver.is_working() and playable.work_action_driver.work != null:
				playable.work_action_driver.work.call("interrupt")
			started = bool(playable._try_work_action_interact(playable.player))
	var s1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if not started:
		_fail("could not start work away"); return
	if s1 <= s0:
		_fail("start SFX missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK START AWAY PASS away=true start=true blocked=true")
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
	print("WORK START AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
