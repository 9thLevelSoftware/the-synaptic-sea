extends Control
class_name WoundsPanel

## PKG-D9d: wound list + treat/bandage actions. Presentation + pure model calls
## only; coordinator binds a WoundState. Headless-queryable.

signal panel_closed
signal treatment_applied(wound_id: String, kind: String)

var _wound_state                  # WoundState
var _open: bool = false
var _selected: int = 0
var _status: String = ""

var _title_label: Label
var _list_label: Label
var _status_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "WOUNDS"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 320)
		add_child(_status_label)
	visible = _open
	_render()


func bind(wound_state) -> void:
	_wound_state = wound_state
	_render()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_selected = 0
	_status = ""
	_render()


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


func get_selected_index() -> int:
	return _selected


func get_selected_wound_id() -> String:
	var rows: Array = _wound_rows()
	if _selected < 0 or _selected >= rows.size():
		return ""
	return str((rows[_selected] as Dictionary).get("wound_id", ""))


func move_selection(delta: int) -> void:
	var n: int = _wound_rows().size()
	if n <= 0:
		_selected = 0
		_render()
		return
	_selected = clampi(_selected + delta, 0, n - 1)
	_render()


func bandage_selected() -> bool:
	var wid: String = get_selected_wound_id()
	if wid.is_empty() or _wound_state == null:
		_status = "no wound"
		_render()
		return false
	if not _wound_state.has_method("bandage"):
		return false
	if not bool(_wound_state.call("bandage", wid)):
		_status = "bandage failed"
		_render()
		return false
	_status = "bandaged %s" % wid
	treatment_applied.emit(wid, "bandage")
	_render()
	return true


func treat_selected(severity_reduce: float = 0.35) -> bool:
	var wid: String = get_selected_wound_id()
	if wid.is_empty() or _wound_state == null:
		_status = "no wound"
		_render()
		return false
	if not _wound_state.has_method("treat"):
		return false
	if not bool(_wound_state.call("treat", wid, severity_reduce)):
		_status = "treat failed"
		_render()
		return false
	_status = "treated %s" % wid
	treatment_applied.emit(wid, "treat")
	_render()
	return true


func get_status() -> String:
	return _status


func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("WOUNDS")
	if _wound_state == null:
		lines.append("(no wound model)")
		return lines
	if _wound_state.has_method("get_status_lines"):
		for line in _wound_state.call("get_status_lines"):
			lines.append(str(line))
	var rows: Array = _wound_rows()
	if rows.is_empty():
		lines.append("(no active wounds)")
	else:
		lines.append("Select: %s" % get_selected_wound_id())
		lines.append("[B] bandage  [T] treat")
	if not _status.is_empty():
		lines.append(_status)
	# Work speed / bleed summary for HUD coupling
	if _wound_state.has_method("work_speed_multiplier"):
		lines.append("Work speed ×%.2f" % float(_wound_state.call("work_speed_multiplier")))
	if _wound_state.has_method("total_bleed_rate"):
		lines.append("Bleed %.2f" % float(_wound_state.call("total_bleed_rate")))
	return lines


func _wound_rows() -> Array:
	var out: Array = []
	if _wound_state == null:
		return out
	var wounds: Array = _wound_state.wounds if _wound_state.get("wounds") != null else []
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if float((w as Dictionary).get("severity", 0.0)) <= 0.001:
			continue
		out.append(w)
	return out


func _render() -> void:
	if _list_label == null:
		return
	var rows: Array = _wound_rows()
	var texts: PackedStringArray = PackedStringArray()
	for i in range(rows.size()):
		var e: Dictionary = rows[i]
		var prefix: String = "> " if i == _selected else "  "
		var flags: String = ""
		if bool(e.get("treated", false)):
			flags += "T"
		if bool(e.get("bandaged", false)):
			flags += "B"
		if flags.is_empty():
			flags = "-"
		texts.append("%s%s %s@%s sev=%.2f [%s]" % [
			prefix,
			str(e.get("wound_id", "")),
			str(e.get("kind", "")),
			str(e.get("body_part", "")),
			float(e.get("severity", 0.0)),
			flags,
		])
	_list_label.text = "\n".join(texts) if not texts.is_empty() else "(no active wounds)"
	if _status_label != null:
		var extra: String = _status
		if _wound_state != null and _wound_state.has_method("work_speed_multiplier"):
			extra = "work×%.2f  %s" % [float(_wound_state.call("work_speed_multiplier")), _status]
		_status_label.text = extra
