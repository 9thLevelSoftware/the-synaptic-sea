extends RefCounted
class_name MenuState
## Pure menu-stack state machine (REQ-UI-001 / ADR-0033).
##
## Owns:
##   - `current_menu` — id of the active menu, or "" for "in-play"
##   - `menu_history` — stack of menu ids so `cancel` pops one
##   - `focus_index` — focused item index within the active menu
##   - `enabled_overrides` — per-item enabled override map
##
## The catalog is loaded from `data/ui/menu_definitions.json` at
## `configure()` time. The catalog is the only source of truth for
## menu ids and item ids — every public method that takes an id
## rejects unknown ids via `push_warning` and is a no-op.
##
## Pure-model-first: no scene-tree access, no signal emission.
## The scene coordinator subscribes to the explicit signals
## `menu_changed`, `focus_changed`, `enabled_changed`, and applies
## the consequences (panel visibility, focus node, item fade).
##
## Signals are declared here so other RefCounted code can subscribe
## without needing the node wrapper. The pure RefCounted emits via
## `emit_signal` like any other Object.

signal menu_changed(new_menu_id: String, previous_menu_id: String)
signal focus_changed(new_index: int)
signal enabled_changed(item_id: String, enabled: bool)

const MenuStateSchemaScript := preload("res://scripts/schemas/menu_state_schema.gd")

const SCHEMA_VERSION: String = "menu-state-1"
const SAVE_KEY: String = "menu_state"

var _catalog: Dictionary = {}
var _menu_ids: Array = []                       # ordered menu ids
var _items_by_menu: Dictionary = {}             # menu_id -> Array of item dicts (in order)
var _current_menu: String = ""                  # "" = in-play
var _menu_history: Array = []                   # stack of previously-open menu ids
var _focus_index: int = 0                       # focused item index in current menu
var _enabled_overrides: Dictionary = {}         # menu_id|item_id -> bool
var _closed_in_play: bool = true                # whether the in-play layer is closed

func configure(catalog: Dictionary) -> bool:
	if not MenuStateSchemaScript.validate_catalog(catalog):
		return false
	_catalog = (catalog as Dictionary).duplicate(true)
	_menu_ids.clear()
	_items_by_menu.clear()
	for menu in (_catalog.get("menus", []) as Array):
		var menu_dict: Dictionary = menu
		var menu_id: String = str(menu_dict.get("id", ""))
		_menu_ids.append(menu_id)
		_items_by_menu[menu_id] = (menu_dict.get("items", []) as Array).duplicate(true)
	_current_menu = ""
	_menu_history.clear()
	_focus_index = 0
	_enabled_overrides.clear()
	_closed_in_play = true
	return true

## True when no menu is open (in-play layer is the active surface).
func is_in_play() -> bool:
	return _current_menu.is_empty()

## True when the named menu is currently the active menu.
func is_open(menu_id: String) -> bool:
	return _current_menu == menu_id

## Currently-active menu id ("" for in-play).
func get_current_menu() -> String:
	return _current_menu

## The list of menu ids the player navigated through to reach the
## current menu. The bottom of the stack is the first menu opened.
func get_menu_history() -> Array:
	return _menu_history.duplicate()

## Focus index within the current menu (0-based).
func get_focus_index() -> int:
	return _focus_index

## Number of items in the current menu.
func get_item_count() -> int:
	if _current_menu.is_empty():
		return 0
	return (_items_by_menu.get(_current_menu, []) as Array).size()

## Number of menus in the catalog.
func get_menu_count() -> int:
	return _menu_ids.size()

## True if the named menu id is registered in the catalog.
func has_menu(menu_id: String) -> bool:
	return menu_id in _menu_ids

## True if the named item id is registered in the named menu.
func has_item(menu_id: String, item_id: String) -> bool:
	if not has_menu(menu_id):
		return false
	for item in (_items_by_menu.get(menu_id, []) as Array):
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == item_id:
			return true
	return false

## Returns the registered list of items for a menu (Array of Dicts) or
## an empty Array when the menu is unknown.
func get_items(menu_id: String) -> Array:
	if not has_menu(menu_id):
		return []
	return ((_items_by_menu.get(menu_id, []) as Array)).duplicate(true)

## Returns the focused item dict, or an empty Dictionary when no menu
## is open or the focus index is out of range.
func get_focused_item() -> Dictionary:
	if _current_menu.is_empty():
		return {}
	var items: Array = _items_by_menu.get(_current_menu, [])
	if _focus_index < 0 or _focus_index >= items.size():
		return {}
	var focused: Variant = items[_focus_index]
	if typeof(focused) != TYPE_DICTIONARY:
		return {}
	return (focused as Dictionary).duplicate(true)

## Returns true when the named item is enabled for interaction.
## Enabled state is the AND of the catalog default and the per-item
## override map (used by the main menu to disable Continue when no
## save exists, etc.).
func is_item_enabled(menu_id: String, item_id: String) -> bool:
	var item: Dictionary = _find_item(menu_id, item_id)
	if item.is_empty():
		return false
	var default_enabled: bool = bool(item.get("enabled", true))
	var key: String = menu_id + "|" + item_id
	if _enabled_overrides.has(key):
		return bool(_enabled_overrides[key]) and default_enabled
	return default_enabled

## Override the enabled state for an item. Used by the main menu to
## enable Continue when a save exists.
func set_item_enabled(menu_id: String, item_id: String, enabled: bool) -> void:
	if not has_item(menu_id, item_id):
		push_warning("MenuState: set_item_enabled unknown item '%s' in menu '%s'" % [item_id, menu_id])
		return
	var key: String = menu_id + "|" + item_id
	_enabled_overrides[key] = enabled
	emit_signal("enabled_changed", item_id, enabled)

## Open a menu. The previously-active menu is pushed onto the history
## stack so `cancel` can pop back. Closing the menu returns to the
## in-play layer.
func open_menu(menu_id: String) -> bool:
	if not has_menu(menu_id):
		push_warning("MenuState: open_menu unknown menu '%s'" % menu_id)
		return false
	if _current_menu == menu_id:
		return true
	var previous: String = _current_menu
	if not _current_menu.is_empty():
		_menu_history.append(_current_menu)
	else:
		_closed_in_play = false
	_current_menu = menu_id
	_focus_index = 0
	emit_signal("menu_changed", _current_menu, previous)
	emit_signal("focus_changed", _focus_index)
	return true

## Pop the topmost menu off the stack. Returns false when there is
## nothing to pop (player is already in-play).
func close_top() -> bool:
	if _current_menu.is_empty():
		return false
	var previous: String = _current_menu
	if _menu_history.is_empty():
		_current_menu = ""
		_closed_in_play = true
	else:
		_current_menu = String(_menu_history.pop_back())
	_focus_index = 0
	emit_signal("menu_changed", _current_menu, previous)
	emit_signal("focus_changed", _focus_index)
	return true

## Pop the entire stack, returning to in-play.
func close_all() -> bool:
	if _current_menu.is_empty() and _menu_history.is_empty():
		return false
	var previous: String = _current_menu
	_current_menu = ""
	_menu_history.clear()
	_closed_in_play = true
	_focus_index = 0
	emit_signal("menu_changed", _current_menu, previous)
	emit_signal("focus_changed", _focus_index)
	return true

## Navigate the focus by (dx, dy). The current menu treats its items
## as a single-column list, so dy drives focus change and dx is
## reserved for sub-menu navigation in a future package. A move that
## lands outside the item range clamps to the valid range.
func navigate(dx: int, dy: int) -> int:
	if _current_menu.is_empty():
		return 0
	var items_count: int = (_items_by_menu.get(_current_menu, []) as Array).size()
	if items_count == 0:
		return 0
	var new_index: int = _focus_index + dy
	if new_index < 0:
		new_index = 0
	elif new_index >= items_count:
		new_index = items_count - 1
	if new_index == _focus_index:
		return _focus_index
	_focus_index = new_index
	emit_signal("focus_changed", _focus_index)
	return _focus_index

## Move focus to the absolute index. Out-of-range indices are clamped.
func set_focus_index(index: int) -> int:
	if _current_menu.is_empty():
		return 0
	var items_count: int = (_items_by_menu.get(_current_menu, []) as Array).size()
	if items_count == 0:
		return 0
	var new_index: int = clampi(index, 0, items_count - 1)
	if new_index == _focus_index:
		return _focus_index
	_focus_index = new_index
	emit_signal("focus_changed", _focus_index)
	return _focus_index

## Trigger the focused item. Returns the focused item id (so the
## scene coordinator can dispatch the action), or "" when no menu is
## open or the focused item is disabled.
func confirm() -> String:
	var focused: Dictionary = get_focused_item()
	if focused.is_empty():
		return ""
	var item_id: String = str(focused.get("id", ""))
	if not is_item_enabled(_current_menu, item_id):
		return ""
	return item_id

## Same as `close_top` — `cancel` and `close_top` are aliases because
## the player expects them to behave identically across menus.
func cancel() -> bool:
	return close_top()

## Pure-model summary used by the save/load seam and the
## `main_playable_slice_ui_shell_smoke`. The summary is opaque to
## callers; use `apply_summary` to restore.
func get_summary() -> Dictionary:
	var history: Array = []
	for menu_id in _menu_history:
		history.append(String(menu_id))
	var overrides: Dictionary = {}
	for key in _enabled_overrides.keys():
		overrides[String(key)] = bool(_enabled_overrides[key])
	return {
		"schema": SCHEMA_VERSION,
		"current_menu": _current_menu,
		"menu_history": history,
		"focus_index": _focus_index,
		"enabled_overrides": overrides,
		"closed_in_play": _closed_in_play,
	}

## Apply a previously-emitted summary. The summary must come from a
## `get_summary` call against a state with the same catalog; a
## summary whose `current_menu` is unknown to the loaded catalog is
## rejected (returns false) so we never open a phantom menu.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	if str(summary.get("schema", "")) != SCHEMA_VERSION:
		return false
	var new_menu: String = str(summary.get("current_menu", ""))
	if not new_menu.is_empty() and not has_menu(new_menu):
		push_warning("MenuState: apply_summary unknown current_menu '%s'; reset to in-play" % new_menu)
		new_menu = ""
	var history_variant: Variant = summary.get("menu_history", [])
	var new_history: Array = []
	if typeof(history_variant) == TYPE_ARRAY:
		for entry in (history_variant as Array):
			var entry_id: String = str(entry)
			if has_menu(entry_id):
				new_history.append(entry_id)
	_current_menu = new_menu
	_menu_history = new_history
	_focus_index = int(summary.get("focus_index", 0))
	_closed_in_play = bool(summary.get("closed_in_play", _current_menu.is_empty()))
	# Clamp focus index to current menu's item count.
	var items_count: int = (_items_by_menu.get(_current_menu, []) as Array).size()
	if items_count == 0:
		_focus_index = 0
	else:
		_focus_index = clampi(_focus_index, 0, items_count - 1)
	_enabled_overrides.clear()
	var overrides_variant: Variant = summary.get("enabled_overrides", {})
	if typeof(overrides_variant) == TYPE_DICTIONARY:
		for key in (overrides_variant as Dictionary).keys():
			var key_str: String = str(key)
			var sep_idx: int = key_str.find("|")
			if sep_idx < 0:
				continue
			var menu_id: String = key_str.substr(0, sep_idx)
			var item_id: String = key_str.substr(sep_idx + 1)
			if has_item(menu_id, item_id):
				_enabled_overrides[key_str] = bool(overrides_variant[key])
	emit_signal("menu_changed", _current_menu, "")
	emit_signal("focus_changed", _focus_index)
	return true

## Per-run status lines for the no-git ledger and the regression
## bundle's status dump.
func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("MenuState: current=%s history=%d focus=%d items=%d" % [
		_current_menu if not _current_menu.is_empty() else "<in-play>",
		_menu_history.size(),
		_focus_index,
		get_item_count(),
	])
	lines.append("  catalog_menus=%d overrides=%d" % [
		_menu_ids.size(),
		_enabled_overrides.size(),
	])
	return lines

func _find_item(menu_id: String, item_id: String) -> Dictionary:
	if not has_menu(menu_id):
		return {}
	for item in (_items_by_menu.get(menu_id, []) as Array):
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == item_id:
			return (item as Dictionary).duplicate(true)
	return {}