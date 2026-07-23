extends SceneTree

## Work start success routes SFX_TOOL_USE; zero-stamina block routes UI_PANEL_CLOSE.
## Marker: WORK START SFX PASS start=true blocked=true

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
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.work_action_driver == null or playable.module_integrity_map == null:
		_fail("work/map"); return
	var mgr: Node = playable.audio_manager

	# Blocked: zero stamina.
	if playable.vitals_state != null:
		playable.vitals_state.stamina = 0.0
	playable.module_integrity_map.ensure_module("eng/wall_start_sfx", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	if playable.inventory_state != null:
		playable.inventory_state.add_item("welding_lance", 1)
	mgr.sfx_router.configure({})
	var b0: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	# Drive nearest work path if available; else call internal helper via validation.
	var blocked: bool = true
	if playable.has_method("_try_work_action_interact") and playable.player != null:
		blocked = not bool(playable._try_work_action_interact(playable.player))
	# Force zero-stamina start through start_action path used by helper when we can set driver via public start.
	if playable.vitals_state != null and float(playable.vitals_state.stamina) <= 0.001:
		# Direct: simulate the block branch by calling try with zero stamina.
		if playable.has_method("run_work_action_for_validation"):
			var res: Dictionary = playable.run_work_action_for_validation("cut_wall", "eng/wall_start_sfx", {"welding_lance": 1})
			blocked = not bool(res.get("ok", false))
	var b1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	# Ensure block cue: if interact didn't hit, call stamina block by starting through driver after forcing stamina.
	if b1 <= b0:
		# Invoke the work start path by setting stamina 0 and calling start via private try.
		playable.vitals_state.stamina = 0.0
		if playable.player != null:
			playable._try_work_action_interact(playable.player)
		b1 = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if b1 <= b0:
		_fail("block SFX missing"); return

	# Success start with stamina restored.
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
		started = bool(playable.work_action_driver.start_action("cut_wall", "eng/wall_start_sfx", ctx))
		if started and is_instance_valid(mgr):
			# Driver-only path skips interact SFX; playable interact is preferred.
			# Call the same start SFX by re-entering try after cancel.
			if playable.work_action_driver.is_working() and playable.work_action_driver.work != null:
				playable.work_action_driver.work.call("interrupt")
			started = bool(playable._try_work_action_interact(playable.player))
	var s1: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if not started:
		_fail("could not start work"); return
	if s1 <= s0:
		_fail("start SFX missing"); return

	print("WORK START SFX PASS start=true blocked=true")
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
	print("WORK START SFX FAIL: %s" % msg)
	finished = true
	quit(1)
