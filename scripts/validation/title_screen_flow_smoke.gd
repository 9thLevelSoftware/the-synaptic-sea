extends SceneTree

## ADR-0043 title screen flow smoke: boots scenes/title_main.tscn (the new
## run/main_scene), drives New Game to a live playable slice, drives
## return-to-title (pause menu quit_main -> return_to_title_requested),
## then drives Continue against a pre-seeded world.json, and finally
## drives the Quit path's signal wiring. Includes the teardown/
## reinstantiate double-boot check (Risk 2): a second PlayableGeneratedShip
## must cleanly reach playable_started in the SAME process after the first
## is queue_free()'d.
##
## Continue fixture (Important review finding 1): a fresh New Game boot always
## starts at current_objective_sequence=1, so round-tripping the smoke's own
## just-created save would pass even if request_load() applied nothing. Before
## driving Continue we overwrite world.json's embedded home_ship snapshot with
## current_objective_sequence=3 (mutating the REAL on-disk save the live New
## Game instance just wrote, so layout_path/kit_path/gameplay_slice_path stay
## valid for the loader) and assert the Continue'd instance's
## current_objective_sequence equals 3 -- a value a fresh boot can never produce.
##
## Quit signal (Important review finding 2): rather than self-emitting
## return_to_title_requested, we drive the REAL producer chain: open the live
## pause menu, focus "quit_main", and confirm it through
## MenuCoordinator._confirm_current_item() (mirrors permadeath_freeze_smoke.gd's
## direct menu_coordinator/menu_state access). That emits quit_requested, which
## playable._on_ui_quit_requested (connected at boot) turns into
## return_to_title_requested -- the exact signal chain "Quit to Main Menu"
## drives in the real game.
##
## Pass marker:
##   TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TIMEOUT_FRAMES: int = 900
const FIXTURE_OBJECTIVE_SEQUENCE: int = 3

var title_node: Node
var frame_count: int = 0
var finished: bool = false
var _stage: String = "new_game_boot"
## GDScript lambdas capture locals BY VALUE at creation time, not by
## reference -- a `var received := false` local mutated inside a signal
## callback lambda never updates the outer local's copy. Must be a
## script-level field so the callback's write is observable afterward.
var _quit_signal_received: bool = false

func _initialize() -> void:
	_wipe_saves()
	title_node = TITLE_SCENE.instantiate()
	get_root().add_child(title_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("timed out in stage=%s" % _stage)
		return
	match _stage:
		"new_game_boot":
			_drive_new_game()
		"await_new_game_playable":
			_await_new_game_playable()
		"return_to_title":
			_drive_return_to_title()
		"await_title_rebuilt":
			_await_title_rebuilt()
		"continue_boot":
			_drive_continue()
		"await_continue_playable":
			_await_continue_playable()
		"quit_signal_check":
			_drive_quit_signal()

func _drive_new_game() -> void:
	if title_node.menu_state == null:
		return
	if title_node.menu_state.get_current_menu() != "main_menu":
		return
	# Move cursor to "start" (index 0 per menu_definitions.json ordering) and confirm.
	title_node._confirm()  # focus_index defaults to 0 == "start"
	_stage = "await_new_game_playable"

func _await_new_game_playable() -> void:
	var playable: PlayableGeneratedShip = title_node.playable_instance
	if playable == null or not playable.playable_started:
		return
	# Codex round 2 finding A: _build_runtime_nodes parks the child's own
	# boot-time main_menu open (menu_coordinator.open_main_menu()). The title
	# handoff (_poll_for_playable_started) must dismiss it via
	# dismiss_boot_menu() once should_load/settings handling is done, or the
	# player would land on a SECOND parked menu capturing input instead of
	# gameplay. By the time playable_started is observed true here, the
	# handoff has already run synchronously -- assert the child's own menu
	# coordinator is back in-play (no menu open), not still parked.
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null or not is_instance_valid(ui):
		_fail("menu_coordinator missing after New Game handoff")
		return
	if not ui.menu_state.is_in_play():
		_fail("child menu still open after New Game handoff: current_menu=%s" % ui.get_current_menu())
		return
	# Save a real world.json through the live instance so Continue (later
	# stage, after a fresh title rebuild) has something to load.
	if not playable.request_save():
		_fail("request_save failed after New Game boot")
		return
	# Finding 1 fixture: mutate the just-written world.json into a
	# distinguishable state before Continue ever gets to it. A fresh boot
	# always starts at sequence 1, so stamping sequence=3 into the saved
	# home_ship snapshot and asserting it later proves request_load()
	# actually applied the file rather than merely finding one present.
	if not _seed_continue_fixture(playable):
		_fail("failed to seed distinguishable Continue fixture over world.json")
		return
	_stage = "return_to_title"

## Overwrites the on-disk world.json's embedded home_ship.current_objective_sequence
## with FIXTURE_OBJECTIVE_SEQUENCE, reusing the real layout_path/kit_path/
## gameplay_slice_path the live New Game instance already wrote (so the loader
## still succeeds) -- only the objective sequence is distinguished from a
## fresh boot.
func _seed_continue_fixture(playable: PlayableGeneratedShip) -> bool:
	var service := playable.get_save_load_service()
	if service == null:
		return false
	var ws = service.load_world()
	if ws == null:
		return false
	var home_ship: Dictionary = ws.home_ship.duplicate(true)
	if home_ship.is_empty():
		return false
	home_ship["current_objective_sequence"] = FIXTURE_OBJECTIVE_SEQUENCE
	ws.home_ship = home_ship
	return service.save_world(ws)

func _drive_return_to_title() -> void:
	var playable: PlayableGeneratedShip = title_node.playable_instance
	if playable == null:
		_fail("playable_instance missing before return-to-title drive")
		return
	# Simulate the pause-menu "Quit to Main Menu" path directly through the
	# signal (the exact producer _on_ui_quit_requested now emits).
	playable.emit_signal("return_to_title_requested")
	_stage = "await_title_rebuilt"

func _await_title_rebuilt() -> void:
	if title_node.main_node != null:
		return  # still tearing down
	if title_node.menu_state == null or title_node.menu_state.get_current_menu() != "main_menu":
		return
	_stage = "continue_boot"

func _drive_continue() -> void:
	if not title_node.menu_state.is_item_enabled("main_menu", "continue"):
		_fail("Continue should be enabled after a fresh world.json save")
		return
	title_node.menu_state.set_focus_index(1)  # "continue" is index 1
	title_node._confirm()
	_stage = "await_continue_playable"

func _await_continue_playable() -> void:
	var playable: PlayableGeneratedShip = title_node.playable_instance
	if playable == null or not playable.playable_started:
		return
	# Continue's request_load() call happens synchronously inside
	# _poll_for_playable_started once playable_started flips true; by the
	# time we observe playable_started here it has already fired. Confirm
	# the world save is intact (freeze-not-delete means load did not
	# consume it).
	if not playable.get_save_load_service().has_save():
		_fail("world save missing after Continue")
		return
	# Finding 1 assertion: a fresh New Game boot can only ever produce
	# current_objective_sequence=1. Observing FIXTURE_OBJECTIVE_SEQUENCE (3)
	# here proves request_load() actually applied the seeded world.json
	# fixture rather than Continue silently no-op'ing into a fresh slice.
	if playable.get_current_objective_sequence() != FIXTURE_OBJECTIVE_SEQUENCE:
		_fail("Continue did not apply fixture: current_objective_sequence=%d expected=%d" % [
			playable.get_current_objective_sequence(),
			FIXTURE_OBJECTIVE_SEQUENCE,
		])
		return
	_stage = "quit_signal_check"

func _drive_quit_signal() -> void:
	var playable: PlayableGeneratedShip = title_node.playable_instance
	if playable == null:
		_fail("playable_instance missing before quit-signal drive")
		return
	var menu_coordinator = playable.get_menu_coordinator_for_validation()
	if menu_coordinator == null or not is_instance_valid(menu_coordinator):
		_fail("menu_coordinator missing before quit-signal drive")
		return
	_quit_signal_received = false
	var cb := func(): _quit_signal_received = true
	playable.return_to_title_requested.connect(cb)
	# Drive the REAL producer chain instead of self-emitting the signal:
	# open the live pause menu, focus "quit_main", and confirm it through
	# the coordinator's real dispatch. _confirm_current_item's pause_menu
	# arm emits quit_requested, which playable._on_ui_quit_requested (wired
	# at boot) turns into return_to_title_requested -- the exact chain
	# "Quit to Main Menu" drives during real play.
	menu_coordinator.menu_state.open_menu("pause_menu")
	if menu_coordinator.get_current_menu() != "pause_menu":
		_fail("pause_menu did not open before quit-signal drive")
		return
	var items: Array = menu_coordinator.menu_state.get_items("pause_menu")
	var quit_main_index: int = -1
	for i in range(items.size()):
		if str((items[i] as Dictionary).get("id", "")) == "quit_main":
			quit_main_index = i
			break
	if quit_main_index < 0:
		_fail("quit_main item not found in pause_menu catalog")
		return
	menu_coordinator.menu_state.set_focus_index(quit_main_index)
	menu_coordinator._confirm_current_item()
	if not _quit_signal_received:
		_fail("return_to_title_requested did not fire via real pause-menu quit_main dispatch")
		return
	finished = true
	print("TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true")
	_cleanup_and_quit(0)

func _wipe_saves() -> void:
	var service := SaveLoadServiceScript.new()
	service.delete_current_run()
	var resolver := PermadeathResolverScript.new()
	resolver.clear_death("world")

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("TITLE SCREEN FLOW FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	_wipe_saves()
	if title_node != null and is_instance_valid(title_node):
		title_node.queue_free()
	call_deferred("_do_quit", code)

func _do_quit(code: int) -> void:
	quit(code)
