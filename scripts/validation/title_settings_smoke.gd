extends SceneTree

## Task 4b (Domain 8, spec 3.7) title settings sub-flow smoke: boots
## scenes/title_main.tscn, drives the title-local Settings sub-flow (open,
## cycle text_scale + captions, back), then starts a New Game and confirms
## the dirty-flag handoff applied the title's SettingsState into the live
## session's MenuCoordinator.
##
## Pass marker:
##   TITLE SETTINGS PASS open=true cycle=true back=true applied=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TIMEOUT_FRAMES: int = 240

var title_node: Node = null
var frame_count: int = 0
var finished: bool = false
var phase: int = 0
var _expect_captions: bool = false

func _initialize() -> void:
	_wipe()
	title_node = TITLE_SCENE.instantiate()
	if title_node == null:
		_fail("could not instantiate title_main scene")
		return
	get_root().add_child(title_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if title_node == null or not is_instance_valid(title_node):
		_fail("title_node missing")
		return
	if title_node.menu_state == null or title_node.menu_panel == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("title UI never built")
		return

	match phase:
		0:
			# Focus the "settings" item on main_menu and confirm into settings_menu.
			var items: Array = title_node.menu_state.get_items("main_menu")
			var settings_index: int = -1
			for i in range(items.size()):
				if str((items[i] as Dictionary).get("id", "")) == "settings":
					settings_index = i
					break
			if settings_index < 0:
				_fail("settings item not found in main_menu")
				return
			title_node.menu_state.set_focus_index(settings_index)
			title_node._confirm()
			if title_node.menu_state.get_current_menu() != "settings_menu":
				_fail("confirming settings did not open settings_menu")
				return
			phase = 1
		1:
			# Focus text_scale, cycle it to 1.5, assert state + rendered panel text.
			var settings_items: Array = title_node.menu_state.get_items("settings_menu")
			var text_scale_index: int = -1
			for i in range(settings_items.size()):
				if str((settings_items[i] as Dictionary).get("id", "")) == "text_scale":
					text_scale_index = i
					break
			if text_scale_index < 0:
				_fail("text_scale item not found in settings_menu")
				return
			title_node.menu_state.set_focus_index(text_scale_index)
			title_node._cycle_setting(1)
			if not is_equal_approx(title_node.settings_state.get_text_scale(), 1.5):
				_fail("text_scale did not cycle to 1.5 (got %s)" % str(title_node.settings_state.get_text_scale()))
				return
			var panel_text: String = title_node.menu_panel.body_label.text
			if panel_text.find("1.5") == -1:
				_fail("rendered panel text missing '1.5': %s" % panel_text)
				return
			if not title_node._settings_dirty:
				_fail("_settings_dirty not set after cycling text_scale")
				return
			# Toggle captions and assert the flip.
			var captions_index: int = -1
			for i in range(settings_items.size()):
				if str((settings_items[i] as Dictionary).get("id", "")) == "captions":
					captions_index = i
					break
			if captions_index < 0:
				_fail("captions item not found in settings_menu")
				return
			var captions_before: bool = title_node.settings_state.is_captions_enabled()
			title_node.menu_state.set_focus_index(captions_index)
			title_node._cycle_setting(1)
			if title_node.settings_state.is_captions_enabled() == captions_before:
				_fail("captions did not flip")
				return
			_expect_captions = title_node.settings_state.is_captions_enabled()
			phase = 2
		2:
			# Confirm "back" -> returns to main_menu.
			var settings_items2: Array = title_node.menu_state.get_items("settings_menu")
			var back_index: int = -1
			for i in range(settings_items2.size()):
				if str((settings_items2[i] as Dictionary).get("id", "")) == "back":
					back_index = i
					break
			if back_index < 0:
				_fail("back item not found in settings_menu")
				return
			title_node.menu_state.set_focus_index(back_index)
			title_node._confirm()
			if title_node.menu_state.get_current_menu() != "main_menu":
				_fail("back did not return to main_menu")
				return
			phase = 3
		3:
			# Confirm "start" -> New Game.
			var main_items: Array = title_node.menu_state.get_items("main_menu")
			var start_index: int = -1
			for i in range(main_items.size()):
				if str((main_items[i] as Dictionary).get("id", "")) == "start":
					start_index = i
					break
			if start_index < 0:
				_fail("start item not found in main_menu")
				return
			title_node.menu_state.set_focus_index(start_index)
			title_node._confirm()
			phase = 4
		4:
			if title_node.playable_instance == null or not title_node.playable_instance.playable_started:
				if frame_count > TIMEOUT_FRAMES:
					_fail("playable_instance never reached playable_started")
				return
			var ui = title_node.playable_instance.get_menu_coordinator_for_validation()
			if ui == null:
				_fail("menu coordinator missing on playable_instance")
				return
			var summary: Dictionary = ui.get_settings_summary()
			if not is_equal_approx(float(summary.get("text_scale", 0.0)), 1.5):
				_fail("applied text_scale mismatch: %s" % str(summary.get("text_scale")))
				return
			if bool(summary.get("captions", not _expect_captions)) != _expect_captions:
				_fail("applied captions mismatch: %s (expected %s)" % [str(summary.get("captions")), str(_expect_captions)])
				return
			# Codex round 2 finding B: the dirty-flag handoff must consume the
			# edit -- _settings_dirty should be false immediately after
			# apply_ui_settings_summary() ran, so a LATER Continue in this
			# same process (after in-game settings were changed and saved)
			# does not re-push this stale title-local summary over a freshly
			# loaded run's settings.
			if title_node._settings_dirty:
				_fail("_settings_dirty still true after New Game handoff consumed it")
				return
			finished = true
			print("TITLE SETTINGS PASS open=true cycle=true back=true applied=true")
			_cleanup()
			_wipe()
			quit(0)

func _cleanup() -> void:
	if is_instance_valid(title_node):
		title_node.queue_free()

func _wipe() -> void:
	var service := SaveLoadServiceScript.new()
	var resolver := PermadeathResolverScript.new()
	service.delete_current_run()
	resolver.clear_death("world")

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("TITLE SETTINGS FAIL %s" % reason)
	_cleanup()
	_wipe()
	quit(1)
