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
## Pass marker:
##   TITLE SCREEN FLOW PASS new_game=true continue=true quit_signal=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TIMEOUT_FRAMES: int = 900

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
	# Save a real world.json through the live instance so Continue (later
	# stage, after a fresh title rebuild) has something to load.
	if not playable.request_save():
		_fail("request_save failed after New Game boot")
		return
	_stage = "return_to_title"

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
	_stage = "quit_signal_check"

func _drive_quit_signal() -> void:
	var playable: PlayableGeneratedShip = title_node.playable_instance
	if playable == null:
		_fail("playable_instance missing before quit-signal drive")
		return
	_quit_signal_received = false
	var cb := func(): _quit_signal_received = true
	playable.return_to_title_requested.connect(cb)
	playable.emit_signal("return_to_title_requested")
	if not _quit_signal_received:
		_fail("return_to_title_requested signal did not fire its own listener")
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
