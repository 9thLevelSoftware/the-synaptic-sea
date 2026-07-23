extends SceneTree

## suppress_fire complete stamps tool-use SFX (verb suppress) and routes.
## Marker: WORK SUPPRESS SFX LIVE AWAY PASS complete=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
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
	playable.away_from_start = true
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "",
		"skill_id": "repair",
		"skill_level": 5,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("suppress_fire", "comp_sfx", ctx):
		_fail("start"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv)
	if not bool(res.get("ok", false)):
		_fail("complete %s" % str(res)); return
	# suppress maps to SFX_TOOL_USE in WORK_VERB_TO_SFX
	var expected: String = String(AudioEventSeamScript.SFX_TOOL_USE)
	if str(res.get("audio_event", "")) != expected:
		_fail("sfx id %s expected %s" % [str(res.get("audio_event", "")), expected]); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("emit empty"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK SUPPRESS SFX LIVE AWAY PASS away=true complete=true sfx=true")
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
	print("WORK SUPPRESS SFX LIVE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
