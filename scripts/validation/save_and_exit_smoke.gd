extends SceneTree

## ADR-0043 Save & Exit smoke: drives the pause menu's new "Save & Exit"
## item end-to-end -- request_save() succeeds, world.json reflects the live
## session (not just "a file exists"), and return_to_title_requested fires.
##
## Also drives the FAILURE branch (review finding 2) through the exact same
## real pause-menu path: force request_save()'s own guard
## (playable.slice_complete = true) so Save & Exit fails, then assert (a) no
## world save is written, (b) return_to_title_requested does NOT fire, and
## (c) the "save_and_exit_failed"/"any" tutorial trigger registered in
## data/ui/tutorial_triggers.json actually fired (review finding 1) --
## observed via menu_coordinator.tutorial_state.get_latest_tutorial_id(),
## the same seam TutorialOverlayPanel reads to render the toast.
##
## Pass marker (unchanged byte-contract; failure-path assertions fail via
## the FAIL path, not new marker fields):
##   SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
const FAILURE_TRIGGER_ID: String = "save_and_exit_failed"

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var _return_signal_received: bool = false

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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.menu_coordinator == null or playable.save_load_service == null:
		_fail("menu_coordinator / save_load_service missing")
		return
	playable.save_load_service.delete_current_run()
	playable.return_to_title_requested.connect(_on_return_to_title)

	if not _drive_failure_stage():
		return
	if not _drive_success_stage():
		return

	finished = true
	print("SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true")
	_cleanup_and_quit(0)

## Review finding 2: force request_save()'s own guard (slice_complete) so
## Save & Exit fails through the REAL pause-menu confirm path (not a direct
## call to _on_save_and_exit_requested), then assert the failure contract:
## no world save written, no return-to-title signal, and the failure toast
## trigger actually fired (finding 1's observable). Resets slice_complete
## afterward so the success stage below is unaffected.
func _drive_failure_stage() -> bool:
	var coord = playable.menu_coordinator
	playable.slice_complete = true
	var confirmed: bool = _open_pause_menu_and_confirm(coord, "save_and_exit")
	playable.slice_complete = false
	if not confirmed:
		return false

	if playable.save_load_service.has_save():
		_fail("world save present after a forced Save & Exit failure -- progress must NOT be written")
		return false
	if _return_signal_received:
		_fail("return_to_title_requested fired on a forced Save & Exit failure -- must not exit on failure")
		return false
	var latest_tutorial_id: String = String(coord.tutorial_state.get_latest_tutorial_id())
	if latest_tutorial_id != FAILURE_TRIGGER_ID:
		_fail("save_and_exit_failed tutorial trigger did not fire (latest_tutorial_id='%s') -- failure toast is silent" % latest_tutorial_id)
		return false
	if not coord.tutorial_state.has_pending_banner():
		_fail("save_and_exit_failed tutorial triggered but has no pending banner to render")
		return false
	return true

## Review finding 3: after a successful Save & Exit, load the just-written
## world save back and assert an observable field (current_objective_sequence)
## matches the live session at save time -- existence-only is not enough to
## prove the write actually reflects the session. Mutated away from the
## default-init value (1) before saving (Task 12 hardening) so a bug that
## silently persisted the default would not slip past a 1==1 comparison --
## mirrors title_screen_flow_smoke.gd's FIXTURE_OBJECTIVE_SEQUENCE pattern.
func _drive_success_stage() -> bool:
	var coord = playable.menu_coordinator
	playable.current_objective_sequence = 2
	var expected_sequence: int = playable.get_current_objective_sequence()
	if not _open_pause_menu_and_confirm(coord, "save_and_exit"):
		return false

	if not playable.save_load_service.has_save():
		_fail("world save missing after Save & Exit")
		return false
	if not _return_signal_received:
		_fail("return_to_title_requested did not fire after a successful Save & Exit")
		return false

	var loaded_snapshot = playable.save_load_service.load_world()
	if loaded_snapshot == null:
		_fail("load_world() returned null immediately after a successful Save & Exit")
		return false
	var home_ship: Dictionary = loaded_snapshot.home_ship
	if not (home_ship.get("current_objective_sequence", -1) == expected_sequence):
		_fail("saved world does not reflect live session: home_ship.current_objective_sequence=%s expected=%d" % [
			str(home_ship.get("current_objective_sequence", -1)),
			expected_sequence,
		])
		return false
	return true

func _open_pause_menu_and_confirm(coord, item_id: String) -> bool:
	coord.open_records_menu()  # ensures we start from a known state
	coord.menu_state.close_all()
	coord.menu_state.open_menu("pause_menu")
	var items: Array = coord.menu_state.get_items("pause_menu")
	var target_index: int = -1
	for i in range(items.size()):
		if str((items[i] as Dictionary).get("id", "")) == item_id:
			target_index = i
			break
	if target_index < 0:
		_fail("%s item not found in pause_menu catalog" % item_id)
		return false
	coord.menu_state.set_focus_index(target_index)
	coord._confirm_current_item()
	return true

func _on_return_to_title() -> void:
	_return_signal_received = true

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
	push_error("SAVE AND EXIT FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
		playable.save_load_service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
