extends Control
class_name MenuCoordinator

signal modal_opened(menu_id: String)
signal modal_closed(previous_menu_id: String)
signal save_requested
signal load_requested
signal quit_requested
signal save_and_exit_requested
signal settings_changed(summary: Dictionary)

const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
const SettingsStateScript := preload("res://scripts/systems/settings_state.gd")
const TutorialStateScript := preload("res://scripts/systems/tutorial_state.gd")
const TooltipPresenterScript := preload("res://scripts/systems/tooltip_presenter.gd")
const ControllerGlyphStateScript := preload("res://scripts/systems/controller_glyph_state.gd")
const MenuPanelScript := preload("res://scripts/ui/menu_panel.gd")
const CodexPanelScript := preload("res://scripts/ui/codex_panel.gd")
const HotbarPanelScript := preload("res://scripts/ui/hotbar_panel.gd")
const TooltipPanelScript := preload("res://scripts/ui/tooltip_panel.gd")
const TutorialOverlayPanelScript := preload("res://scripts/ui/tutorial_overlay_panel.gd")
# Bucket 3 meta screens (ADR-0038 follow-on: menu/meta-UI shell made player-reachable).
const AchievementsPanelScript := preload("res://scripts/ui/achievements_panel.gd")
const SkillTreePanelScript := preload("res://scripts/ui/skill_tree_panel.gd")
const HubUpgradePanelScript := preload("res://scripts/ui/hub_upgrade_panel.gd")
const ClassPanelScript := preload("res://scripts/ui/class_panel.gd")
const AudioLogPanelScript := preload("res://scripts/ui/audio_log_panel.gd")
const AudioSettingsPanelScript := preload("res://scripts/ui/audio_settings_panel.gd")
const LanguageSelectorScript := preload("res://scripts/ui/language_selector.gd")
const ReleaseBadgeOverlayScript := preload("res://scripts/ui/release_badge_overlay.gd")
const CreditsScreenScript := preload("res://scripts/ui/credits_screen.gd")
const PermadeathResolverScriptForCoordinator := preload("res://scripts/systems/permadeath_resolver.gd")
const SaveSlotStateScriptForCoordinator := preload("res://scripts/systems/save_slot_state.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")

## The ten records/meta screens in display order. The same ids are the menu item ids
## in `records_menu` (data/ui/menu_definitions.json) and the keys of `_meta_panels`.
const META_SCREEN_IDS: Array[String] = [
	"achievements", "skill_tree", "hub_upgrades", "class", "audio_log",
	"audio_settings", "language", "save_load", "release_badge", "credits",
]

var accessibility_settings: RefCounted = null
var menu_state = MenuStateScript.new()
var settings_state = SettingsStateScript.new()
var tutorial_state = TutorialStateScript.new()
var tooltip_presenter = TooltipPresenterScript.new()
var controller_glyph_state = ControllerGlyphStateScript.new()

var menu_panel
var codex_panel
var hotbar_panel
var tooltip_panel
var tutorial_overlay_panel

# Bucket 3 meta screens + the slot model (save_load_menu is a RefCounted presenter,
# surfaced through _save_load_panel — a plain label — since it has no Control of its own).
var achievements_panel
var skill_tree_panel
var hub_upgrade_panel
var class_panel
var audio_log_panel
var audio_settings_panel
var _audio_manager = null  # AudioManager for UI open SFX (codex/pause)
var language_selector
var release_badge_overlay
var credits_screen
var save_load_menu                       # SaveLoadMenu (RefCounted model)
var _save_load_panel: RichTextLabel
var _meta_panels: Dictionary = {}        # screen_id -> CanvasItem (visibility-toggled)
var _active_meta_screen: String = ""     # "" when the records list (or no menu) is shown
var _meta_bound: bool = false
# Domain 8 (ADR-0043): slot-screen cursor/verb state. Row index reuses the
# existing menu focus concept but the save_load screen is not a MenuState
# menu -- it is a meta-screen with its OWN cursor over SaveLoadMenu.refresh()
# rows, so it needs its own index.
var _save_load_row_index: int = 0
var _save_load_pending_verb: String = ""
var _pending_delete_slot_id: String = ""
var _snapshot_builder: Callable = Callable()
# Domain 8: last Dictionary returned by a save_load meta_screen_confirm()
# dispatched through handle_ui_input's ui_accept branch. PlayableGeneratedShip
# reads this via get_last_meta_screen_confirm_result() to notice a slot Load
# result it must apply itself (this Node owns no gameplay state).
var _last_meta_screen_confirm_result: Dictionary = {}

var _menu_catalog: Dictionary = {}
var _codex_entries: Dictionary = {}
var _presets: Array = []
var _load_available: bool = false
var _inventory_item_ids: Array = []
var _hotbar_slot_labels: Array = []
var _selected_hotbar_index: int = 0
var _last_closed_menu: String = ""

# Domain 6: model refs for interactive meta screens (set in bind_meta_screens).
var _hub_upgrade_state = null
var _skill_tree_state = null
var _meta_progression_state = null
var _player_progression = null
var _unlock_registry = null
# Tranche 6 (REQ-RL-006): DemoScopeGate — blocks hub/meta progression
# persistence in demo builds. Null outside the playable coordinator wiring.
var _demo_scope_gate = null
# PR #68 review (Codex P2 #2): the playable's _demo_save_refused predicate —
# the slot screen's Save verb must honor the SAME demo play-time refusal as
# request_save()/autosaves (play time lives on the playable, not this Node).
var _demo_save_refused_cb: Callable = Callable()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_panel = MenuPanelScript.new()
	menu_panel.name = "MenuPanel"
	add_child(menu_panel)
	codex_panel = CodexPanelScript.new()
	codex_panel.name = "CodexPanel"
	add_child(codex_panel)
	hotbar_panel = HotbarPanelScript.new()
	hotbar_panel.name = "HotbarPanel"
	add_child(hotbar_panel)
	tooltip_panel = TooltipPanelScript.new()
	tooltip_panel.name = "TooltipPanel"
	add_child(tooltip_panel)
	tutorial_overlay_panel = TutorialOverlayPanelScript.new()
	tutorial_overlay_panel.name = "TutorialOverlayPanel"
	add_child(tutorial_overlay_panel)
	_build_meta_screens()
	menu_state.menu_changed.connect(_on_menu_changed)
	# Session 3 (audit): enabled_changed was emitted by set_item_enabled but
	# connected nowhere — enable/disable only rendered if the caller happened
	# to hand-refresh. The renderer now follows the model signal.
	menu_state.enabled_changed.connect(_on_item_enabled_changed)
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
			_emit_menu_open_sfx()
		else:
			menu_state.close_all()
			_emit_menu_close_sfx()
		return true
	if event.is_action_pressed("ui_open_codex"):
		menu_state.open_menu("codex")
		_emit_menu_open_sfx()
		return true
	if menu_state.is_in_play():
		return false
	# While a meta screen is displayed it owns the input: cancel returns to the records
	# list. Swallow ONLY the menu-list navigation/accept actions so the list behind the
	# screen doesn't move — but let every other event (mouse clicks, slider drags, key
	# typing) fall through (return false) so the visible screen's own Controls (the
	# Language OptionButton, Audio Settings sliders, Audio Log ItemList) stay operable.
	if not _active_meta_screen.is_empty():
		if event.is_action_pressed("ui_cancel"):
			var active_meta_node = _active_meta_screen_node()
			if is_instance_valid(active_meta_node) and active_meta_node.has_method("dismiss"):
				active_meta_node.dismiss()
			else:
				_close_meta_screen()
			return true
		if _active_meta_screen in ["hub_upgrades", "skill_tree", "class", "save_load"]:
			if event.is_action_pressed("ui_up"):
				meta_screen_move_selection(-1)
				return true
			if event.is_action_pressed("ui_down"):
				meta_screen_move_selection(1)
				return true
			if event.is_action_pressed("ui_accept"):
				_last_meta_screen_confirm_result = meta_screen_confirm()
				return true
			if _active_meta_screen == "save_load":
				if event.is_action_pressed("ui_left"):
					_cycle_save_load_verb(-1)
					return true
				if event.is_action_pressed("ui_right"):
					_cycle_save_load_verb(1)
					return true
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			return true
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

func set_inventory_items(item_ids: Array, selected_index: int = 0) -> void:
	_inventory_item_ids = item_ids.duplicate()
	_selected_hotbar_index = clampi(selected_index, 0, max(0, _inventory_item_ids.size() - 1))
	_refresh_hotbar()

func set_hotbar_slots(slot_labels: Array, selected_index: int = 0) -> void:
	_hotbar_slot_labels = slot_labels.duplicate()
	_selected_hotbar_index = clampi(selected_index, 0, max(0, _hotbar_slot_labels.size() - 1))
	_refresh_hotbar()

## Two gameplay pushers call this (ADR-0045): PlayableGeneratedShip's
## proximity focus (_refresh_tooltip_focus) and InventoryPanel's selection
## push (tooltip_query_push). Arbitration between them is deliberately
## absent -- whichever calls last wins, there is no priority/lock concept.
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


func _emit_menu_open_sfx() -> void:
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		_audio_manager.play_sfx(AudioEventSeamScript.UI_PANEL_OPEN)


func _emit_menu_close_sfx() -> void:
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		_audio_manager.play_sfx(AudioEventSeamScript.UI_PANEL_CLOSE)


## ADR-0043 title handoff seam: dismisses the in-scene boot-time main_menu
## _build_runtime_nodes() parks open via open_main_menu(). The title screen
## already collected the player's New Game / Continue intent, so this menu
## is redundant once the title handoff completes -- mirrors the same
## in-play transition menu_coordinator._confirm_current_item()'s main_menu
## "start" arm drives (menu_state.close_all()) when the game is NOT booted
## through the title screen. Idempotent: closing an already-closed menu
## stack is a no-op in MenuState.
func dismiss_boot_menu() -> bool:
	return menu_state.close_all()

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
				"start":
					menu_state.close_all()
					_emit_menu_close_sfx()
				"continue": load_requested.emit()
				"settings":
					menu_state.open_menu("settings_menu")
					_emit_menu_open_sfx()
				"quit": quit_requested.emit()
		"pause_menu":
			match item_id:
				"resume":
					menu_state.close_all()
					_emit_menu_close_sfx()
				"settings":
					menu_state.open_menu("settings_menu")
					_emit_menu_open_sfx()
				"codex":
					menu_state.open_menu("codex")
					_emit_menu_open_sfx()
				"records":
					menu_state.open_menu("records_menu")
					_emit_menu_open_sfx()
				"save": save_requested.emit()
				"save_and_exit": save_and_exit_requested.emit()
				"quit_main": quit_requested.emit()
		"records_menu":
			if item_id == "back":
				menu_state.close_top()
				_emit_menu_close_sfx()
			else:
				_open_meta_screen(item_id)
		"settings_menu":
			if item_id == "back":
				menu_state.close_top()
				_emit_menu_close_sfx()
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

## ADR-0044 (final review Finding 1) seam: the single re-emit point handed to
## AudioSettingsPanel via set_settings_push(). Reuses the exact emit shape
## _cycle_setting() already uses (settings_changed with the current summary),
## so playable_generated_ship.gd::_on_ui_settings_changed -- the ONLY writer
## of sfx_router.captions_enabled -- picks up the panel's caption toggle the
## same way it picks up the in-game settings menu's.
func _emit_settings_changed() -> void:
	settings_changed.emit(settings_state.get_summary())

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

# --- Bucket 3 meta screens -----------------------------------------------------------

func _build_meta_screens() -> void:
	achievements_panel = AchievementsPanelScript.new()
	achievements_panel.name = "AchievementsPanel"
	add_child(achievements_panel)
	skill_tree_panel = SkillTreePanelScript.new()
	skill_tree_panel.name = "SkillTreePanel"
	add_child(skill_tree_panel)
	hub_upgrade_panel = HubUpgradePanelScript.new()
	hub_upgrade_panel.name = "HubUpgradePanel"
	add_child(hub_upgrade_panel)
	class_panel = ClassPanelScript.new()
	class_panel.name = "ClassPanel"
	add_child(class_panel)
	audio_log_panel = AudioLogPanelScript.new()
	audio_log_panel.name = "AudioLogPanel"
	add_child(audio_log_panel)
	audio_settings_panel = AudioSettingsPanelScript.new()
	audio_settings_panel.name = "AudioSettingsPanel"
	add_child(audio_settings_panel)
	language_selector = LanguageSelectorScript.new()
	language_selector.name = "LanguageSelector"
	add_child(language_selector)
	# Session 3 (audit): language_changed had zero subscribers — a language
	# pick did nothing. Record it on the coordinator and re-render.
	language_selector.language_changed.connect(_on_language_changed)
	release_badge_overlay = ReleaseBadgeOverlayScript.new()
	release_badge_overlay.name = "ReleaseBadgeOverlay"
	add_child(release_badge_overlay)
	release_badge_overlay.metadata_changed.connect(_refresh_all)
	credits_screen = CreditsScreenScript.new()
	credits_screen.name = "CreditsScreen"
	add_child(credits_screen)
	credits_screen.credits_dismissed.connect(_on_credits_dismissed)
	# save_load_menu is a RefCounted model; its rows render into this label.
	_save_load_panel = RichTextLabel.new()
	_save_load_panel.name = "SaveLoadList"
	_save_load_panel.bbcode_enabled = true
	_save_load_panel.fit_content = true
	add_child(_save_load_panel)
	_meta_panels = {
		"achievements": achievements_panel,
		"skill_tree": skill_tree_panel,
		"hub_upgrades": hub_upgrade_panel,
		"class": class_panel,
		"audio_log": audio_log_panel,
		"audio_settings": audio_settings_panel,
		"language": language_selector,
		"save_load": _save_load_panel,
		"release_badge": release_badge_overlay,
		"credits": credits_screen,
	}
	for sid in _meta_panels:
		var node = _meta_panels[sid]
		if is_instance_valid(node):
			node.visible = false

## Inject each meta screen's coordinator-owned data dependency. Idempotent; re-callable
## on a HUD rebuild. The coordinator constructs/owns every required dependency before
## calling this, so a null is a wiring bug — asserted in debug. The catalog-backed panels
## need an explicit render() after binding (their setters assign data but don't redraw).
func bind_meta_screens(p_achievement_state, p_audio_manager, p_skill_tree_state, p_player_progression, p_hub_upgrade_state, p_meta_progression_state, p_localization_catalog, p_build_metadata_state, p_save_load_menu, p_a11y, p_unlock_registry = null, p_snapshot_builder: Callable = Callable(), p_demo_scope_gate = null, p_demo_save_refused: Callable = Callable()) -> void:
	assert(p_achievement_state != null, "p_achievement_state dependency is missing")
	assert(p_audio_manager != null, "p_audio_manager dependency is missing")
	_audio_manager = p_audio_manager
	assert(p_skill_tree_state != null, "p_skill_tree_state dependency is missing")
	assert(p_player_progression != null, "p_player_progression dependency is missing")
	assert(p_hub_upgrade_state != null, "p_hub_upgrade_state dependency is missing")
	assert(p_meta_progression_state != null, "p_meta_progression_state dependency is missing")
	assert(p_localization_catalog != null, "p_localization_catalog dependency is missing")
	assert(p_build_metadata_state != null, "p_build_metadata_state dependency is missing")
	assert(p_save_load_menu != null, "p_save_load_menu dependency is missing")
	# p_a11y stays optional (its body use is null-guarded), matching the rest of the
	# coordinator, which tolerates a null accessibility_settings.
	_skill_tree_state = p_skill_tree_state
	_player_progression = p_player_progression
	_hub_upgrade_state = p_hub_upgrade_state
	_meta_progression_state = p_meta_progression_state
	_unlock_registry = p_unlock_registry
	_demo_scope_gate = p_demo_scope_gate
	_demo_save_refused_cb = p_demo_save_refused
	save_load_menu = p_save_load_menu
	# Catalog-backed panels: set data, then render() (the setters do not auto-redraw, so
	# without this the panel is visible but its RichTextLabel stays blank).
	if is_instance_valid(achievements_panel):
		achievements_panel.load_catalog()
		achievements_panel.set_state(p_achievement_state)
		achievements_panel.render()
	if is_instance_valid(skill_tree_panel):
		skill_tree_panel.set_tree(p_skill_tree_state)
		skill_tree_panel.set_progression(p_player_progression)
		skill_tree_panel.render()
	if is_instance_valid(hub_upgrade_panel):
		hub_upgrade_panel.set_catalog(p_hub_upgrade_state)
		hub_upgrade_panel.set_meta_state(p_meta_progression_state)
		hub_upgrade_panel.render()
	if is_instance_valid(class_panel):
		class_panel.load_catalog()
		class_panel.set_meta_state(p_meta_progression_state)
		if p_player_progression != null and p_player_progression.has_method("get_class_id"):
			class_panel.set_selected_class(str(p_player_progression.get_class_id()))
		class_panel.render()
	# These panels self-render in their setters (set_audio_manager / set_catalog /
	# set_metadata) or in load_catalog (credits) — no explicit render() needed.
	if is_instance_valid(audio_log_panel):
		audio_log_panel.set_audio_manager(p_audio_manager)
	if is_instance_valid(audio_settings_panel):
		audio_settings_panel.set_audio_manager(p_audio_manager)
		if p_a11y != null:
			audio_settings_panel.set_accessibility_settings(p_a11y)
		audio_settings_panel.set_settings_state(settings_state)
		# ADR-0044 (final review Finding 1): the panel must never write
		# sfx_router.captions_enabled directly. It mutates settings_state,
		# then calls this Callable to ask THIS coordinator to emit
		# settings_changed(summary) -- the same seam _cycle_setting() already
		# uses, which playable_generated_ship.gd::_on_ui_settings_changed is
		# connected to.
		audio_settings_panel.set_settings_push(_emit_settings_changed)
	if is_instance_valid(language_selector):
		language_selector.set_catalog(p_localization_catalog)
	if is_instance_valid(release_badge_overlay):
		release_badge_overlay.set_metadata(p_build_metadata_state)
	if is_instance_valid(credits_screen):
		credits_screen.load_catalog()
	_snapshot_builder = p_snapshot_builder
	_refresh_save_load_panel()
	_meta_bound = true

## Domain 6 (WI-3): the cross-run unlock registry's unlocked entries, for the
## codex/records screen. Empty when no registry is bound.
func get_registry_unlock_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _unlock_registry == null:
		return out
	for uid in _unlock_registry.get_unlocked_ids():
		out.append("- [%s] %s" % [_unlock_registry.get_category(uid), _unlock_registry.get_display_name(uid)])
	return out

func _refresh_save_load_panel() -> void:
	if not is_instance_valid(_save_load_panel):
		return
	var lines := PackedStringArray()
	lines.append("SAVE / LOAD")
	var rows: Array = _save_load_rows()
	if rows.is_empty():
		lines.append("(no save slots)")
	else:
		if _save_load_row_index >= rows.size():
			_save_load_row_index = rows.size() - 1
		if _save_load_row_index < 0:
			_save_load_row_index = 0
		for index in range(rows.size()):
			var row = rows[index]
			var prefix: String = "> " if index == _save_load_row_index else "  "
			lines.append(prefix + _save_load_row_line(row, index))
	_save_load_panel.text = "\n".join(lines)

## Normalizes SaveLoadMenu.refresh() rows (real SaveSlotState instances,
## one per slot PRESENT in the on-disk index) plus synthesized placeholder
## SaveSlotState rows for every MANUAL_SLOT_IDS entry that has no row yet
## (an empty manual slot the player has never saved to). This is required
## so the player can make their FIRST manual save from the slot screen --
## spec 3.2's "Empty manual slot (slot_01..06): [Save]" verb model demands
## a cursor-able row for empty slots, not just filled ones. save_load_menu.gd
## itself is NOT touched (spec 4: "No signature changes") -- the synthesis
## happens entirely here at the coordinator level, using the SAME
## SaveSlotState class SaveLoadMenu.refresh() already returns (a plain
## RefCounted with public vars -- scripts/systems/save_slot_state.gd), so
## every existing accessor (is_manual()/is_world()/.frozen/.display_name/
## .slot_id) behaves identically on a synthetic row as on a real one; no
## duck-typed dict and no extra guarding is needed anywhere else in this
## file. Order: real rows first (in SaveLoadMenu.refresh()'s existing
## saved_at-desc order), then one synthetic row per empty manual slot id,
## in MANUAL_SLOT_IDS order.
func _save_load_rows() -> Array:
	var rows: Array = []
	if save_load_menu != null:
		var refreshed: Variant = save_load_menu.refresh()
		if typeof(refreshed) == TYPE_ARRAY:
			rows = (refreshed as Array).duplicate()
	var present_manual_ids: Dictionary = {}
	for row in rows:
		if row != null and bool(row.is_manual()):
			present_manual_ids[String(row.slot_id)] = true
	for slot_id in SaveSlotStateScriptForCoordinator.MANUAL_SLOT_IDS:
		if not present_manual_ids.has(String(slot_id)):
			rows.append(_synthesize_empty_manual_row(String(slot_id)))
	# Review fix (Finding 2): SaveLoadService._index_run_slot never populates
	# `frozen` from a death record (permadeath is written to a separate
	# <slot_id>.death.json side-file by PermadeathResolver, not into the
	# save index), so without this overlay the slot screen can never render
	# "DEAD -- <epitaph>" or block verbs on a slot the player actually died
	# in. Overlay runtime frozen state onto every row here -- the single
	# row-list source every save/load path shares -- rather than persisting
	# it into the index (the index is disk state; death is derived at read
	# time from the resolver, same as _save_load_row_line already assumes).
	var resolver := PermadeathResolverScriptForCoordinator.new()
	for row in rows:
		if row != null:
			row.frozen = resolver.has_died_in(String(row.slot_id))
	return rows

## Builds a placeholder SaveSlotState for a manual slot id that has no
## on-disk row yet. Every field is a safe, never-frozen, empty-payload
## default so it passes through _save_load_row_line/_valid_verbs_for_row/
## the delete-arm/load-arm guards exactly like a real row would -- the
## only special-cased field is slot_kind (stamped SLOT_KIND_MANUAL so
## is_manual() reads true) and slot_id/display_name (so the row is
## identifiable and selectable).
func _synthesize_empty_manual_row(slot_id: String):
	var row = SaveSlotStateScriptForCoordinator.new()
	row.slot_id = slot_id
	row.slot_kind = SaveSlotStateScriptForCoordinator.SLOT_KIND_MANUAL
	row.display_name = ""
	row.frozen = false
	row.corrupt = false
	return row

func _save_load_row_line(row, index: int) -> String:
	if row == null:
		return "?"
	var slot_id: String = String(row.slot_id)
	var display_name: String = String(row.display_name)
	if bool(row.frozen):
		var resolver := PermadeathResolverScriptForCoordinator.new()
		var epitaph: Dictionary = resolver.load_epitaph(slot_id)
		return "%s | DEAD -- %s" % [slot_id, str(epitaph.get("epitaph", "unknown"))]
	if bool(row.is_manual()) and display_name.is_empty() and not _save_load_row_has_payload(row):
		var empty_verb_text: String = ""
		if index == _save_load_row_index and not _save_load_pending_verb.is_empty():
			empty_verb_text = " | verb=%s" % _save_load_pending_verb
		return "%s -- empty%s" % [slot_id, empty_verb_text]
	var verb_text: String = ""
	if index == _save_load_row_index and not _save_load_pending_verb.is_empty():
		verb_text = " | verb=%s" % _save_load_pending_verb
		if _pending_delete_slot_id == slot_id and _save_load_pending_verb == "Delete":
			verb_text = " | verb=Delete (confirm again to delete)"
	# A payload-bearing row should always have a display_name (SaveLoadService stamps
	# one on save), but guard against an empty one from another writer by falling back
	# to the slot_id rather than rendering "slot_03 | ".
	var shown_name: String = display_name if not display_name.is_empty() else slot_id
	# ADR-0046 slot metadata: surface location, class, objective, play time, and
	# world seed so the list is scannable without opening the payload.
	var loc: String = String(row.current_location)
	if loc.is_empty():
		loc = "?"
	var cls: String = String(row.player_class)
	if cls.is_empty():
		cls = "?"
	var obj_seq: int = int(row.objective_sequence)
	var time_txt: String = _format_play_time_seconds(float(row.play_time_seconds))
	var seed_n: int = int(row.synaptic_sea_seed)
	return "%s | %s | %s | %s | obj=%d | %s | seed=%d%s" % [
		slot_id, shown_name, loc, cls, obj_seq, time_txt, seed_n, verb_text]


## Human-readable accumulated play clock for save-slot rows (not wall-clock epoch).
func _format_play_time_seconds(seconds: float) -> String:
	var total: int = maxi(0, int(floor(seconds)))
	var h: int = int(total / 3600)
	var m: int = int((total % 3600) / 60)
	var s: int = int(total % 60)
	if h > 0:
		return "%dh%02dm" % [h, m]
	return "%dm%02ds" % [m, s]

## True when a row came from SaveLoadMenu.refresh() (a real on-disk slot)
## rather than being one of this coordinator's synthesized empty-manual
## placeholders. Synthesized rows always have saved_at_epoch == 0 AND
## schema_version == "" (a real save_to_slot call always stamps both --
## see SaveLoadService._index_run_slot); this is a safe, cheap
## distinguishing check that does not require tracking row identity.
func _save_load_row_has_payload(row) -> bool:
	return int(row.saved_at_epoch) != 0 or not String(row.schema_version).is_empty()

func _open_meta_screen(screen_id: String) -> void:
	if not _meta_panels.has(screen_id):
		return
	if screen_id == "save_load":
		# Reset the cursor + any pending verb/delete-arm state on every (re)open so a
		# stale row index from a prior visit (rows can shift under autosave rotation,
		# etc.) never carries over into this visit.
		_save_load_row_index = 0
		_save_load_pending_verb = ""
		_pending_delete_slot_id = ""
		_refresh_save_load_panel()
	_active_meta_screen = screen_id
	_refresh_all()

func _close_meta_screen() -> void:
	_active_meta_screen = ""
	_save_load_pending_verb = ""
	_pending_delete_slot_id = ""
	_refresh_all()

func _refresh_meta_screens() -> void:
	for sid in _meta_panels:
		var node = _meta_panels[sid]
		if is_instance_valid(node):
			node.visible = (sid == _active_meta_screen)

## Validation/host seam: open the records list directly.
func open_records_menu() -> void:
	menu_state.open_menu("records_menu")
	_refresh_all()

## Validation/host seam: open one meta screen (opening the records list first if needed).
func open_meta_screen(screen_id: String) -> void:
	if menu_state.get_current_menu() != "records_menu":
		menu_state.open_menu("records_menu")
	_open_meta_screen(screen_id)

func get_active_meta_screen() -> String:
	return _active_meta_screen

func _active_meta_screen_node():
	if _active_meta_screen.is_empty() or not _meta_panels.has(_active_meta_screen):
		return null
	return _meta_panels[_active_meta_screen]

## Domain 8 seam: the Dictionary returned by the last meta_screen_confirm()
## call driven through handle_ui_input's ui_accept branch. Used by
## PlayableGeneratedShip's _input dispatch to notice a slot-screen Load
## result (which this Node cannot apply itself -- it has no gameplay state).
func get_last_meta_screen_confirm_result() -> Dictionary:
	return _last_meta_screen_confirm_result

func clear_last_meta_screen_confirm_result() -> void:
	_last_meta_screen_confirm_result = {}

## Domain 6 host/input seam: move the active interactive meta screen's cursor.
func meta_screen_move_selection(direction: int) -> void:
	match _active_meta_screen:
		"hub_upgrades":
			if is_instance_valid(hub_upgrade_panel):
				hub_upgrade_panel.move_selection(direction)
				hub_upgrade_panel.render()
		"skill_tree":
			if is_instance_valid(skill_tree_panel):
				skill_tree_panel.move_selection(direction)
				skill_tree_panel.render()
		"class":
			if is_instance_valid(class_panel):
				class_panel.move_selection(direction)
				class_panel.render()
		"save_load":
			var rows: Array = _save_load_rows()
			if rows.is_empty():
				return
			_save_load_row_index = clampi(_save_load_row_index + direction, 0, rows.size() - 1)
			_save_load_pending_verb = ""
			_pending_delete_slot_id = ""
			_refresh_save_load_panel()

## Domain 6 host/input seam: confirm (purchase/unlock/select) on the active
## interactive meta screen. Returns {screen, action, ok, detail}.
func meta_screen_confirm() -> Dictionary:
	match _active_meta_screen:
		"hub_upgrades":
			# Tranche 6 (REQ-RL-006): demo builds block hub/meta progression
			# persistence entirely (manifest hub.meta_progression).
			if _demo_scope_gate != null and _demo_scope_gate.is_blocked("hub.meta_progression"):
				return {"screen": "hub_upgrades", "action": "purchase", "ok": false, "detail": "demo_blocked"}
			var sel: String = hub_upgrade_panel.get_selected_id() if is_instance_valid(hub_upgrade_panel) else ""
			var ok: bool = false
			if _hub_upgrade_state != null and _meta_progression_state != null and not sel.is_empty():
				if _hub_upgrade_state.purchase(sel, _meta_progression_state):
					ok = _meta_progression_state.save_to_disk()
			if is_instance_valid(hub_upgrade_panel):
				hub_upgrade_panel.render()
			return {"screen": "hub_upgrades", "action": "purchase", "ok": ok, "detail": sel}
		"skill_tree":
			var sel_s: String = skill_tree_panel.get_selected_id() if is_instance_valid(skill_tree_panel) else ""
			var ok_s: bool = false
			if _skill_tree_state != null and not sel_s.is_empty():
				var chk: Dictionary = _skill_tree_state.can_unlock(sel_s, _player_progression, _meta_progression_state)
				if bool(chk.get("can", false)):
					ok_s = _skill_tree_state.unlock(sel_s)
			if is_instance_valid(skill_tree_panel):
				skill_tree_panel.render()
			return {"screen": "skill_tree", "action": "unlock", "ok": ok_s, "detail": sel_s}
		"class":
			# Tranche 6 (REQ-RL-006): class selection persists via
			# meta_progression_state.save_to_disk() — same demo block.
			if _demo_scope_gate != null and _demo_scope_gate.is_blocked("hub.meta_progression"):
				return {"screen": "class", "action": "select", "ok": false, "detail": "demo_blocked"}
			var sel_c: String = class_panel.get_selected_id() if is_instance_valid(class_panel) else ""
			var ok_c: bool = false
			if _meta_progression_state != null and not sel_c.is_empty() and class_panel.is_available(sel_c):
				_meta_progression_state.set_selected_class(sel_c)
				ok_c = _meta_progression_state.save_to_disk()
				if is_instance_valid(class_panel):
					class_panel.set_selected_class(sel_c)
			if is_instance_valid(class_panel):
				class_panel.render()
			return {"screen": "class", "action": "select", "ok": ok_c, "detail": sel_c}
		"save_load":
			return _confirm_save_load_row()
	return {"screen": _active_meta_screen, "action": "none", "ok": false, "detail": ""}

## Domain 8 (ADR-0043) slot-screen confirm dispatch. Returns
## {screen:"save_load", action, ok, detail, snapshot} -- snapshot is only
## populated on a successful Load action; the RunSnapshot cannot be applied
## here (this Node has no gameplay state), so the caller (PlayableGeneratedShip's
## _input dispatch site) notices action=="load" and ok==true and calls
## apply_manual_slot(snapshot) itself (Task 8).
func _confirm_save_load_row() -> Dictionary:
	var rows: Array = _save_load_rows()
	if rows.is_empty() or _save_load_row_index >= rows.size():
		return {"screen": "save_load", "action": "none", "ok": false, "detail": ""}
	var row = rows[_save_load_row_index]
	var slot_id: String = String(row.slot_id)
	if bool(row.frozen):
		return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}
	var verbs: Array = _valid_verbs_for_row(row)
	if verbs.is_empty():
		return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}
	if _save_load_pending_verb.is_empty():
		_save_load_pending_verb = String(verbs[0])
		_refresh_save_load_panel()
		return {"screen": "save_load", "action": "arm", "ok": true, "detail": slot_id}
	var verb: String = _save_load_pending_verb
	if verb == "Delete":
		if _pending_delete_slot_id != slot_id:
			_pending_delete_slot_id = slot_id
			_refresh_save_load_panel()
			return {"screen": "save_load", "action": "delete_armed", "ok": true, "detail": slot_id}
		var deleted: bool = save_load_menu.confirm_delete(slot_id)
		_pending_delete_slot_id = ""
		_save_load_pending_verb = ""
		if deleted:
			_reanchor_save_load_row_index(slot_id)
		_refresh_save_load_panel()
		return {"screen": "save_load", "action": "delete", "ok": deleted, "detail": slot_id}
	if verb == "Save":
		# Tranche 6 / PR #68 review (Codex P2 #2): honor the demo play-time
		# save refusal here too — otherwise Records -> Save/Load bypasses the
		# cap that request_save() and the autosave loops enforce.
		if _demo_save_refused_cb.is_valid() and bool(_demo_save_refused_cb.call()):
			_save_load_pending_verb = ""
			_refresh_save_load_panel()
			return {"screen": "save_load", "action": "save", "ok": false, "detail": "demo_blocked"}
		var display_name: String = String(row.display_name) if not String(row.display_name).is_empty() else slot_id
		var ok: bool = false
		if _snapshot_builder.is_valid():
			var snap = _snapshot_builder.call()
			if snap != null:
				ok = save_load_menu.confirm_save_to_slot(slot_id, snap, "manual", display_name)
		_save_load_pending_verb = ""
		if ok:
			_reanchor_save_load_row_index(slot_id)
		_refresh_save_load_panel()
		return {"screen": "save_load", "action": "save", "ok": ok, "detail": slot_id}
	if verb == "Load":
		# Domain 8 (PR #57 Codex P2, world-row Load): the world row's on-disk
		# file (world.json) holds a WorldSnapshot, not a RunSnapshot --
		# select_slot_for_load()/load_from_slot() decode strictly as
		# RunSnapshot, so calling that path for slot_id=="world" would
		# either return null (silent no-op) or worse, misparse the
		# WorldSnapshot dict and have the corrupt-file guard quarantine a
		# perfectly good world.json. The proven world-apply path is
		# PlayableGeneratedShip.request_load() (same one F9 / title
		# Continue use), which this Node cannot call directly (no
		# gameplay state) -- so signal the caller via action=="load_world"
		# and let it dispatch request_load() itself, mirroring the
		# action=="load" contract's split of responsibility.
		if bool(row.is_world()):
			_save_load_pending_verb = ""
			_refresh_save_load_panel()
			return {"screen": "save_load", "action": "load_world", "ok": true, "detail": slot_id}
		var snapshot = save_load_menu.select_slot_for_load(slot_id)
		_save_load_pending_verb = ""
		_refresh_save_load_panel()
		return {"screen": "save_load", "action": "load", "ok": snapshot != null, "detail": slot_id, "snapshot": snapshot}
	return {"screen": "save_load", "action": "none", "ok": false, "detail": slot_id}

## Domain 8 cursor-drift fix (review finding 1): _save_load_rows() is sorted by
## saved_at DESCENDING with synthesized empty rows appended at the tail, so the
## acted-on slot's position can move after a successful Save (a fresh save jumps
## to the front of the list) or Delete (the slot's real row is replaced by a
## synthesized empty row, which lives at the tail alongside the other empty
## manual rows). Leaving _save_load_row_index as a raw, merely bounds-clamped
## int would silently land the cursor on a DIFFERENT slot, so the player's next
## ui_accept would act on the wrong row. Re-resolve the index by searching the
## REFRESHED rows for slot_id: after Save the slot's real (now-freshest) row is
## found directly; after Delete the same slot_id now appears as its synthesized
## empty row (see _save_load_rows/_synthesize_empty_manual_row) so the search
## still finds it and anchors there. If the slot_id is truly absent from the
## refreshed rows (should not happen for a manual slot id, but guard anyway),
## clamp to the nearest valid index instead of leaving a stale/out-of-range one.
func _reanchor_save_load_row_index(slot_id: String) -> void:
	var refreshed_rows: Array = _save_load_rows()
	for index in range(refreshed_rows.size()):
		var refreshed_row = refreshed_rows[index]
		if refreshed_row != null and String(refreshed_row.slot_id) == slot_id:
			_save_load_row_index = index
			return
	_save_load_row_index = clampi(_save_load_row_index, 0, max(0, refreshed_rows.size() - 1))

## Verb model per row state (spec 3.2, unconditional -- not deferrable):
## empty manual [Save] only; filled manual [Load, Save, Delete]; world row
## [Load] only; autosave rows display-only (empty array); frozen rows are
## handled before this is called. "Empty manual" is distinguished from
## "filled manual" via _save_load_row_has_payload (step 7.8's synthesized
## rows never have a saved_at_epoch/schema_version stamp; every real
## save_to_slot call always sets both).
func _valid_verbs_for_row(row) -> Array:
	if bool(row.is_world()):
		return ["Load"]
	if bool(row.is_auto()) or bool(row.is_quick()):
		return []
	if bool(row.is_manual()):
		if not _save_load_row_has_payload(row):
			# Empty manual slot (never saved to, or this is one of step 7.8's
			# synthesized placeholder rows): only Save is offered. Load/Delete
			# on a slot with no payload on disk would be meaningless/unsafe --
			# select_slot_for_load would return null and confirm_delete would
			# no-op on a missing file, so excluding them here is not just
			# cosmetic, it prevents a dead-end verb cycle.
			return ["Save"]
		# A filled manual row (real payload on disk): offer the full verb set.
		return ["Load", "Save", "Delete"]
	return []

func _cycle_save_load_verb(direction: int) -> void:
	var rows: Array = _save_load_rows()
	if rows.is_empty() or _save_load_row_index >= rows.size():
		return
	var row = rows[_save_load_row_index]
	if bool(row.frozen):
		return
	var verbs: Array = _valid_verbs_for_row(row)
	if verbs.is_empty():
		return
	var current_index: int = verbs.find(_save_load_pending_verb)
	if current_index < 0:
		# No verb armed yet: first ui_left (direction -1) lands on the LAST verb,
		# first ui_right (direction 1) lands on the FIRST verb -- previously both
		# directions landed on verbs[0], which made the first ui_left a no-op.
		current_index = verbs.size() - 1 if direction < 0 else 0
	else:
		current_index = wrapi(current_index + direction, 0, verbs.size())
	_save_load_pending_verb = String(verbs[current_index])
	_pending_delete_slot_id = ""
	_refresh_save_load_panel()

func get_meta_screen_ids() -> Array:
	return META_SCREEN_IDS.duplicate()

func get_meta_screen_panel(screen_id: String):
	return _meta_panels.get(screen_id, null)

func get_save_load_menu():
	return save_load_menu

## Per-screen "mounted + populated" check. Centralizes content knowledge so the
## reachability smoke stays generic. Returns true when the screen has live content.
func meta_screen_is_populated(screen_id: String) -> bool:
	match screen_id:
		"achievements":
			return is_instance_valid(achievements_panel) and achievements_panel.get_total_count() > 0
		"skill_tree":
			return is_instance_valid(skill_tree_panel) and skill_tree_panel.get_status_lines().size() >= 1
		"hub_upgrades":
			return is_instance_valid(hub_upgrade_panel) and hub_upgrade_panel.get_upgrade_count() > 0
		"class":
			return is_instance_valid(class_panel) and class_panel.get_class_count() > 0
		"audio_log":
			# Tranche 4 (2026-07-06 audit): require actual listed entries, not
			# just an injected manager — the old manager-only check masked the
			# permanently-empty panel (has_method-on-var bug) from the bundled
			# meta-screens reachability smoke. Mirrors the achievements case.
			return is_instance_valid(audio_log_panel) and audio_log_panel.get_entry_count() > 0
		"audio_settings":
			return is_instance_valid(audio_settings_panel) and audio_settings_panel.audio_manager != null
		"language":
			return is_instance_valid(language_selector) and language_selector.get_known_languages().size() > 0
		"save_load":
			# save_load_menu is a RefCounted model, not a node — keep the null check.
			return save_load_menu != null and typeof(save_load_menu.refresh()) == TYPE_ARRAY
		"release_badge":
			return is_instance_valid(release_badge_overlay) and not release_badge_overlay.get_badge_text().is_empty()
		"credits":
			return is_instance_valid(credits_screen) and credits_screen.get_entry_count() > 0
	return false

func _apply_accessibility_to_children() -> void:
	if accessibility_settings == null:
		return
	for child in [menu_panel, codex_panel, hotbar_panel, tooltip_panel, tutorial_overlay_panel]:
		if child != null and child.has_method("apply_accessibility_settings"):
			child.apply_accessibility_settings(accessibility_settings)

func _refresh_all() -> void:
	_refresh_menu_panel()
	_refresh_codex()
	_refresh_hotbar()
	_refresh_tutorial()
	_refresh_meta_screens()

func _refresh_menu_panel() -> void:
	if menu_panel == null:
		return
	var current_menu: String = menu_state.get_current_menu()
	# Hidden for the codex (its own panel) and while a meta screen overlays the records list.
	menu_panel.visible = not current_menu.is_empty() and current_menu != "codex" and _active_meta_screen.is_empty()
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
		"difficulty":
			# Tranche 4 (2026-07-06 audit): the old line probed a nonexistent
			# AccessibilitySettings.get_difficulty_multiplier() behind a
			# has_method guard, so every difficulty rendered "(x1.0)". Render
			# the REAL hazard dial from the canonical procgen mapping instead
			# (DifficultyProfile.resolve_dict — the same values the generator
			# feeds the encounter injector).
			var difficulty_id: String = settings_state.get_difficulty()
			return "%s: %s (hazard x%.1f)" % [base_label, difficulty_id, float(DifficultyProfileScript.for_id(difficulty_id).hazard_modifier)]
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
	var registry_lines: PackedStringArray = get_registry_unlock_lines()
	if registry_lines.size() > 0:
		lines.append("— CROSS-RUN UNLOCKS —")
		for rl in registry_lines:
			lines.append(String(rl))
	codex_panel.set_entries(lines)

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

## Session 3 (audit): the coordinator's record of the picked UI language.
## LanguageSelector owns the OptionButton; this is the game-side consumer.
var _active_language: String = "en"

func get_active_language() -> String:
	return _active_language

func _on_language_changed(language_id: String) -> void:
	_active_language = language_id
	_refresh_all()

func _on_credits_dismissed() -> void:
	_close_meta_screen()

func _on_item_enabled_changed(_item_id: String, _enabled: bool) -> void:
	_refresh_all()

func _on_menu_changed(new_menu_id: String, previous_menu_id: String) -> void:
	_last_closed_menu = previous_menu_id
	# Leaving the records menu always tears down any displayed meta screen.
	if new_menu_id != "records_menu" and not _active_meta_screen.is_empty():
		_active_meta_screen = ""
	if previous_menu_id.is_empty() and not new_menu_id.is_empty():
		modal_opened.emit(new_menu_id)
	elif not previous_menu_id.is_empty() and new_menu_id.is_empty():
		modal_closed.emit(previous_menu_id)
	_refresh_all()

func _on_tutorial_triggered(_tutorial_id: String, title: String, body: String) -> void:
	tutorial_overlay_panel.show_tutorial(title, body)
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		_audio_manager.play_sfx(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE)
	_refresh_codex()

func _on_tutorial_dismissed(_tutorial_id: String) -> void:
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		_audio_manager.play_sfx(AudioEventSeamScript.UI_PANEL_CLOSE)
	_refresh_tutorial()
	_refresh_codex()

func _on_codex_unlocked(_codex_entry_id: String) -> void:
	if is_instance_valid(_audio_manager) and _audio_manager.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		_audio_manager.play_sfx(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE)
	_refresh_codex()

func _on_payload_changed(payload) -> void:
	if payload == null:
		tooltip_panel.set_payload("", "", "")
		return
	tooltip_panel.set_payload(str(payload.title), str(payload.body), str(payload.footer))
