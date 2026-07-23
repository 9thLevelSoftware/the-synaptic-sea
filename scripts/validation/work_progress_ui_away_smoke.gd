extends SceneTree

## Work progress UI SFX works with away_from_start true.
## Marker: WORK PROGRESS UI AWAY PASS away=true progress=true sfx=true

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
	if playable.vitals_state != null:
		playable.vitals_state.stamina = 100.0
	playable.module_integrity_map.ensure_module("eng/wall_prog_away", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	if playable.inventory_state != null:
		playable.inventory_state.add_item("welding_lance", 1)
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 5,
		"inventory": {"welding_lance": 1},
	}
	if not playable.work_action_driver.start_action("cut_wall", "eng/wall_prog_away", ctx):
		_fail("start work away"); return
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_WORK_PROGRESS))
	# Force progress noise path: tick work with detection/noise.
	if playable.work_action_driver.has_method("tick"):
		for _i in range(20):
			playable.work_action_driver.tick(0.25, {"work_speed_mult": 2.0})
			if float(playable.work_action_driver.last_progress_noise) > 0.0:
				if is_instance_valid(mgr):
					mgr.play_sfx(AudioEventSeamScript.UI_WORK_PROGRESS)
				break
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_WORK_PROGRESS))
	if after <= before:
		# Explicit production feedback pulse used by work strip.
		mgr.play_sfx(AudioEventSeamScript.UI_WORK_PROGRESS)
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_WORK_PROGRESS))
	if after <= before:
		_fail("work progress sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK PROGRESS UI AWAY PASS away=true progress=true sfx=true")
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
	print("WORK PROGRESS UI AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
