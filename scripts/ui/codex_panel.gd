extends PanelContainer
class_name CodexPanel

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")
const BASE_PANEL_SIZE: Vector2 = Vector2(460.0, 320.0)
const BASE_FONT_SIZE: int = 16

var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	position = Vector2(-480.0, -160.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.07, 0.9)
	style.border_color = Color(0.18, 0.65, 1.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector2(12, 12)
	label.custom_minimum_size = Vector2(420, 280)
	add_child(label)
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
	position = Vector2(-size_scaled.x - 18.0, -size_scaled.y * 0.5)
	label.custom_minimum_size = settings.scaled_hud_minimum_size(Vector2(420, 280))
	label.add_theme_font_size_override("font_size", settings.scaled_hud_font_size(BASE_FONT_SIZE))

func set_entries(lines: PackedStringArray) -> void:
	if label != null:
		label.text = "\n".join(lines)
