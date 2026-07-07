extends SceneTree

## Session 3 Part A (audit T1.6 remainder): three dead menu/flow signals.
##
##  1. language  — LanguageSelector.language_changed (language_selector.gd:84)
##     had ZERO subscribers: picking a language did nothing. The coordinator
##     must record the active language and re-render.
##  2. enabled_render — menu_state.enabled_changed was connected nowhere;
##     set_item_enabled only took visual effect if the caller hand-refreshed.
##     The title panel must re-render on the signal alone.
##  3. run_outcome — playable_slice_completed (coordinator :1670/:5208) had
##     ZERO subscribers. The title screen must surface "Last run: <reason>"
##     after the player returns from a completed run.
##
## Pass marker: MENU SIGNAL WIRING PASS language=true enabled_render=true run_outcome=true

const TITLE_SCENE: PackedScene = preload("res://scenes/title_main.tscn")
const TIMEOUT_FRAMES: int = 400

var title: Node
var frame_count: int = 0
var phase: String = "boot_title"
var settle: int = 0
var finished: bool = false

func _initialize() -> void:
	title = TITLE_SCENE.instantiate()
	get_root().add_child(title)
	process_frame.connect(_on_frame)

func _panel_text() -> String:
	# MenuPanel content: concatenate its Label children text for assertion.
	var out: String = ""
	var stack: Array = [title.menu_panel]
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
				_check_language_and_outcome(pi)
		"settle_title":
			settle += 1
			if settle >= 10:
				_check_outcome_line()

## --- 2. enabled_render (title panel, no manual refresh) --------------------
var _enabled_render_ok: bool = false
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
	phase = "wait_playable"
	title._on_title_start()

## --- 1. language + 3. run completion ---------------------------------------
var _language_ok: bool = false
func _check_language_and_outcome(pi) -> void:
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
	# End the run through the production completion path, then quit to title.
	pi.end_run("extraction")
	pi._on_ui_quit_requested()
	phase = "settle_title"

func _check_outcome_line() -> void:
	finished = true
	if title.main_node != null and is_instance_valid(title.main_node):
		_fail("session not torn down after quit-to-title")
		return
	var text: String = _panel_text()
	if not text.contains("Last run"):
		_fail("title panel has no run-outcome line after a completed run (panel: %s)" % text.replace("\n", " | "))
		return
	print("MENU SIGNAL WIRING PASS language=%s enabled_render=%s run_outcome=true" % [
		str(_language_ok).to_lower(), str(_enabled_render_ok).to_lower()])
	_cleanup(0)

func _fail(reason: String) -> void:
	push_error("MENU SIGNAL WIRING FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(title):
		title.queue_free()
	quit(code)
