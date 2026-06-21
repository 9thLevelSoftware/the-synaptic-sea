extends Control
class_name ScannerPanel

## Minimal functional scanner UI. Renders the coordinator's scan() view-dicts as
## text rows, moves a selection, and confirms travel via travel_to_marker_id().
## Unstyled — a Phase 7 visual pass replaces the presentation. The row model is
## headless-queryable so smokes exercise the same code path without keystrokes.

# Emitted at the end of close() so the coordinator restores player control on
# EVERY close path (toggle, confirm-success, future ESC/dock/reload) rather than
# only the two paths wired into _input.
signal panel_closed

var _coordinator                 # has scan() and travel_to_marker_id(id)
var _markers: Array = []         # Array of scan() view dicts
var _selected: int = 0
var _status: String = ""
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label

func _ready() -> void:
	# Build a bare vertical text panel programmatically so the scene file stays
	# trivial (the .tscn only needs to instance this script on a Control).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "SCANNER"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 320)
		add_child(_status_label)
	visible = _open
	_render()

func bind(coord) -> void:
	_coordinator = coord

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	# Always reopen at the top contact rather than a stale prior index.
	_selected = 0
	refresh()

func close() -> void:
	_open = false
	visible = false
	panel_closed.emit()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func refresh() -> void:
	if _coordinator == null or not _coordinator.has_method("scan"):
		_markers = []
		_status = "no scanner"
		_render()
		return
	var result: Dictionary = _coordinator.scan()
	_markers = result.get("markers", []) as Array
	if _markers.is_empty():
		_status = "no signal"
	else:
		_status = "%d contact(s)" % _markers.size()
	_selected = clampi(_selected, 0, max(0, _markers.size() - 1))
	_render()

func move_selection(dir: int) -> void:
	if _markers.is_empty():
		return
	_selected = wrapi(_selected + dir, 0, _markers.size())
	_render()

func get_selected_index() -> int:
	return _selected

func get_status() -> String:
	return _status

func confirm_selection() -> Dictionary:
	if _markers.is_empty():
		_status = "no target"
		_render()
		return {"success": false, "reason": "no_target", "ship": null}
	if _coordinator == null or not _coordinator.has_method("travel_to_marker_id"):
		_status = "no travel"
		_render()
		return {"success": false, "reason": "not_ready", "ship": null}
	var marker_id: String = String((_markers[_selected] as Dictionary).get("marker_id", ""))
	var result: Dictionary = _coordinator.travel_to_marker_id(marker_id)
	if bool(result.get("success", false)):
		close()
	else:
		_status = String(result.get("reason", "rejected"))
		_render()
	return result

func get_row_texts() -> Array:
	var out: Array = []
	for view in _markers:
		out.append(_format_row(view as Dictionary))
	return out

func _format_row(view: Dictionary) -> String:
	var parts: Array = [String(view.get("marker_id", "?"))]
	parts.append("d=%.0f" % float(view.get("distance", 0.0)))
	parts.append("sz=%d" % int(view.get("size_class", 0)))
	if view.has("ship_type"):
		parts.append(String(view["ship_type"]))
	if view.has("condition"):
		parts.append("cond=%d" % int(view["condition"]))
	if view.has("predicted_status"):
		parts.append(String(view["predicted_status"]))
	if view.has("loot_hint"):
		parts.append(String(view["loot_hint"]))
	return " · ".join(parts)

func _render() -> void:
	if _list_label == null:
		return
	var lines: Array = []
	var rows: Array = get_row_texts()
	for i in range(rows.size()):
		var prefix: String = "> " if i == _selected else "  "
		lines.append(prefix + String(rows[i]))
	_list_label.text = "\n".join(lines) if not lines.is_empty() else "(no contacts)"
	if _status_label != null:
		_status_label.text = _status
