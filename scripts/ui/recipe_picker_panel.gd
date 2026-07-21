extends Control
class_name RecipePickerPanel

## REQ-CS-016 station recipe picker. Lists CraftingState.list_recipe_entries for a
## station_kind, moves a selection, and confirms via the coordinator begin path.
## Unstyled text list (scanner / hub-upgrade pattern). Headless-queryable for smokes.

signal panel_closed

var _coordinator                 # PlayableGeneratedShip or stub with list + begin APIs
var _station_kind: String = ""
var _entries: Array = []         # Array of entry Dictionaries from list_recipe_entries
var _selected: int = 0
var _status: String = ""
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "CRAFT"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 360)
		add_child(_status_label)
	visible = _open
	_render()

func bind(coord) -> void:
	_coordinator = coord

func is_open() -> bool:
	return _open

func get_station_kind() -> String:
	return _station_kind

func get_selected_index() -> int:
	return _selected

func get_status() -> String:
	return _status

func get_entry_count() -> int:
	return _entries.size()

func get_selected_id() -> String:
	if _selected < 0 or _selected >= _entries.size():
		return ""
	return str((_entries[_selected] as Dictionary).get("recipe_id", ""))

func get_row_texts() -> Array:
	var out: Array = []
	for entry in _entries:
		out.append(_format_row(entry as Dictionary))
	return out

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Craft: %s  (%d recipes)" % [_station_kind if not _station_kind.is_empty() else "?", _entries.size()])
	var rows: Array = get_row_texts()
	for i in range(rows.size()):
		var prefix: String = "> " if i == _selected else "  "
		lines.append(prefix + String(rows[i]))
	if not _status.is_empty():
		lines.append(_status)
	return lines

func open_for_station(station_kind: String) -> void:
	_station_kind = station_kind
	_open = true
	visible = true
	_status = ""
	_refresh_entries()
	_selected = _first_ready_index()
	_render()

func close() -> void:
	_open = false
	visible = false
	_station_kind = ""
	panel_closed.emit()

func refresh() -> void:
	if not _open:
		return
	var prev_id: String = get_selected_id()
	_refresh_entries()
	# Prefer keeping the same recipe under the cursor if it still exists.
	var kept: int = -1
	if not prev_id.is_empty():
		for i in range(_entries.size()):
			if str((_entries[i] as Dictionary).get("recipe_id", "")) == prev_id:
				kept = i
				break
	if kept >= 0:
		_selected = kept
	else:
		_selected = _first_ready_index()
	_render()

func move_selection(dir: int) -> void:
	if _entries.is_empty():
		return
	_selected = wrapi(_selected + dir, 0, _entries.size())
	_render()

func confirm_selection() -> Dictionary:
	if _entries.is_empty():
		_status = "no recipes"
		_render()
		return {"ok": false, "reason": "no_recipes", "recipe_id": ""}
	var entry: Dictionary = _entries[_selected] as Dictionary
	var rid: String = str(entry.get("recipe_id", ""))
	if not bool(entry.get("craftable", false)):
		_status = "blocked: %s" % str(entry.get("status", "unknown"))
		_render()
		return {"ok": false, "reason": str(entry.get("status", "blocked")), "recipe_id": rid}
	if _coordinator == null or not _coordinator.has_method("begin_craft_from_picker"):
		_status = "no craft handler"
		_render()
		return {"ok": false, "reason": "not_ready", "recipe_id": rid}
	var result: Dictionary = _coordinator.begin_craft_from_picker(_station_kind, rid)
	if bool(result.get("ok", false)):
		close()
		return result
	_status = str(result.get("reason", "rejected"))
	_render()
	# Refresh so ingredient state after a partial failure is accurate.
	refresh()
	return result

func _refresh_entries() -> void:
	_entries = []
	if _coordinator == null or not _coordinator.has_method("list_station_recipe_entries"):
		return
	var listed: Variant = _coordinator.list_station_recipe_entries(_station_kind)
	if listed is Array:
		_entries = listed as Array

func _first_ready_index() -> int:
	for i in range(_entries.size()):
		if bool((_entries[i] as Dictionary).get("craftable", false)):
			return i
	return 0 if not _entries.is_empty() else 0

func _format_row(entry: Dictionary) -> String:
	var status: String = str(entry.get("status", "?"))
	var name: String = str(entry.get("display_name", entry.get("recipe_id", "?")))
	var skill: int = int(entry.get("required_skill_level", 0))
	var produces: Dictionary = entry.get("produces", {}) as Dictionary if entry.get("produces", {}) is Dictionary else {}
	var out_id: String = str(produces.get("item_id", ""))
	var out_qty: int = int(produces.get("quantity", 0))
	var ing_parts: Array = []
	var ingredients: Variant = entry.get("ingredients", {})
	if ingredients is Dictionary:
		for mat_id in (ingredients as Dictionary):
			ing_parts.append("%s×%d" % [str(mat_id), int((ingredients as Dictionary)[mat_id])])
	var ing_str: String = " ".join(ing_parts) if not ing_parts.is_empty() else "-"
	return "[%s] %s  skill=%d  %s → %s×%d" % [status, name, skill, ing_str, out_id, out_qty]

func _render() -> void:
	if _title_label != null:
		if _station_kind == "salvage":
			_title_label.text = "SALVAGE"
		elif _station_kind == "field_crafting":
			_title_label.text = "FIELD CRAFT"
		else:
			_title_label.text = "CRAFT — %s" % (_station_kind if not _station_kind.is_empty() else "?")
	if _list_label == null:
		return
	var lines: Array = []
	var rows: Array = get_row_texts()
	for i in range(rows.size()):
		var prefix: String = "> " if i == _selected else "  "
		lines.append(prefix + String(rows[i]))
	_list_label.text = "\n".join(lines) if not lines.is_empty() else "(no recipes)"
	if _status_label != null:
		_status_label.text = _status
