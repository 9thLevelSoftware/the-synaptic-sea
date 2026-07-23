extends SceneTree

## plant_crop and harvest_crop stamp verb SFX and route via SfxEventRouter.
## Marker: WORK VERB SFX PLANT HARVEST AWAY PASS plant=true harvest=true

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
	var router = SfxEventRouterScript.new()
	# --- plant ---
	var inv: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx: Dictionary = {
		"tool_class": "",
		"skill_id": "cooking",
		"skill_level": 5,
		"inventory": inv,
	}
	if not playable.work_action_driver.start_action("plant_crop", "hydro_bed_sfx", ctx):
		_fail("start plant"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_pl: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv)
	if not bool(res_pl.get("ok", false)):
		_fail("plant complete %s" % str(res_pl)); return
	if str(res_pl.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_PLANT):
		_fail("plant sfx id %s" % str(res_pl.get("audio_event", ""))); return
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("plant emit empty"); return
	# --- harvest ---
	inv = playable._inventory_qty_dict_for_work()
	ctx["inventory"] = inv
	if not playable.work_action_driver.start_action("harvest_crop", "hydro_bed_sfx", ctx):
		_fail("start harvest"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_h: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv)
	if not bool(res_h.get("ok", false)):
		_fail("harvest complete %s" % str(res_h)); return
	if str(res_h.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_HARVEST):
		_fail("harvest sfx id %s" % str(res_h.get("audio_event", ""))); return
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("harvest emit empty"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK VERB SFX PLANT HARVEST AWAY PASS away=true plant=true harvest=true")
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
	print("WORK VERB SFX PLANT HARVEST AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
