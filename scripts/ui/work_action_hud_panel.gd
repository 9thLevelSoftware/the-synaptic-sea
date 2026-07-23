extends Control
class_name WorkActionHudPanel

## PKG-D9a: WorkAction target + progress HUD. Presentation only — coordinator
## pushes state from WorkActionDriver. Headless-queryable for smokes.

const PANEL_COLOR: Color = Color(0.05, 0.08, 0.06, 0.88)
const PANEL_BORDER_COLOR: Color = Color(0.95, 0.65, 0.2, 0.75)

var _open: bool = false
var _action_id: String = ""
var _target_id: String = ""
var _verb: String = ""
var _progress: float = 0.0
var _status: String = "idle"
var _noise: float = 0.0
var _hint: String = "Hold to work · release to cancel"

var _title_label: Label
var _body_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	if _title_label == null:
		var panel := PanelContainer.new()
		panel.name = "WorkActionHudPanel"
		panel.position = Vector2(-320, -140)
		panel.custom_minimum_size = Vector2(300, 110)
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		panel.add_child(margin)
		var vbox := VBoxContainer.new()
		margin.add_child(vbox)
		_title_label = Label.new()
		_title_label.text = "WORK"
		vbox.add_child(_title_label)
		_body_label = Label.new()
		_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body_label.custom_minimum_size = Vector2(270, 0)
		vbox.add_child(_body_label)
	visible = _open
	_render()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_render()


func close() -> void:
	_open = false
	visible = false
	_action_id = ""
	_target_id = ""
	_progress = 0.0
	_status = "idle"
	_render()


## Push live work state from WorkActionDriver / coordinator.
func set_work_state(state: Dictionary) -> void:
	_action_id = str(state.get("action_id", ""))
	_target_id = str(state.get("target_id", ""))
	_verb = str(state.get("verb", ""))
	_progress = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	_status = str(state.get("status", "idle"))
	_noise = maxf(0.0, float(state.get("noise", 0.0)))
	if state.has("hint"):
		_hint = str(state.get("hint"))
	if _status == "active" or _status == "completed":
		open()
	elif _status == "idle" or _status == "interrupted" or _status == "blocked":
		if _status == "idle":
			close()
		else:
			open()
	_render()


func get_progress() -> float:
	return _progress


func get_action_id() -> String:
	return _action_id


func get_status() -> String:
	return _status


func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if not _open and _status == "idle":
		return lines
	var title: String = _verb.to_upper() if not _verb.is_empty() else "WORK"
	if not _action_id.is_empty():
		title = "%s (%s)" % [title, _action_id]
	lines.append(title)
	if not _target_id.is_empty():
		lines.append("Target: %s" % _target_id)
	lines.append("Status: %s" % _status)
	var bar: String = _progress_bar(_progress)
	lines.append("Progress: %s %d%%" % [bar, int(round(_progress * 100.0))])
	if _noise > 0.0:
		lines.append("Noise: %.2f" % _noise)
	if not _hint.is_empty() and _status == "active":
		lines.append(_hint)
	return lines


func _progress_bar(ratio: float) -> String:
	var filled: int = int(clampf(ratio, 0.0, 1.0) * 10.0)
	var s: String = "["
	for i in range(10):
		s += "#" if i < filled else "-"
	s += "]"
	return s


func _render() -> void:
	if _body_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	_body_label.text = "\n".join(lines) if not lines.is_empty() else ""
	if _title_label != null:
		_title_label.text = "WORK" if _verb.is_empty() else _verb.to_upper()
