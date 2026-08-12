extends PanelContainer
class_name RunResultsPanel

## Task 2.2: intentional end-of-run presentation for death, extraction, and abort.
## The panel accepts the completion summary directly so it stays tolerant of
## additive gameplay stats and does not invent values that the run did not track.

const COPY_PATH: String = "res://data/ui/run_results_copy.json"
const BASE_FONT_SIZE: int = 20
const BASE_PANEL_SIZE: Vector2 = Vector2(620.0, 460.0)
const BASE_BODY_SIZE: Vector2 = Vector2(560.0, 280.0)
const PANEL_COLOR: Color = Color(0.02, 0.04, 0.07, 0.97)
const PANEL_BORDER_COLOR: Color = Color(0.86, 0.63, 0.24, 0.9)

signal return_to_title_requested
signal new_run_requested

var title_label: Label
var body_label: Label
var return_button: Button
var new_run_button: Button
var _summary: Dictionary = {}
var _epitaphs: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_preset(Control.PRESET_CENTER)
	_build_nodes()
	_load_copy()
	if not _summary.is_empty():
		_refresh_content()
	return_button.call_deferred("grab_focus")

func set_run_summary(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	_load_copy()
	_build_nodes()
	_refresh_content()

func get_summary() -> Dictionary:
	return _summary.duplicate(true)

func _build_nodes() -> void:
	if title_label != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "RUN RESULTS"
	vbox.add_child(title_label)

	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body_label.custom_minimum_size = BASE_BODY_SIZE
	vbox.add_child(body_label)

	var divider := HSeparator.new()
	vbox.add_child(divider)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	return_button = Button.new()
	return_button.text = "Return to Title"
	return_button.focus_mode = Control.FOCUS_ALL
	return_button.pressed.connect(_on_return_pressed)
	button_row.add_child(return_button)

	new_run_button = Button.new()
	new_run_button.text = "New Run"
	new_run_button.focus_mode = Control.FOCUS_ALL
	new_run_button.pressed.connect(_on_new_run_pressed)
	button_row.add_child(new_run_button)

	custom_minimum_size = BASE_PANEL_SIZE
	size = BASE_PANEL_SIZE
	position = Vector2(-BASE_PANEL_SIZE.x * 0.5, -BASE_PANEL_SIZE.y * 0.5)
	title_label.add_theme_font_size_override("font_size", BASE_FONT_SIZE + 6)
	body_label.add_theme_font_size_override("font_size", BASE_FONT_SIZE)

func _load_copy() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_epitaphs = (parsed as Dictionary).get("epitaphs", {}).duplicate(true)
	if _epitaphs.is_empty():
		_epitaphs = {"default": "The sea keeps what it takes."}

func _refresh_content() -> void:
	var outcome: String = _normalized_outcome()
	var lines := PackedStringArray()
	lines.append("Outcome: %s" % outcome)

	var cause: String = _summary_string(["cause", "death_cause", "failure_cause"])
	if not cause.is_empty():
		lines.append("Cause: %s" % cause)
	if outcome == "death":
		lines.append("Epitaph: %s" % _epitaph_for(cause))

	var play_time: Variant = _first_present(["play_time_seconds", "time_survived_seconds", "run_time_seconds", "survival_seconds"])
	if play_time != null:
		lines.append("Time survived: %s" % _format_duration(float(play_time)))

	_append_stat(lines, "Rooms discovered", ["rooms_discovered", "rooms_discovered_count", "discovered_rooms"])
	_append_stat(lines, "Threats killed", ["threats_killed", "threats_defeated", "kills"])
	_append_stat(lines, "Loot value", ["loot_value", "loot_value_total", "loot_total"])
	_append_stat(lines, "Objectives completed", ["objectives_completed"])

	if lines.size() == 1:
		lines.append("No additional run statistics were recorded.")
	body_label.text = "\n".join(lines)

func _normalized_outcome() -> String:
	var outcome: String = _summary_string(["reason", "outcome"])
	if outcome.is_empty():
		return "abort"
	outcome = outcome.to_lower()
	if outcome == "complete" or outcome == "completion":
		return "extraction"
	if outcome == "abandon" or outcome == "aborted" or outcome == "quit":
		return "abort"
	if outcome == "death" or outcome == "extraction" or outcome == "abort":
		return outcome
	return "abort"

func _summary_string(keys: Array) -> String:
	for key in keys:
		if _summary.has(key) and _summary[key] != null:
			var value: String = str(_summary[key]).strip_edges()
			if not value.is_empty():
				return value
	return ""

func _first_present(keys: Array) -> Variant:
	for key in keys:
		if _summary.has(key) and _summary[key] != null:
			return _summary[key]
	return null

func _append_stat(lines: PackedStringArray, label: String, keys: Array) -> void:
	var value: Variant = _first_present(keys)
	if value != null:
		lines.append("%s: %s" % [label, str(value)])

func _epitaph_for(cause: String) -> String:
	var key: String = cause.to_lower().strip_edges()
	if not _epitaphs.has(key):
		key = "default"
	return str(_epitaphs.get(key, "The sea keeps what it takes."))

func _format_duration(seconds: float) -> String:
	var total: int = maxi(0, int(floor(seconds)))
	return "%02d:%02d" % [int(total / 60), total % 60]

func _on_return_pressed() -> void:
	return_to_title_requested.emit()

func _on_new_run_pressed() -> void:
	new_run_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_return_pressed()
		get_viewport().set_input_as_handled()
