extends Node

## ADR-0043 title screen bootstrap. project.godot run/main_scene points
## here; scripts/main.gd / scenes/main.tscn stay byte-identical so every
## existing main-scene smoke (which preloads res://scenes/main.tscn
## directly) is unaffected. This node instantiates scenes/main.tscn
## itself, lazily, only on New Game / Continue.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
const MenuPanelScript := preload("res://scripts/ui/menu_panel.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")
const SettingsStateScript := preload("res://scripts/systems/settings_state.gd")

var menu_state
var menu_panel
var main_node: Node = null
var playable_instance: PlayableGeneratedShip = null
var _save_load_service = null
var _resolver = null

## Title's own SettingsState (spec 3.7) — mirrors menu_coordinator's settings_menu
## handling so the title screen's Settings item is fully functional before any
## gameplay session exists. `_settings_dirty` gates the handoff into a live
## session so an untouched title never clobbers a loaded run's settings.
var settings_state = SettingsStateScript.new()
var _settings_dirty: bool = false
var _presets: Array = []

func _ready() -> void:
	_save_load_service = SaveLoadServiceScript.new()
	_resolver = PermadeathResolverScript.new()
	_build_title_ui()

func _build_title_ui() -> void:
	menu_state = MenuStateScript.new()
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/menu_definitions.json"))
	if typeof(catalog) != TYPE_DICTIONARY or not menu_state.configure(catalog as Dictionary):
		push_error("TitleMain: failed to configure MenuState from menu_definitions.json")
		return
	var presets_catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/accessibility_presets.json"))
	if typeof(presets_catalog) == TYPE_DICTIONARY:
		_presets = ((presets_catalog as Dictionary).get("presets", []) as Array).duplicate(true)
	menu_panel = MenuPanelScript.new()
	menu_panel.name = "TitleMenuPanel"
	add_child(menu_panel)
	menu_state.menu_changed.connect(_on_menu_changed)
	menu_state.focus_changed.connect(_on_focus_changed)
	_refresh_continue_enabled()
	menu_state.open_menu("main_menu")
	_refresh_panel()

func _refresh_continue_enabled() -> void:
	var available: bool = TitleSaveQueryScript.is_continue_available(_save_load_service, _resolver)
	menu_state.set_item_enabled("main_menu", "continue", available)

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(main_node):
		return  # gameplay owns input once it exists
	if menu_state.get_current_menu() == "settings_menu":
		if event.is_action_pressed("ui_left"):
			_cycle_setting(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_cycle_setting(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			menu_state.navigate(0, 1)
			_refresh_panel()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			menu_state.navigate(0, -1)
			_refresh_panel()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			menu_state.close_top()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		menu_state.navigate(0, 1)
		_refresh_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		menu_state.navigate(0, -1)
		_refresh_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()

func _confirm() -> void:
	var current_menu: String = menu_state.get_current_menu()
	var item_id: String = menu_state.confirm()
	if item_id.is_empty():
		return
	if current_menu == "settings_menu":
		if item_id == "back":
			menu_state.close_top()
		else:
			_cycle_setting(1)
		return
	match item_id:
		"start": _on_title_start()
		"continue": _on_title_continue()
		"settings": menu_state.open_menu("settings_menu")
		"quit": _on_title_quit()

func _on_title_start() -> void:
	_instantiate_gameplay(false)

func _on_title_continue() -> void:
	_instantiate_gameplay(true)

func _instantiate_gameplay(should_load: bool) -> void:
	main_node = MAIN_SCENE.instantiate()
	add_child(main_node)
	if is_instance_valid(menu_panel):
		menu_panel.visible = false
	_poll_for_playable_started(should_load)

func _poll_for_playable_started(should_load: bool) -> void:
	if not is_instance_valid(main_node):
		return
	playable_instance = main_node.playable_instance
	if not is_instance_valid(playable_instance) or not playable_instance.playable_started:
		call_deferred("_poll_for_playable_started", should_load)
		return
	# ADR-0043 (Task 5): PlayableGeneratedShip now declares
	# `return_to_title_requested`. has_signal + is_connected guards keep this
	# idempotent across repeated polls and any future re-entry, in case the
	# signal fires twice or _poll_for_playable_started runs again.
	if playable_instance.has_signal("return_to_title_requested") \
			and not playable_instance.return_to_title_requested.is_connected(_on_gameplay_return_to_title):
		playable_instance.return_to_title_requested.connect(_on_gameplay_return_to_title)
	if should_load:
		playable_instance.request_load()
	# Dirty-flag handoff (spec 3.7): only push title-local settings into the fresh
	# session when the player actually touched them at the title screen — otherwise
	# an untouched title would clobber whatever request_load() just restored.
	if _settings_dirty:
		playable_instance.apply_ui_settings_summary(settings_state.get_summary())
		# Codex round 2 finding B: the handoff consumed the edit -- clear the flag so
		# a LATER Continue in the same process (after in-game settings changes were
		# saved) does not re-push this stale title-local summary over a freshly
		# loaded run's settings. settings_state's values are left as last shown;
		# only the dirty flag resets.
		_settings_dirty = false
	# Codex round 2 finding A: the child PlayableGeneratedShip's _build_runtime_nodes
	# parks its own boot-time main_menu open (menu_coordinator.open_main_menu()) --
	# a pre-title-era overlay that is redundant here because the title screen already
	# collected New Game / Continue intent. Left open it would keep capturing input
	# (menu_coordinator.handle_ui_input) and strand the player on a second menu
	# instead of gameplay. Dismiss it through the same seam the in-scene "start"
	# confirm uses (menu_state.close_all()).
	playable_instance.dismiss_boot_menu()

func _on_title_quit() -> void:
	get_tree().quit()

func _on_gameplay_return_to_title() -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	main_node = null
	playable_instance = null
	if menu_panel != null and is_instance_valid(menu_panel):
		menu_panel.queue_free()
	menu_panel = null
	_build_title_ui()

func _on_menu_changed(_new_menu_id: String, _previous_menu_id: String) -> void:
	_refresh_panel()

func _on_focus_changed(_new_index: int) -> void:
	_refresh_panel()

func _refresh_panel() -> void:
	if not is_instance_valid(menu_panel) or menu_state == null:
		return
	var current_menu: String = menu_state.get_current_menu()
	if current_menu.is_empty():
		menu_panel.visible = false
		return
	menu_panel.visible = true
	var lines := PackedStringArray()
	var items: Array = menu_state.get_items(current_menu)
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var item_id: String = str(item.get("id", ""))
		var label_text: String = str(item.get("label", item_id))
		if current_menu == "settings_menu":
			label_text = _settings_line(item_id, label_text)
		var prefix: String = "> " if index == menu_state.get_focus_index() else "  "
		var enabled_suffix: String = "" if menu_state.is_item_enabled(current_menu, item_id) else " (disabled)"
		lines.append(prefix + label_text + enabled_suffix)
	menu_panel.set_content("The Synaptic Sea", lines)

## Title-local mirror of `menu_coordinator._cycle_setting` (same ids/setters/enum
## arrays/preset walk) against the title's own `settings_state`. Skips
## `apply_to_accessibility` (no AccessibilitySettings exists at the title screen)
## and `settings_changed.emit` (no consumer at the title screen).
func _cycle_setting(direction: int) -> void:
	if menu_state.get_current_menu() != "settings_menu":
		return
	var focused: Dictionary = menu_state.get_focused_item()
	var item_id: String = str(focused.get("id", ""))
	if item_id.is_empty() or item_id == "back":
		return
	match item_id:
		"preset": _cycle_preset(direction)
		"text_scale": _cycle_text_scale(direction)
		"colorblind": _cycle_array_setting("colorblind_mode", ["none", "protanopia", "deuteranopia", "tritanopia"], settings_state.get_colorblind_mode(), direction)
		"motion_reduce": settings_state.set_motion_reduce(not settings_state.is_motion_reduce())
		"captions": settings_state.set_captions_enabled(not settings_state.is_captions_enabled())
		"hold_to_tap": settings_state.set_hold_to_tap(not settings_state.is_hold_to_tap())
		"difficulty": _cycle_array_setting("difficulty", ["standard", "hardened", "deep_dive"], settings_state.get_difficulty(), direction)
		"glyph_scheme": _cycle_array_setting("glyph_scheme", ["auto", "keyboard", "gamepad_xbox", "gamepad_ps"], settings_state.get_glyph_scheme(), direction)
	_settings_dirty = true
	_refresh_panel()

func _cycle_preset(direction: int) -> void:
	if _presets.is_empty():
		return
	var ids: Array = []
	for preset in _presets:
		ids.append(str((preset as Dictionary).get("id", "default")))
	var current: String = settings_state.get_preset_id()
	var index: int = ids.find(current)
	if index < 0:
		index = 0
	index = wrapi(index + direction, 0, ids.size())
	settings_state.apply_preset_dict(_presets[index])

func _cycle_text_scale(direction: int) -> void:
	var scales: Array[float] = [1.0, 1.5, 2.0]
	var current: float = settings_state.get_text_scale()
	var index: int = 0
	for idx in range(scales.size()):
		if is_equal_approx(scales[idx], current):
			index = idx
			break
	index = wrapi(index + direction, 0, scales.size())
	settings_state.set_text_scale(scales[index])

func _cycle_array_setting(field: String, values: Array, current: String, direction: int) -> void:
	var index: int = values.find(current)
	if index < 0:
		index = 0
	index = wrapi(index + direction, 0, values.size())
	match field:
		"colorblind_mode": settings_state.set_colorblind_mode(str(values[index]))
		"difficulty": settings_state.set_difficulty(str(values[index]))
		"glyph_scheme": settings_state.set_glyph_scheme(str(values[index]))

## Title-local mirror of `menu_coordinator._settings_line`, EXCEPT the difficulty
## row renders plain "Difficulty: <value>" (no multiplier suffix — that needs
## AccessibilitySettings, which does not exist at the title screen).
func _settings_line(item_id: String, base_label: String) -> String:
	match item_id:
		"preset": return "%s: %s" % [base_label, settings_state.get_preset_id()]
		"text_scale": return "%s: %.1fx" % [base_label, settings_state.get_text_scale()]
		"colorblind": return "%s: %s" % [base_label, settings_state.get_colorblind_mode()]
		"motion_reduce": return "%s: %s" % [base_label, "On" if settings_state.is_motion_reduce() else "Off"]
		"captions": return "%s: %s" % [base_label, "On" if settings_state.is_captions_enabled() else "Off"]
		"hold_to_tap": return "%s: %s" % [base_label, "On" if settings_state.is_hold_to_tap() else "Off"]
		"difficulty": return "%s: %s" % [base_label, settings_state.get_difficulty()]
		"glyph_scheme": return "%s: %s" % [base_label, settings_state.get_glyph_scheme()]
	return base_label
