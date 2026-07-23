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
var _sea_graph     # SeaGraph (PKG-D9c optional)
var _route_summary: Dictionary = {}
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label
var _route_label: Label

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
		_route_label = Label.new()
		_route_label.position = Vector2(24, 360)
		_route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_route_label.custom_minimum_size = Vector2(400, 0)
		add_child(_route_label)
	visible = _open
	_render()

func bind(chart_state) -> void:
	assert(chart_state != null, "ChartPanel.bind: chart_state must not be null")
	_chart_state = chart_state


## PKG-D9c: optional strategic SeaGraph for extraction route display.
func bind_sea_graph(sea_graph) -> void:
	_sea_graph = sea_graph
	_render()


## Push a route dict from SeaGraph.find_route / route_to_extraction.
func set_route_summary(route: Dictionary) -> void:
	_route_summary = route.duplicate(true) if route != null else {}
	_render()


func refresh_extraction_route() -> void:
	if _sea_graph == null or not _sea_graph.has_method("route_to_extraction"):
		_route_summary = {}
		_render()
		return
	_route_summary = _sea_graph.call("route_to_extraction")
	_render()


func get_route_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _route_summary.is_empty():
		return lines
	if not bool(_route_summary.get("ok", false)):
		lines.append("Route: unavailable (%s)" % str(_route_summary.get("reason", "?")))
		return lines
	var path: Array = _route_summary.get("path", [])
	lines.append("Route to extraction (%d hops)" % maxi(0, path.size() - 1))
	lines.append("  fuel=%.1f food=%.1f dist=%.1f" % [
		float(_route_summary.get("fuel", 0.0)),
		float(_route_summary.get("food", 0.0)),
		float(_route_summary.get("distance", 0.0)),
	])
	if not path.is_empty():
		var via: PackedStringArray = PackedStringArray()
		for n in path:
			via.append(str(n))
		lines.append("  %s" % " -> ".join(via))
	return lines

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
	var base: String = "no markers recorded" if count == 0 else "%d marker(s) recorded" % count
	if bool(_route_summary.get("ok", false)):
		base += " · route ready"
	return base

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
	if _route_label != null:
		var rlines: PackedStringArray = get_route_lines()
		_route_label.text = "\n".join(rlines) if not rlines.is_empty() else ""
