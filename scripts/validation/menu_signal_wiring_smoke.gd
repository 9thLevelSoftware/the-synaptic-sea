extends SceneTree

## Session 8 Task 6: menu/title signal wiring sweep.
##
##  1. language  — LanguageSelector.language_changed must record the active
##     language and re-render.
##  2. enabled_render — menu_state.enabled_changed must re-render the title
##     panel without a hand-called refresh.
##  3. credits_dismissed — canceling the active credits screen must route
##     through CreditsScreen.dismiss() so the signal fires before close.
##  4. metadata_changed — release badge metadata changes must be consumed by
##     the coordinator and re-render the visible badge.
##  5. playable_ready — title_main must consume the playable-ready summary and
##     clear stale title-session outcome/progress state.
##  6. playable_interaction_completed + playable_slice_completed — the title
##     must surface both run progress and final run outcome after return.
##
## Pass marker:
##   MENU SIGNAL WIRING PASS language=true enabled_render=true credits=true metadata=true ready=true progress=true run_outcome=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const TIMEOUT_FRAMES: int = 400

var title: Node
var frame_count: int = 0
var phase: String = "boot_title"
var settle: int = 0
var finished: bool = false
var _enabled_render_ok: bool = false
var _language_ok: bool = false
var _credits_ok: bool = false
var _metadata_ok: bool = false
var _ready_ok: bool = false
var _progress_ok: bool = false
var _credits_signal_fired: bool = false

func _initialize() -> void:
	title = TITLE_SCENE.instantiate()
	get_root().add_child(title)
	process_frame.connect(_on_frame)

func _node_text(root: Node) -> String:
	# Concatenate visible Label/RichTextLabel text for assertion.
	var out: String = ""
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null or not is_instance_valid(n):
			continue
		if n is Label:
			out += (n as Label).text + "\n"
		if n is RichTextLabel:
			out += (n as RichTextLabel).text + "\n"
		for c in n.get_children():
			stack.push_back(c)
	return out

func _panel_text() -> String:
	return _node_text(title.menu_panel)

func _has_property(node: Object, property_name: String) -> bool:
	if node == null:
		return false
	for prop in node.get_property_list():
		if str((prop as Dictionary).get("name", "")) == property_name:
			return true
	return false

func _pressed_action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event

func _on_credits_dismissed_smoke() -> void:
	_credits_signal_fired = true

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("timeout in phase %s" % phase)
		return
	match phase:
		"boot_title":
			if title.menu_panel != null and is_instance_valid(title.menu_panel):
				_check_enabled_render()
		"wait_playable":
			var pi = title.playable_instance
			if pi != null and is_instance_valid(pi) and pi.playable_started:
				_check_session_wiring(pi)
		"settle_title":
			settle += 1
			if settle >= 10:
				_check_title_return_lines()

## --- 2. enabled_render (title panel, no manual refresh) --------------------
func _check_enabled_render() -> void:
	var before: String = _panel_text()
	# Flip 'continue' enabled state through the pure model ONLY — the panel
	# must follow via the enabled_changed signal, not a hand-called refresh.
	var currently_enabled: bool = title.menu_state.is_item_enabled("main_menu", "continue")
	title.menu_state.set_item_enabled("main_menu", "continue", not currently_enabled)
	var after: String = _panel_text()
	title.menu_state.set_item_enabled("main_menu", "continue", currently_enabled)  # restore
	if before == after:
		_fail("panel did not re-render on menu_state.enabled_changed alone")
		return
	_enabled_render_ok = true
	title._last_run_outcome = "stale_outcome"
	if _has_property(title, "_last_run_progress"):
		title.set("_last_run_progress", "objectives 9/9")
	title._refresh_panel()
	phase = "wait_playable"
	title._on_title_start()

## --- 1. language + 3/4/5/6. session/title signal wiring --------------------
func _check_session_wiring(pi) -> void:
	var mc = pi.menu_coordinator
	if mc == null or not is_instance_valid(mc):
		_fail("menu_coordinator missing")
		return
	if not mc.has_method("get_active_language"):
		_fail("menu_coordinator has no get_active_language (language_changed unconsumed)")
		return
	var selector = mc.language_selector
	if selector == null or not is_instance_valid(selector):
		_fail("language_selector missing")
		return
	# The shipped catalog carries only "en" — feed the real selector a
	# two-language catalog through its public set_catalog API so the real
	# selection path can actually fire language_changed.
	var LocalizationCatalogScript := preload("res://scripts/systems/localization_catalog.gd")
	var two_lang = LocalizationCatalogScript.new()
	two_lang.configure({"en": {"k": "v"}, "smoke_lang": {"k": "w"}})
	selector.set_catalog(two_lang)
	# Pick a DIFFERENT language through the real OptionButton selection path.
	var target_idx: int = -1
	for idx in range(selector._option_button.item_count):
		if str(selector._option_button.get_item_text(idx)) != str(mc.get_active_language()):
			target_idx = idx
			break
	if target_idx < 0:
		_fail("no alternate language available to select")
		return
	var target_lang: String = str(selector._option_button.get_item_text(target_idx))
	selector._option_button.select(target_idx)
	selector._on_item_selected(target_idx)
	if str(mc.get_active_language()) != target_lang:
		_fail("coordinator did not record language '%s' (got '%s')" % [target_lang, str(mc.get_active_language())])
		return
	_language_ok = true

	_credits_signal_fired = false
	mc.credits_screen.credits_dismissed.connect(_on_credits_dismissed_smoke, CONNECT_ONE_SHOT)
	mc.open_meta_screen("credits")
	if mc.get_active_meta_screen() != "credits":
		_fail("credits screen did not open")
		return
	mc.handle_ui_input(_pressed_action("ui_cancel"))
	if not _credits_signal_fired:
		_fail("credits cancel did not call dismiss() / fire credits_dismissed")
		return
	if mc.get_active_meta_screen() != "":
		_fail("credits screen stayed open after dismiss")
		return
	_credits_ok = true

	mc.open_meta_screen("release_badge")
	if mc.get_active_meta_screen() != "release_badge":
		_fail("release badge screen did not open")
		return
	if not mc.release_badge_overlay.metadata_changed.is_connected(mc._refresh_all):
		_fail("release_badge_overlay.metadata_changed has no coordinator consumer")
		return
	var badge_before: String = _node_text(mc.release_badge_overlay)
	var metadata := BuildMetadataStateScript.new()
	metadata.configure({
		"version": "v9.9.9-smoke",
		"build_kind": "release",
		"store": "smoke",
		"language_defaults": ["en"],
	})
	mc.release_badge_overlay.set_metadata(metadata)
	var badge_after: String = _node_text(mc.release_badge_overlay)
	if badge_before == badge_after:
		_fail("release badge did not re-render after metadata_changed")
		return
	_metadata_ok = true
	mc.handle_ui_input(_pressed_action("ui_cancel"))
	mc.handle_ui_input(_pressed_action("ui_cancel"))

	if not _has_property(title, "_last_playable_summary"):
		_fail("title has no _last_playable_summary consumer state")
		return
	var ready_summary: Dictionary = title.get("_last_playable_summary")
	if ready_summary.is_empty():
		_fail("title did not store playable_ready summary")
		return
	if not title._last_run_outcome.is_empty():
		_fail("playable_ready did not clear stale run outcome")
		return
	if not _has_property(title, "_last_run_progress"):
		_fail("title has no _last_run_progress consumer state")
		return
	if not String(title.get("_last_run_progress")).is_empty():
		_fail("playable_ready did not clear stale run progress")
		return
	_ready_ok = true

	if not pi.teleport_player_to_objective_for_validation(1):
		_fail("could not move player to objective 1")
		return
	var interactable = pi.get_interactable_by_sequence(1)
	if interactable == null or not interactable.has_method("set_validation_player_in_range"):
		_fail("objective 1 interactable missing")
		return
	interactable.set_validation_player_in_range(pi.player)
	pi.player.request_interact()
	if pi.get_current_objective_sequence() != 2:
		_fail("interaction input path did not advance current_sequence=%d" % pi.get_current_objective_sequence())
		return
	var expected_progress: String = "objectives 1/%d" % int(ready_summary.get("objective_count", 0))
	var actual_progress: String = String(title.get("_last_run_progress"))
	if actual_progress != expected_progress:
		_fail("interaction progress missing expected='%s' got='%s'" % [expected_progress, actual_progress])
		return
	_progress_ok = true

	# End the run through the production completion path, then quit to title.
	pi.end_run("extraction")
	pi._on_ui_quit_requested()
	phase = "settle_title"

func _check_title_return_lines() -> void:
	finished = true
	if title.main_node != null and is_instance_valid(title.main_node):
		_fail("session not torn down after quit-to-title")
		return
	var text: String = _panel_text()
	if not text.contains("Last run"):
		_fail("title panel has no run-outcome line after a completed run (panel: %s)" % text.replace("\n", " | "))
		return
	if not text.contains("Progress: objectives 1/"):
		_fail("title panel has no progress line after a completed interaction (panel: %s)" % text.replace("\n", " | "))
		return
	print("MENU SIGNAL WIRING PASS language=%s enabled_render=%s credits=%s metadata=%s ready=%s progress=%s run_outcome=true" % [
		str(_language_ok).to_lower(),
		str(_enabled_render_ok).to_lower(),
		str(_credits_ok).to_lower(),
		str(_metadata_ok).to_lower(),
		str(_ready_ok).to_lower(),
		str(_progress_ok).to_lower(),
	])
	_cleanup(0)

func _fail(reason: String) -> void:
	push_error("MENU SIGNAL WIRING FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(title):
		title.queue_free()
	quit(code)
