extends SceneTree

## Live cut_wall complete stamps audio_event and is routable via seam.
## Marker: WORK COMPLETE SFX LIVE AWAY PASS complete=true audio=true route=true

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
	playable.module_integrity_map.ensure_module("eng/wall_sfx", "wall")
	if playable.inventory_state.get_quantity("welding_lance") < 1:
		playable.inventory_state.add_item("welding_lance", 1)
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 5,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("cut_wall", "eng/wall_sfx", ctx):
		_fail("start"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv)
	if not bool(res.get("ok", false)):
		_fail("complete"); return
	var ae: String = str(res.get("audio_event", ""))
	if ae != String(AudioEventSeamScript.SFX_WORK_CUT):
		_fail("expected cut sfx got %s" % ae); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	var bus: String = playable.work_action_driver.emit_completion_sfx(router)
	if bus.is_empty():
		_fail("emit_completion_sfx empty"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK COMPLETE SFX LIVE AWAY PASS away=true complete=true audio=true route=true")
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
	print("WORK COMPLETE SFX LIVE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
