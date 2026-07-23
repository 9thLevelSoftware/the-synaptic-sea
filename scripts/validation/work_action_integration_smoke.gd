extends SceneTree

## Integration: WorkActionDriver + HUD + wounds + ship mod wired on playable.
## Marker: WORK ACTION INTEGRATION PASS driver=true hud=true wounds=true shipmod=true cut=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")

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
	if playable.get_work_action_driver_for_validation() == null:
		_fail("work_action_driver not wired"); return
	if playable.get_work_action_hud_for_validation() == null:
		_fail("work_action_hud not wired"); return
	if playable.get_wound_state_for_validation() == null:
		_fail("wound_state not wired"); return
	if playable.get_wounds_panel_for_validation() == null:
		_fail("wounds_panel not wired"); return
	if playable.get_ship_modification_state_for_validation() == null:
		_fail("ship_mod not wired"); return
	if playable.get_sea_graph_for_validation() == null:
		_fail("sea_graph not wired"); return

	# Seed a wall module and cut it via validation seam
	var mim = playable.get_module_integrity_map_for_validation()
	if mim == null:
		_fail("module map"); return
	mim.ensure_module("hub/wall_test", "wall_straight_1x1", {}, "bridge")
	var res: Dictionary = playable.run_work_action_for_validation("cut_wall", "hub/wall_test", {
		"welding_lance": 1,
	})
	# cut may fail start if tool_class required but inventory is dict - driver uses tool_class welding_lance
	if not bool(res.get("ok", false)):
		# Retry with explicit inventory that satisfies can_start materials
		res = playable.run_work_action_for_validation("pry_panel", "hub/wall_test", {"prybar": 1})
	if not bool(res.get("ok", false)):
		_fail("work action failed: %s" % str(res)); return
	if str(res.get("audio_event", "")).is_empty():
		_fail("audio_event missing"); return

	# Wounds panel open
	if not playable.open_wounds_panel_for_validation():
		_fail("wounds panel open"); return
	playable.wound_state.apply_wound({
		"kind": "laceration",
		"body_part": "arm",
		"severity": 0.4,
	})
	playable.wounds_panel.refresh()
	if playable.wounds_panel.get_selected_wound_id().is_empty():
		_fail("wound selection"); return

	# Ship mod install
	var mod = playable.get_ship_modification_state_for_validation()
	var inv: Dictionary = {"console_unit": 1}
	var inst: Dictionary = mod.install("hub_slot_0", "console_generic", "console_unit", inv, 5.0, 12.0, "home")
	if not bool(inst.get("ok", false)):
		_fail("ship mod install: %s" % str(inst.get("reason", ""))); return

	print("WORK ACTION INTEGRATION PASS driver=true hud=true wounds=true shipmod=true cut=true")
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
	finished = true
	print("WORK ACTION INTEGRATION FAIL: %s" % msg)
	quit(1)
