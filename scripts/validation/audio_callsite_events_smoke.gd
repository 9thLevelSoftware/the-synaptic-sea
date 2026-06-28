extends SceneTree

## REQ-AU-001 call-site audio event coupling smoke (T5b).
##
## Proves that the wired call sites in playable_generated_ship.gd fire their
## AudioEventSeam constants through audio_manager.play_sfx at the natural
## interaction points:
##
##   SFX_TOOL_USE      — consumable use path (_use_consumable_item ok=true)
##   UI_INVENTORY_OPEN — _open_inventory_self()
##   UI_INVENTORY_CLOSE — _on_inventory_panel_closed() via panel_closed signal
##   UI_OBJECTIVE_ADVANCE — _on_interactable_completed() after sequence ++
##   UI_SAVE           — request_save() on success
##
## Events skipped (no genuine call site found):
##   SFX_DOOR_OPEN / SFX_DOOR_CLOSE — portals are pure data; no open/close node
##   SFX_FOOTSTEP                    — PlayerController has no step event
##   SFX_DROP_ITEM                   — no ground-drop mechanic; zone_drop is
##                                     inter-pane transfer, not a floor drop
##   SFX_DOCK_LAND                   — call site wired at _attach_derelict_active
##                                     but requires live travel_to; not reachable
##                                     in a pure headless boot
##   UI_LOAD                         — request_load() resets the entire runtime;
##                                     too destructive to run mid-smoke
##
## Pass marker:
##   AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=true inv_toggle=true objective=true save=true dock=skip load=skip
##
## Headless:
##   <GODOT> --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea"
##     --script res://scripts/validation/audio_callsite_events_smoke.gd

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready within %d frames" % TIMEOUT_FRAMES)
		return
	_validate()

func _validate() -> void:
	if playable.audio_manager == null:
		_fail("audio_manager is null")
		return
	var mgr: Node = playable.audio_manager

	# -----------------------------------------------------------------
	# 1. SFX_TOOL_USE — consume an item through the live consumable path.
	# -----------------------------------------------------------------
	if playable.inventory_state == null:
		_fail("inventory_state is null")
		return
	playable.inventory_state.add_item("cooked_meal", 1)
	mgr.sfx_router.configure({})
	var tool_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
	var use_result: Dictionary = playable.use_inventory_item_for_validation("cooked_meal")
	var tool_ok: bool = false
	if bool(use_result.get("ok", false)):
		var tool_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
		tool_ok = tool_after > tool_before
		if not tool_ok:
			_fail("SFX_TOOL_USE not routed after successful consumable use (before=%d after=%d)" % [tool_before, tool_after])
			return
	else:
		_fail("consumable use failed — cannot verify SFX_TOOL_USE (result=%s)" % str(use_result))
		return

	# -----------------------------------------------------------------
	# 2. UI_INVENTORY_OPEN + UI_INVENTORY_CLOSE via open/close seams.
	# -----------------------------------------------------------------
	mgr.sfx_router.configure({})
	var inv_open_before: int = int(mgr.sfx_router.get_routed_count(&"ui.inventory.open"))
	playable.inventory_open_self_for_validation()
	var inv_open_after: int = int(mgr.sfx_router.get_routed_count(&"ui.inventory.open"))
	var inv_open_ok: bool = inv_open_after > inv_open_before
	if not inv_open_ok:
		_fail("UI_INVENTORY_OPEN not routed after inventory_open_self_for_validation() (before=%d after=%d)" % [inv_open_before, inv_open_after])
		return

	mgr.sfx_router.configure({})
	var inv_close_before: int = int(mgr.sfx_router.get_routed_count(&"ui.inventory.close"))
	playable.inventory_close_for_validation()
	var inv_close_after: int = int(mgr.sfx_router.get_routed_count(&"ui.inventory.close"))
	var inv_close_ok: bool = inv_close_after > inv_close_before
	if not inv_close_ok:
		_fail("UI_INVENTORY_CLOSE not routed after inventory_close_for_validation() (before=%d after=%d)" % [inv_close_before, inv_close_after])
		return

	# -----------------------------------------------------------------
	# 3. UI_OBJECTIVE_ADVANCE — complete sequence 1 via the validation seam.
	# -----------------------------------------------------------------
	mgr.sfx_router.configure({})
	var obj_before: int = int(mgr.sfx_router.get_routed_count(&"ui.objective.advance"))
	var obj_ok: bool = false
	if playable.current_objective_sequence == 1:
		var advanced: bool = playable.complete_objective_sequence_for_validation(1)
		if not advanced:
			_fail("complete_objective_sequence_for_validation(1) returned false")
			return
		var obj_after: int = int(mgr.sfx_router.get_routed_count(&"ui.objective.advance"))
		obj_ok = obj_after > obj_before
		if not obj_ok:
			_fail("UI_OBJECTIVE_ADVANCE not routed after objective completion (before=%d after=%d)" % [obj_before, obj_after])
			return
	else:
		_fail("current_objective_sequence != 1 at start of objective test (got %d)" % playable.current_objective_sequence)
		return

	# -----------------------------------------------------------------
	# 4. UI_SAVE — fire request_save() and verify the event routed.
	# -----------------------------------------------------------------
	mgr.sfx_router.configure({})
	var save_before: int = int(mgr.sfx_router.get_routed_count(&"ui.save"))
	var saved: bool = playable.request_save()
	var save_after: int = int(mgr.sfx_router.get_routed_count(&"ui.save"))
	var save_ok: bool = saved and save_after > save_before
	if not save_ok:
		_fail("UI_SAVE not routed after request_save() (saved=%s before=%d after=%d)" % [str(saved), save_before, save_after])
		return

	# -----------------------------------------------------------------
	# All assertions passed.  Skipped events logged in marker.
	# -----------------------------------------------------------------
	finished = true
	print("AUDIO CALLSITE EVENTS PASS door=skip footstep=skip drop=skip tool=%s inv_toggle=%s objective=%s save=%s dock=skip load=skip" % [
		str(tool_ok).to_lower(),
		str(inv_open_ok and inv_close_ok).to_lower(),
		str(obj_ok).to_lower(),
		str(save_ok).to_lower(),
	])
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("AUDIO CALLSITE EVENTS FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
