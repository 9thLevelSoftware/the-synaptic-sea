extends SceneTree

## patch_breach and splice_conduit stamp verb SFX and route via SfxEventRouter.
## Marker: WORK VERB SFX PATCH SPLICE AWAY PASS patch=true splice=true

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
	# --- patch ---
	playable.module_integrity_map.ensure_module("eng/wall_patch_sfx", "wall")
	var mp = playable.module_integrity_map.get_module("eng/wall_patch_sfx")
	if mp != null:
		mp.integrity = 0.35
		if mp.has_method("_recompute_state"):
			mp._recompute_state()
	playable.inventory_state.add_item("sealant", 1)
	playable.inventory_state.add_item("hull_sealant", 1)
	var inv_p: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx_p: Dictionary = {
		"tool_class": "sealant",
		"skill_id": "repair",
		"skill_level": 2,
		"inventory": inv_p,
	}
	if not playable.work_action_driver.start_action("patch_breach", "eng/wall_patch_sfx", ctx_p):
		_fail("start patch"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_p: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv_p)
	if not bool(res_p.get("ok", false)):
		_fail("patch complete %s" % str(res_p)); return
	if str(res_p.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_PATCH):
		_fail("patch sfx id %s" % str(res_p.get("audio_event", ""))); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("patch emit empty"); return
	# --- splice ---
	playable.module_integrity_map.ensure_module("eng/conduit_splice_sfx", "wall")
	playable.inventory_state.add_item("multitool", 1)
	playable.inventory_state.add_item("wire_spool", 1)
	var inv_s: Dictionary = playable._inventory_qty_dict_for_work()
	var ctx_s: Dictionary = {
		"tool_class": "multitool",
		"skill_id": "repair",
		"skill_level": 2,
		"inventory": inv_s,
	}
	if not playable.work_action_driver.start_action("splice_conduit", "eng/conduit_splice_sfx", ctx_s):
		_fail("start splice"); return
	playable.work_action_driver.tick(99.0, {"work_speed_mult": 1.0})
	var res_s: Dictionary = playable.work_action_driver.complete(playable.module_integrity_map, inv_s)
	if not bool(res_s.get("ok", false)):
		_fail("splice complete %s" % str(res_s)); return
	if str(res_s.get("audio_event", "")) != String(AudioEventSeamScript.SFX_WORK_SPLICE):
		_fail("splice sfx id %s" % str(res_s.get("audio_event", ""))); return
	router.configure({})
	if playable.work_action_driver.emit_completion_sfx(router).is_empty():
		_fail("splice emit empty"); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WORK VERB SFX PATCH SPLICE AWAY PASS away=true patch=true splice=true")
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
	print("WORK VERB SFX PATCH SPLICE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
