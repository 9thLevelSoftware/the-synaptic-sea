extends SceneTree

## Work interrupt on damage SFX works with away_from_start true.
## Marker: WORK INTERRUPT AWAY PASS away=true interrupt=true sfx=true

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
	if playable.work_action_driver == null:
		_fail("no work driver"); return
	if playable.module_integrity_map != null:
		playable.module_integrity_map.ensure_module("eng/wall_int_away", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	if playable.inventory_state != null:
		playable.inventory_state.add_item("welding_lance", 1)
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"welding_lance": 1},
	}
	if not playable.work_action_driver.start_action("cut_wall", "eng/wall_int_away", ctx):
		_fail("start_action failed away"); return
	if not playable.work_action_driver.is_working():
		_fail("not working after start away"); return
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	playable._interrupt_work_on_damage()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("interrupt sfx missing away"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK INTERRUPT AWAY PASS away=true interrupt=true sfx=true")
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
	print("WORK INTERRUPT AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
