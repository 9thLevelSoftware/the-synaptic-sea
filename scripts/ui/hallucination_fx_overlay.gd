extends CanvasLayer
class_name HallucinationFXOverlay

## ADR-0042 Task 5: lightweight screen-FX overlay for sanity hallucinations.
##
## A full-rect red ColorRect whose alpha follows the `hallucination_intensity` meta
## (0..1) that HallucinationManager writes each frame. This is a deliberately minimal
## tint — richer shader distortion is a non-goal for v1. The manager owns the
## intensity value (derived from the sanity tier); this node only renders it.

const MAX_TINT_ALPHA: float = 0.35

var _tint: ColorRect

func _ready() -> void:
	layer = 90
	set_meta("hallucination_intensity", float(get_meta("hallucination_intensity", 0.0)))
	_tint = ColorRect.new()
	_tint.name = "Tint"
	_tint.color = Color(0.6, 0.0, 0.05, 1.0)
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_tint)

func _process(_delta: float) -> void:
	if _tint == null or not is_instance_valid(_tint):
		return
	var intensity: float = clampf(float(get_meta("hallucination_intensity", 0.0)), 0.0, 1.0)
	_tint.modulate = Color(1.0, 1.0, 1.0, intensity * MAX_TINT_ALPHA)
