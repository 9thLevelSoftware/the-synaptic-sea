extends Control
class_name MenuCoordinator

signal modal_opened(menu_id: String)
signal modal_closed(previous_menu_id: String)
signal save_requested
signal load_requested
signal quit_requested
signal settings_changed(summary: Dictionary)

const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
const SettingsStateScript := preload("res://scripts/systems/settings_state.gd")
const TutorialStateScript := preload("res://scripts/systems/tutorial_state.gd")
const TooltipPresenterScript := preload("res://scripts/systems/tooltip_presenter.gd")
const MapFogStateScript := preload("res://scripts/systems/map_fog_state.gd")
const ControllerGlyphStateScript := preload("res://scripts/systems/controller_glyph_state.gd")
const MenuPanelScript := preload("res://scripts/ui/menu_panel.gd")
const CodexPanelScript := preload("res://scripts/ui/codex_panel.gd")
const MinimapPanelScript := preload("res://scripts/ui/minimap_panel.gd")
const HotbarPanelScript := preload("res://scripts/ui/hotbar_panel.gd")
const TooltipPanelScript := preload("res://scripts/ui/tooltip_panel.gd")
const TutorialOverlayPanelScript := preload("res://scripts/ui/tutorial_overlay_panel.gd")

var accessibility_settings: RefCounted = null
var menu_state = MenuStateScript.new()
var settings_state = SettingsStateScript.new()
var tutorial_state = TutorialStateScript.new()
var tooltip_presenter = TooltipPresenterScript.new()
var map_fog_state = MapFogStateScript.new()
var controller_glyph_state = ControllerGlyphStateScript.new()

var menu_panel
var codex_panel
var minimap_panel
var hotbar_panel
var tooltip_panel
var tutorial_overlay_panel

var _menu_catalog: Dictionary = {}
var _codex_entries: Dictionary = {}
var _presets: Array = []
var _load_available: bool = false
var _inventory_item_ids: Array = []
var _hotbar_slot_labels: Array = []
var _selected_hotbar_index: int = 0
var _last_closed_menu: String = ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel = MenuPanelScript.new()
	menu_panel.name = "MenuPanel"
	add_child(menu_panel)
	codex_panel = CodexPanelScript.new()
	codex_panel.name = "CodexPanel"
	add_child(codex_panel)
	minimap_panel = MinimapPanelScript.new()
	minimap_panel.name = "MinimapPanel"
	add_child(minimap_panel)
	hotbar_panel = HotbarPanelScript.new()
	hotbar_panel.name = "HotbarPanel"
	add_child(hotbar_panel)
	tooltip_panel = TooltipPanelScript.new()
	tooltip_panel.name = "TooltipPanel"
	add_child(tooltip_panel)
	tutorial_overlay_panel = TutorialOverlayPanelScript.new()
	tutorial_overlay_panel.name = "TutorialOverlayPanel"
	add_child(tutorial_overlay_panel)
	menu_state.menu_changed.connect(_on_menu_changed)
	tutorial_state.triggered.connect(_on_tutorial_triggered)
	tutorial_state.dismissed.connect(_on_tutorial_dismissed)
	tutorial_state.codex_unlocked.connect(_on_codex_unlocked)
	tooltip_presenter.payload_changed.connect(_on_payload_changed)
	_apply_accessibility_to_children()
	_refresh_all()

func configure(menu_catalog: Dictionary, tutorial_catalog: Dictionary, codex_catalog: Dictionary, glyph_table: Dictionary, tooltip_catalog: Dictionary, presets_catalog: Dictionary, bindings_table: Dictionary, a11y: RefCounted) -> bool:
	accessibility_settings = a11y
	_menu_catalog = menu_catalog.duplicate(true)
	_codex_entries.clear()
	for entry in (codex_catalog.get("entries", []) as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			var entry_dict: Dictionary = entry
			_codex_entries[str(entry_dict.get("id", ""))] = entry_dict.duplicate(true)
	_presets = (presets_catalog.get("presets", []) as Array).duplicate(true)
	var ok: bool = true
	ok = menu_state.configure(menu_catalog) and ok
	ok = tutorial_state.configure(tutorial_catalog) and ok
	ok = controller_glyph_state.configure(glyph_table, bindings_table) and ok
	ok = tooltip_presenter.configure(tooltip_catalog) and ok
	_apply_accessibility_to_children()
	set_load_available(_load_available)
	_refresh_all()
	return ok

func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	_apply_accessibility_to_children()
	_refresh_all()

func handle_ui_input(event: InputEvent) -> bool:
	if event == null:
		return false
	if event.is_action_pressed("ui_pause"):
		if menu_state.is_in_play():
			menu_state.open_menu("pause_menu")
		else:
			menu_state.close_all()
		return true
	if event.is_action_pressed("ui_open_codex"):
		if menu_state.is_in_play():
			menu_state.open_menu("codex")
		else:
			menu_state.open_menu("codex")
		return true
	if event.is_action_pressed("ui_open_map"):
		minimap_panel.visible = not minimap_panel.visible
		return true
	if menu_state.is_in_play():
		return false
	if event.is_action_pressed("ui_down"):
		menu_state.navigate(0, 1)
		_refresh_menu_panel()
		return true
	if event.is_action_pressed("ui_up"):
		menu_state.navigate(0, -1)
		_refresh_menu_panel()
		return true
	if event.is_action_pressed("ui_left"):
		_cycle_setting(-1)
		return true
	if event.is_action_pressed("ui_right"):
		_cycle_setting(1)
		return true
	if event.is_action_pressed("ui_accept"):
		_confirm_current_item()
		return true
	if event.is_action_pressed("ui_cancel"):
		if menu_state.get_current_menu() == "codex":
			menu_state.close_top()
		else:
			menu_state.cancel()
		_refresh_all()
		return true
	return false

func set_load_available(value: bool) -> void:
	_load_available = value
	if menu_state.has_item("main_menu", "continue"):
		menu_state.set_item_enabled("main_menu", "continue", value)
	_refresh_menu_panel()

func configure_map(room_payload: Dictionary) -> bool:
	var ok: bool = map_fog_state.configure_for_rooms(room_payload)
	_refresh_minimap()
	return ok

func track_room(room_id: String) -> bool:
	if room_id.is_empty() or not map_fog_state.is_known_room(room_id):
		return false
	var ok: bool = map_fog_state.track(room_id)
	_refresh_minimap()
	return ok

func reveal_room(room_id: String) -> bool:
	if room_id.is_empty() or not map_fog_state.is_known_room(room_id):
		return false
	var ok: bool = map_fog_state.reveal(room_id)
	_refresh_minimap()
	return ok

func set_inventory_items(item_ids: Array, selected_index: int = 0) -> void:
	_inventory_item_ids = item_ids.duplicate()
	_selected_hotbar_index = clampi(selected_index, 0, max(0, _inventory_item_ids.size() - 1))
	_refresh_hotbar()

func set_hotbar_slots(slot_labels: Array, selected_index: int = 0) -> void:
	_hotbar_slot_labels = slot_labels.duplicate()
	_selected_hotbar_index = clampi(selected_index, 0, max(0, _hotbar_slot_labels.size() - 1))
	_refresh_hotbar()

func set_tooltip_query(query: Dictionary) -> void:
	tooltip_presenter.resolve(query)

func trigger_tutorial(event_id: String, target_id: String = "any") -> String:
	var tutorial_id: String = tutorial_state.trigger(event_id, target_id)
	_refresh_codex()
	return tutorial_id

func dismiss_latest_tutorial() -> bool:
	var latest: String = tutorial_state.get_latest_tutorial_id()
	if latest.is_empty():
		return false
	return tutorial_state.dismiss(latest)

func open_main_menu() -> void:
	menu_state.open_menu("main_menu")
	_refresh_all()

func get_current_menu() -> String:
	return menu_state.get_current_menu()

func get_focus_index() -> int:
	return menu_state.get_focus_index()

func get_settings_summary() -> Dictionary:
	return settings_state.get_summary()

func apply_settings_summary(summary: Dictionary) -> bool:
	var ok: bool = settings_state.apply_summary(summary)
	if ok and accessibility_settings != null:
		settings_state.apply_to_accessibility(accessibility_settings)
		_apply_accessibility_to_children()
		settings_changed.emit(settings_state.get_summary())
	_refresh_all()
	return ok

func get_codex_unlocked_ids() -> Array:
	return tutorial_state.get_unlocked_codex_ids()

func get_hotbar_text() -> String:
	return hotbar_panel.label.text if hotbar_panel != null and hotbar_panel.label != null else ""

func get_menu_text() -> String:
	return menu_panel.body_label.text if menu_panel != null and menu_panel.body_label != null else ""

func get_minimap_text() -> String:
	return minimap_panel.label.text if minimap_panel != null and minimap_panel.label != null else ""

func get_tutorial_text() -> String:
	return tutorial_overlay_panel.label.text if tutorial_overlay_panel != null and tutorial_overlay_panel.label != null else ""

func get_tooltip_panel_text() -> String:
	return tooltip_panel.label.text if tooltip_panel != null and tooltip_panel.label != null else ""

func _confirm_current_item() -> void:
	var current_menu: String = menu_state.get_current_menu()
	var item_id: String = menu_state.confirm()
	if item_id.is_empty():
		return
	match current_menu:
		"main_menu":
			match item_id:
				"start": menu_state.close_all()
				"continue": load_requested.emit()
				"settings": menu_state.open_menu("settings_menu")
				"quit": quit_requested.emit()
		"pause_menu":
			match item_id:
				"resume": menu_state.close_all()
				"settings": menu_state.open_menu("settings_menu")
				"codex": menu_state.open_menu("codex")
				"save": save_requested.emit()
				"quit_main": quit_requested.emit()
		"settings_menu":
			if item_id == "back":
				menu_state.close_top()
			else:
				_cycle_setting(1)
		"codex":
			if item_id == "back":
				menu_state.close_top()
	_refresh_all()

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
	if accessibility_settings != null:
		settings_state.apply_to_accessibility(accessibility_settings)
	_apply_accessibility_to_children()
	settings_changed.emit(settings_state.get_summary())
	_refresh_all()

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

func _apply_accessibility_to_children() -> void:
	if accessibility_settings == null:
		return
	for child in [menu_panel, codex_panel, minimap_panel, hotbar_panel, tooltip_panel, tutorial_overlay_panel]:
		if child != null and child.has_method("apply_accessibility_settings"):
			child.apply_accessibility_settings(accessibility_settings)

func _refresh_all() -> void:
	_refresh_menu_panel()
	_refresh_codex()
	_refresh_minimap()
	_refresh_hotbar()
	_refresh_tutorial()

func _refresh_menu_panel() -> void:
	if menu_panel == null:
		return
	var current_menu: String = menu_state.get_current_menu()
	menu_panel.visible = not current_menu.is_empty() and current_menu != "codex"
	if not menu_panel.visible:
		return
	var title: String = current_menu.capitalize()
	for menu_entry in (_menu_catalog.get("menus", []) as Array):
		var menu_dict: Dictionary = menu_entry
		if str(menu_dict.get("id", "")) == current_menu:
			title = str(menu_dict.get("title", title))
			break
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
	menu_panel.set_content(title, lines)

func _settings_line(item_id: String, base_label: String) -> String:
	match item_id:
		"preset": return "%s: %s" % [base_label, settings_state.get_preset_id()]
		"text_scale": return "%s: %.1fx" % [base_label, settings_state.get_text_scale()]
		"colorblind": return "%s: %s" % [base_label, settings_state.get_colorblind_mode()]
		"motion_reduce": return "%s: %s" % [base_label, "On" if settings_state.is_motion_reduce() else "Off"]
		"captions": return "%s: %s" % [base_label, "On" if settings_state.is_captions_enabled() else "Off"]
		"hold_to_tap": return "%s: %s" % [base_label, "On" if settings_state.is_hold_to_tap() else "Off"]
		"difficulty": return "%s: %s (x%.1f)" % [base_label, settings_state.get_difficulty(), accessibility_settings.get_difficulty_multiplier() if accessibility_settings != null and accessibility_settings.has_method("get_difficulty_multiplier") else 1.0]
		"glyph_scheme": return "%s: %s" % [base_label, settings_state.get_glyph_scheme()]
	return base_label

func _refresh_codex() -> void:
	if codex_panel == null:
		return
	codex_panel.visible = menu_state.get_current_menu() == "codex"
	var lines := PackedStringArray()
	lines.append("CODEX")
	for entry_id in tutorial_state.get_unlocked_codex_ids():
		if not _codex_entries.has(entry_id):
			continue
		var entry: Dictionary = _codex_entries[entry_id]
		lines.append("- %s | %s" % [str(entry.get("topic", "Misc")), str(entry.get("title", entry_id))])
		lines.append("  %s" % str(entry.get("body", "")))
	if lines.size() == 1:
		lines.append("No unlocked entries yet.")
	codex_panel.set_entries(lines)

func _refresh_minimap() -> void:
	if minimap_panel == null:
		return
	var lines := PackedStringArray()
	lines.append("MAP")
	lines.append("Tracked: %s" % (map_fog_state.get_tracked_room_id() if not map_fog_state.get_tracked_room_id().is_empty() else "<none>"))
	lines.append("Revealed: %d" % map_fog_state.get_revealed_count())
	lines.append("Discovered: %d" % map_fog_state.get_discovered_count())
	for room_id in map_fog_state.get_room_ids().slice(0, 5):
		var state_text: String = "revealed" if map_fog_state.is_revealed(room_id) else ("seen" if map_fog_state.is_discovered(room_id) else "hidden")
		lines.append("- %s [%s]" % [room_id, state_text])
	minimap_panel.set_map_text("\n".join(lines))

func _refresh_hotbar() -> void:
	if hotbar_panel == null:
		return
	var slots: Array = []
	if not _hotbar_slot_labels.is_empty():
		for index in range(_hotbar_slot_labels.size()):
			var slot_text: String = str(_hotbar_slot_labels[index])
			var slot_prefix: String = "[%d]" % (index + 1)
			if index == _selected_hotbar_index:
				slot_prefix = ">" + slot_prefix
			slots.append("%s %s" % [slot_prefix, slot_text])
	else:
		for index in range(5):
			var text: String = "(empty)"
			if index < _inventory_item_ids.size():
				text = str(_inventory_item_ids[index])
			var prefix: String = "[%d]" % (index + 1)
			if index == _selected_hotbar_index:
				prefix = ">" + prefix
			slots.append("%s %s" % [prefix, text])
	var glyph_scheme: String = controller_glyph_state.resolve_scheme(settings_state.get_glyph_scheme())
	var use_glyph: String = controller_glyph_state.glyph_for("interact", glyph_scheme)
	hotbar_panel.visible = menu_state.is_in_play()
	hotbar_panel.set_hotbar_text("HOTBAR  %s\n%s" % [use_glyph, " | ".join(slots)])

func _refresh_tutorial() -> void:
	if tutorial_overlay_panel == null:
		return
	if tutorial_state.has_pending_banner():
		var tutorial_id: String = tutorial_state.get_latest_tutorial_id()
		tutorial_overlay_panel.show_tutorial(tutorial_state.get_title(tutorial_id), tutorial_state.get_body(tutorial_id))
	else:
		tutorial_overlay_panel.show_tutorial("", "")

func _on_menu_changed(new_menu_id: String, previous_menu_id: String) -> void:
	_last_closed_menu = previous_menu_id
	if previous_menu_id.is_empty() and not new_menu_id.is_empty():
		modal_opened.emit(new_menu_id)
	elif not previous_menu_id.is_empty() and new_menu_id.is_empty():
		modal_closed.emit(previous_menu_id)
	_refresh_all()

func _on_tutorial_triggered(_tutorial_id: String, title: String, body: String) -> void:
	tutorial_overlay_panel.show_tutorial(title, body)
	_refresh_codex()

func _on_tutorial_dismissed(_tutorial_id: String) -> void:
	_refresh_tutorial()
	_refresh_codex()

func _on_codex_unlocked(_codex_entry_id: String) -> void:
	_refresh_codex()

func _on_payload_changed(payload) -> void:
	if payload == null:
		tooltip_panel.set_payload("", "", "")
		return
	tooltip_panel.set_payload(str(payload.title), str(payload.body), str(payload.footer))
