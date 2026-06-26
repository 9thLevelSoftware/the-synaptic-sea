extends Control
class_name ObjectiveTracker
# A11Y-P1-001: HUD sizing and font size are derived from a single
# AccessibilitySettings instance. The hard-coded constants below are the
# "1.0x" baseline; at scale=N they are multiplied by N. The default
# AccessibilitySettings() reads scale=1.0, so the visual output is
# identical to the prior hard-coded implementation until a caller
# (smoke, settings menu, future card) swaps in a larger scale.

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")

const HUD_POSITION: Vector2 = Vector2(18.0, 18.0)
const BASE_HUD_SIZE: Vector2 = Vector2(520.0, 250.0)
const BASE_LABEL_MIN_SIZE: Vector2 = Vector2(480.0, 0.0)
const BASE_HUD_FONT_SIZE: int = 18
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)
const COMPLETE_COLOR: Color = Color(0.35, 1.0, 0.55, 1.0)

var panel: PanelContainer
var margin: MarginContainer
var label: Label
var objectives: Array = []
var completed_sequences: Dictionary = {}
var run_complete: bool = false
var current_sequence: int = 1
var interaction_prompt: String = "Approach the highlighted objective and press E."
var system_status_lines: PackedStringArray = PackedStringArray()
var current_step_progress: Dictionary = {}
# A11Y-P1-001: owned AccessibilitySettings instance. Default scale=1.0
# preserves the prior hard-coded HUD layout exactly. Replace via
# apply_accessibility_settings() to enlarge HUD text.
var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_scaled_layout()
	_ensure_nodes()
	_refresh()

## A11Y-P1-001: re-apply HUD sizing + label font size from the supplied
## accessibility settings. Existing nodes are updated in place so callers
## do not have to rebuild the HUD. Idempotent; safe to call multiple times.
func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if label != null:
		var scaled_label_min: Vector2 = accessibility_settings.scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)
		# A11Y-P1-001: reset the label's size and min size to the new
		# scaled minimum so the autowrap Label can re-measure its content
		# after a font_size change. Without this, a Label that grew to
		# fit a larger font at scale=2.0 would stay at the larger height
		# when the scale drops back to 1.0, and the parent PanelContainer
		# would inherit the oversized height.
		label.custom_minimum_size = scaled_label_min
		label.size = scaled_label_min
		label.add_theme_font_size_override(
			"font_size",
			accessibility_settings.scaled_hud_font_size(BASE_HUD_FONT_SIZE)
		)
	# A11Y-P1-001: force the tracker and its children to re-emit their
	# minimum size after the label/panel were re-sized. This is the
	# documented Godot way to break out of a sticky PanelContainer height
	# that grew to fit previous-scale content. Must run BEFORE
	# _apply_scaled_layout so the panel/tracker's custom_minimum_size
	# reset actually takes effect.
	if is_inside_tree():
		update_minimum_size()
		if panel != null:
			panel.update_minimum_size()
	_apply_scaled_layout()

func _apply_scaled_layout() -> void:
	var scaled_size: Vector2 = accessibility_settings.scaled_hud_panel_size(BASE_HUD_SIZE)
	position = HUD_POSITION
	size = scaled_size
	custom_minimum_size = scaled_size
	# A11Y-P1-001: clip the tracker so the panel cannot visually overflow
	# the HUD bounds even when the autowrapped label content grows. The
	# panel's `custom_minimum_size` is reset to the new scaled size in
	# apply_accessibility_settings, but PanelContainer can still grow
	# temporarily between frames; clipping keeps the HUD box invariant.
	clip_contents = true
	if panel != null:
		panel.size = scaled_size
		panel.custom_minimum_size = scaled_size

func set_objectives(objective_list: Array) -> void:
	objectives = objective_list.duplicate(true)
	completed_sequences.clear()
	run_complete = false
	current_sequence = 1
	interaction_prompt = "Approach the highlighted objective and press E."
	system_status_lines = PackedStringArray()
	_refresh()

func set_system_status_lines(lines: PackedStringArray) -> void:
	system_status_lines = PackedStringArray()
	for line in lines:
		system_status_lines.append(String(line))
	_refresh()

func set_current_sequence(sequence: int) -> void:
	current_sequence = max(sequence, 1)
	_refresh()

func set_step_progress(_sequence: int, progress: Dictionary) -> void:
	current_step_progress = progress.duplicate(true)
	_refresh()

func set_interaction_prompt(text: String) -> void:
	interaction_prompt = text
	_refresh()

func mark_completed(sequence: int) -> void:
	completed_sequences[sequence] = true
	_refresh()

func mark_run_complete() -> void:
	run_complete = true
	interaction_prompt = "Slice complete. Extraction route found."
	_refresh()

func get_completed_count() -> int:
	return completed_sequences.size()

func is_sequence_completed(sequence: int) -> bool:
	return completed_sequences.has(sequence)

func get_hud_text() -> String:
	if label == null:
		return _compose_text()
	return label.text

func _ensure_nodes() -> void:
	var scaled_size: Vector2 = accessibility_settings.scaled_hud_panel_size(BASE_HUD_SIZE)
	var scaled_label_min: Vector2 = accessibility_settings.scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "ObjectivePanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
		panel.size = scaled_size
		panel.custom_minimum_size = scaled_size
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
		margin.name = "ObjectiveMargin"
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		panel.add_child(margin)
	if label == null:
		label = Label.new()
		label.name = "ObjectiveLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.custom_minimum_size = scaled_label_min
		label.size = scaled_label_min
		label.add_theme_font_size_override("font_size", accessibility_settings.scaled_hud_font_size(BASE_HUD_FONT_SIZE))
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)

func _refresh() -> void:
	_ensure_nodes()
	label.text = _compose_text()
	label.add_theme_color_override("font_color", COMPLETE_COLOR if run_complete else Color.WHITE)

func _compose_text() -> String:
	# A11Y-P1-002: HUD prompt advertises both the original WASD/E keys and
	# the alternate arrow-key / Enter / Space bindings that are registered
	# alongside them on the same InputMap actions. Save/load (F5 / F9) is
	# mentioned so the discoverable key list stays accurate after the
	# alternate-binding expansion.
	const CONTROLS_LINE: String = "Controls: WASD or Arrows move / E or Enter or Space interact / F5 save / F9 load"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Synaptic Sea First Playable")
	lines.append(CONTROLS_LINE)
	lines.append("Progress: %d/%d" % [completed_sequences.size(), objectives.size()])
	if system_status_lines.size() > 0:
		lines.append("Systems:")
		for system_line in system_status_lines:
			lines.append("  %s" % String(system_line))
	if run_complete:
		lines.append("Current: COMPLETE - Extraction route found")
	else:
		lines.append("Current: %s" % _current_objective_display())
	lines.append("Prompt: %s" % interaction_prompt)
	return "\n".join(lines)

func _current_objective_display() -> String:
	for objective_variant in objectives:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		if sequence == current_sequence:
			var required_steps: int = int(current_step_progress.get("required_steps", 1))
			var completed_steps: int = int(current_step_progress.get("completed_steps", 0))
			var base: String = _objective_label(objective)
			if required_steps > 1:
				base = "%s (%d/%d)" % [base, completed_steps, required_steps]
			return "%02d %s @ %s" % [
				sequence,
				base,
				_room_display(str(objective.get("room_id", "room"))),
			]
	return "%02d Objective" % current_sequence

# Player-facing HUD label for an objective. REQ-011 requires `kind ==
# "repair_junction" to show as "Repair junction" even though the ship-system
# `type` stays "restore_systems" (the objective bridge maps it to manager
# repairs + route-control integration).
func _objective_label(objective: Dictionary) -> String:
	var kind: String = str(objective.get("kind", ""))
	if kind == "repair_junction":
		return "Repair junction"
	return _type_display(str(objective.get("type", "objective")))

func _type_display(raw_type: String) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part in raw_type.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)

func _room_display(room_id: String) -> String:
	return room_id.replace("_", " ").capitalize()
