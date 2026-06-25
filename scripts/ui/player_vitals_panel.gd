extends Control
class_name PlayerVitalsPanel

## Bottom-left player-vitals HUD panel (Phase 7 sub-project C). Presentation only:
## the coordinator pushes pre-formatted ASCII lines via set_status_lines; this node
## renders them in a styled panel. No model access. Mirrors ObjectiveTracker's node
## construction (PanelContainer -> MarginContainer -> autowrap Label).

const PANEL_POSITION: Vector2 = Vector2(18.0, -168.0)
const PANEL_SIZE: Vector2 = Vector2(360.0, 150.0)
const LABEL_MIN_SIZE: Vector2 = Vector2(320.0, 0.0)
const HUD_FONT_SIZE: int = 18
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var panel: PanelContainer
var margin: MarginContainer
var label: Label
var _laid_out: bool = false

func _ready() -> void:
	_ensure_nodes()

func set_status_lines(lines: PackedStringArray) -> void:
	_ensure_nodes()
	label.text = "\n".join(lines)

func get_hud_text() -> String:
	if label == null:
		return ""
	return label.text

func _ensure_nodes() -> void:
	if not _laid_out:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		position = PANEL_POSITION
		custom_minimum_size = PANEL_SIZE
		_laid_out = true
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "VitalsPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
		panel.size = PANEL_SIZE
		panel.custom_minimum_size = PANEL_SIZE
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
		label.custom_minimum_size = LABEL_MIN_SIZE
		label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)
