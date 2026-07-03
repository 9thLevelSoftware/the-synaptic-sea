extends Control
class_name ChartPanel

## Domain 10 (ADR-0045): read-only text panel rendering WebChartState's
## recorded ship markers. Mirrors ScannerPanel's presentation style (a bare
## vertical text panel, headless-queryable row model) but has no travel
## action -- travel stays on the scanner panel (spec 5.5/6). Gated open:
## the coordinator only calls open() when the player possesses a web_chart
## (get_quantity("web_chart") > 0); otherwise it surfaces a HUD feedback
## line instead of opening this panel at all.

signal panel_closed

var _chart_state   # WebChartState
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "WEB CHART"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 320)
		add_child(_status_label)
	visible = _open
	_render()

func bind(chart_state) -> void:
	_chart_state = chart_state

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
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
	_render()

func get_status() -> String:
	if _chart_state == null:
		return "no chart"
	var count: int = int(_chart_state.get_known_count())
	return "no markers recorded" if count == 0 else "%d marker(s) recorded" % count

func get_row_texts() -> Array:
	var out: Array = []
	if _chart_state == null:
		return out
	for marker_id in _chart_state.get_known_marker_ids():
		out.append(_format_row(String(marker_id), _chart_state.get_entry(marker_id)))
	return out

func _format_row(marker_id: String, entry: Dictionary) -> String:
	var parts: Array = [marker_id]
	parts.append("sz=%d" % int(entry.get("size_class", 0)))
	if entry.has("ship_type"):
		parts.append(String(entry["ship_type"]))
	if entry.has("condition"):
		parts.append("cond=%d" % int(entry["condition"]))
	if entry.has("predicted_status"):
		parts.append(String(entry["predicted_status"]))
	if entry.has("loot_hint"):
		parts.append(String(entry["loot_hint"]))
	return " · ".join(parts)

func _render() -> void:
	if _list_label == null:
		return
	var rows: Array = get_row_texts()
	_list_label.text = "\n".join(rows) if not rows.is_empty() else "(no markers recorded)"
	if _status_label != null:
		_status_label.text = get_status()
