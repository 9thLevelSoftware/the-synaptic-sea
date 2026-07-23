extends SceneTree

## weld_patch and pry_panel complete stamp verb SFX and route via SfxEventRouter.
## Marker: WORK VERB SFX MULTI PASS weld=true pry=true

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
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	# --- weld ---
	playable.module_integrity_map.ensure_module("eng/wall_weld_sfx", "wall")
	var mw = playable.module_integrity_map.get_module("eng/wall_weld_sfx")
	if mw != null:
		mw.integrity = 0.5
		if mw.has_method("_recompute_state"):
			mw._recompute_state()
	if playable.inventory_state.get_quantity("welding_lance") < 1:
		playable.inventory_state.add_item("welding_lance", 1)
	if playable.inventory_state.get_quantity("hull_plate") < 1:
		playable.inventory_state.add_item("hull_plate", 1)
	var inv_w: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx_w: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 2,
		"inventory": inv_w,
	}
	if not playable.work_action_driver.start_action("weld_patch", "eng/wall_weld_sfx", ctx_w):
		_fail("start weld"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_w: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv_w)
	if not bool(res_w.get("ok", false)):
		_fail("weld complete"); return
	if str(res_w.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_WELD):
		_fail("weld sfx id %s" % str(res_w.get("audio_event", ""))); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("weld emit empty"); return
	# --- pry ---
	playable.module_integrity_map.ensure_module("eng/wall_pry_sfx", "wall")
	if playable.inventory_state.get_quantity("prybar") < 1:
		playable.inventory_state.add_item("prybar", 1)
	var inv_p: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx_p: Dictionary = {
		"tool_class": "prybar",
		"skill_id": "salvage",
		"skill_level": 5,
		"inventory": inv_p,
	}
	if not playable.work_action_driver.start_action("pry_panel", "eng/wall_pry_sfx", ctx_p):
		_fail("start pry"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_p: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv_p)
	if not bool(res_p.get("ok", false)):
		_fail("pry complete"); return
	if str(res_p.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_PRY):
		_fail("pry sfx id %s" % str(res_p.get("audio_event", ""))); return
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("pry emit empty"); return
	print("WORK VERB SFX MULTI PASS weld=true pry=true")
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
	print("WORK VERB SFX MULTI FAIL: %s" % msg)
	finished = true
	quit(1)
