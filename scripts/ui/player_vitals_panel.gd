extends Control
class_name PlayerVitalsPanel

## Bottom-left player-vitals HUD panel (Phase 7 sub-project C). Presentation only:
## the coordinator pushes pre-formatted ASCII lines via set_status_lines; this node
## renders them in a styled panel. No model access. Mirrors ObjectiveTracker's node
## construction (PanelContainer -> MarginContainer -> autowrap Label).
##
## A11Y parity (ADR-0027): font/panel/label sizes derive from an owned
## AccessibilitySettings instance, exactly like ObjectiveTracker. Default
## scale=1.0 reproduces the prior hard-coded sizes pixel-for-pixel. Because the
## panel is anchored BOTTOM_LEFT, its Y offset is computed from the SCALED panel
## height so a larger scale grows the panel upward from a fixed bottom margin
## instead of overflowing the screen bottom.

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")

const BASE_PANEL_SIZE: Vector2 = Vector2(360.0, 150.0)
const BASE_LABEL_MIN_SIZE: Vector2 = Vector2(320.0, 0.0)
const BASE_HUD_FONT_SIZE: int = 18
const LEFT_MARGIN: float = 18.0
const BOTTOM_MARGIN: float = 18.0
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var panel: PanelContainer
var margin: MarginContainer
var label: Label
# A11Y parity (ADR-0027): owned AccessibilitySettings; default scale=1.0
# preserves the prior hard-coded layout exactly. Replace via
# apply_accessibility_settings() to enlarge the panel text.
var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var _anchored: bool = false

func _ready() -> void:
	_ensure_nodes()

func set_status_lines(lines: PackedStringArray) -> void:
	_ensure_nodes()
	label.text = "\n".join(lines)

func get_hud_text() -> String:
	if label == null:
		return ""
	return label.text

## A11Y parity (ADR-0027): re-apply panel/label/font sizes from the supplied
## settings, updating existing nodes in place. Idempotent. Safe to call before
## _ready (stores the settings; _ready builds the nodes at the stored scale).
func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if label != null:
		_apply_scaled_layout()

func _ensure_nodes() -> void:
	if not _anchored:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_anchored = true
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "VitalsPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "VitalsMargin"
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		panel.add_child(margin)
	if label == null:
		label = Label.new()
		label.name = "VitalsLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)
	_apply_scaled_layout()

func _apply_scaled_layout() -> void:
	var scaled_panel: Vector2 = accessibility_settings.scaled_hud_panel_size(BASE_PANEL_SIZE)
	var scaled_label_min: Vector2 = accessibility_settings.scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)
	var scaled_font: int = accessibility_settings.scaled_hud_font_size(BASE_HUD_FONT_SIZE)
	custom_minimum_size = scaled_panel
	size = scaled_panel
	# Bottom-anchored: grow upward from a fixed bottom margin so a larger scale
	# does not push the panel off the bottom edge.
	position = Vector2(LEFT_MARGIN, -(scaled_panel.y + BOTTOM_MARGIN))
	if panel != null:
		panel.size = scaled_panel
		panel.custom_minimum_size = scaled_panel
	if label != null:
		label.custom_minimum_size = scaled_label_min
		label.size = scaled_label_min
		label.add_theme_font_size_override("font_size", scaled_font)
