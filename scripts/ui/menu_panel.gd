extends PanelContainer
class_name MenuPanel

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")

const BASE_FONT_SIZE: int = 20
const BASE_PANEL_SIZE: Vector2 = Vector2(520.0, 360.0)
const BASE_LABEL_MIN_SIZE: Vector2 = Vector2(460.0, 280.0)
const PANEL_COLOR: Color = Color(0.02, 0.04, 0.07, 0.9)
const PANEL_BORDER_COLOR: Color = Color(0.18, 0.65, 1.0, 0.7)

var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var title_label: Label
var body_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-BASE_PANEL_SIZE.x * 0.5, -BASE_PANEL_SIZE.y * 0.5)
	_build_nodes()
	_apply_accessibility_settings(accessibility_settings)

func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if is_inside_tree():
		_apply_accessibility_settings(settings)

func set_content(title: String, lines: PackedStringArray) -> void:
	_build_nodes()
	title_label.text = title
	body_label.text = "\n".join(lines)

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
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body_label.custom_minimum_size = BASE_LABEL_MIN_SIZE
	vbox.add_child(body_label)

func _apply_accessibility_settings(settings: RefCounted) -> void:
	var panel_size: Vector2 = settings.scaled_hud_panel_size(BASE_PANEL_SIZE)
	var body_size: Vector2 = settings.scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)
	custom_minimum_size = panel_size
	size = panel_size
	position = Vector2(-panel_size.x * 0.5, -panel_size.y * 0.5)
	title_label.add_theme_font_size_override("font_size", settings.scaled_hud_font_size(BASE_FONT_SIZE + 2))
	body_label.add_theme_font_size_override("font_size", settings.scaled_hud_font_size(BASE_FONT_SIZE))
	body_label.custom_minimum_size = body_size
	body_label.size = body_size
