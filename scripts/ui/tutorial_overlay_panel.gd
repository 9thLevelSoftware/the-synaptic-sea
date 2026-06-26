extends PanelContainer
class_name TutorialOverlayPanel

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")
const BASE_PANEL_SIZE: Vector2 = Vector2(560.0, 110.0)
const BASE_FONT_SIZE: int = 16

var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.94)
	style.border_color = Color(0.88, 0.73, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.position = Vector2(12, 10)
	label.custom_minimum_size = Vector2(520, 84)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	visible = false
	apply_accessibility_settings(accessibility_settings)

func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if label == null:
		return
	var size_scaled: Vector2 = settings.scaled_hud_panel_size(BASE_PANEL_SIZE)
	custom_minimum_size = size_scaled
	size = size_scaled
	position = Vector2(180.0, 18.0)
	label.custom_minimum_size = settings.scaled_hud_minimum_size(Vector2(520, 84))
	label.add_theme_font_size_override("font_size", settings.scaled_hud_font_size(BASE_FONT_SIZE))

func show_tutorial(title: String, body: String) -> void:
	if label == null:
		return
	if title.is_empty() and body.is_empty():
		visible = false
		label.text = ""
		return
	visible = true
	label.text = "%s\n%s" % [title, body]
