extends RefCounted
class_name AccessibilitySettings
## A11Y-P1-001: single runtime seam for scalable HUD and world text.
##
## The Synapse Sea playable slice keeps pure gameplay state in RefCounted / Resource
## classes where practical. This settings object is a pure model — it owns a
## text scale multiplier and exposes helpers that turn that multiplier into the
## two different kinds of "larger text" we need:
##
## - Control nodes (HUD): `font_size` and `custom_minimum_size` are both
##   multiplied by the scale. The HUD's own size is also multiplied so the
##   content keeps fitting at the larger scale.
## - World Label3D nodes: `pixel_size` is DIVIDED by the scale. Label3D treats
##   `pixel_size` as world-units-per-screen-pixel, so a smaller pixel_size
##   renders a larger label on screen for the same world position.
##
## The scale multiplier is read from three sources, in order:
## 1. The `SYNAPSE_SEA_TEXT_SCALE` environment variable (CI /).
## 2. The headless overrides `synapse-sea/accessibility/text_scale` project setting.
## 3. A hard-coded default of 1.0.
##
## The value is clamped to [MIN_TEXT_SCALE, MAX_TEXT_SCALE] so a malformed env
## var or setting cannot blow up the layout or make text invisible.
##
## This is intentionally the smallest possible seam. It does NOT add a settings
## menu, persist user choices, or change the scene tree. It exists so the HUD
## and Label3D constructors can ask "how big should this text be?" and get one
## consistent answer.
##
## Usage:
##   var settings := AccessibilitySettings.new()
##   var font: int = settings.scaled_hud_font_size(18)
##   var pixel: float = settings.scaled_world_pixel_size(0.0035)

const MIN_TEXT_SCALE: float = 1.0
const MAX_TEXT_SCALE: float = 2.0
const DEFAULT_TEXT_SCALE: float = 1.0
const PROJECT_SETTING_KEY: String = "synapse-sea/accessibility/text_scale"
const ENV_VAR_NAME: String = "SYNAPSE_SEA_TEXT_SCALE"

var _text_scale: float = DEFAULT_TEXT_SCALE

func _init() -> void:
	_text_scale = _resolve_initial_scale()

## Current text scale multiplier in [MIN_TEXT_SCALE, MAX_TEXT_SCALE]. 1.0 is
## the default and reproduces the prior hard-coded text sizes exactly so the
## existing smokes stay green.
func get_text_scale() -> float:
	return _text_scale

## Override the scale at runtime (e.g. from a settings menu in a future
## card). Clamps to the supported range; ignores values <= 0.
func set_text_scale(new_scale: float) -> void:
	if new_scale <= 0.0:
		return
	_text_scale = clampf(new_scale, MIN_TEXT_SCALE, MAX_TEXT_SCALE)

## HUD font size for a base pixel value at the current scale, rounded to int.
func scaled_hud_font_size(base_font_size: int) -> int:
	return int(round(float(base_font_size) * _text_scale))

## HUD custom_minimum_size for a base size at the current scale.
func scaled_hud_minimum_size(base_size: Vector2) -> Vector2:
	return Vector2(base_size.x * _text_scale, base_size.y * _text_scale)

## HUD outer panel size for a base size at the current scale. Same formula as
## the minimum size, but exposed separately so the seam is explicit at the
## call site.
func scaled_hud_panel_size(base_size: Vector2) -> Vector2:
	return Vector2(base_size.x * _text_scale, base_size.y * _text_scale)

## World Label3D pixel_size for a base pixel_size at the current scale.
## Label3D treats `pixel_size` as world units per screen pixel, so dividing by
## the scale renders the label larger on screen for the same world position.
## Clamped to a documented minimum readable size so a malformed scale value
## can never produce an invisible (0 or negative) pixel_size.
func scaled_world_pixel_size(base_pixel_size: float) -> float:
	var raw: float = base_pixel_size / _text_scale
	return maxf(raw, 0.0005)

## Read the scale from env -> project setting -> default, in that order.
## Exposed as a static so the validation smoke can re-resolve without
## instantiating a duplicate RefCounted.
static func resolve_text_scale() -> float:
	return _clamp_scale(_read_env_scale(_read_project_setting_scale()))

func _resolve_initial_scale() -> float:
	return resolve_text_scale()

static func _read_env_scale(fallback: float) -> float:
	var raw: String = OS.get_environment(ENV_VAR_NAME)
	if raw.is_empty():
		return fallback
	var parsed: float = NAN
	# Try strict float parse first; fall back to letting Godot convert.
	if raw.is_valid_float():
		parsed = raw.to_float()
	if is_nan(parsed) or parsed <= 0.0:
		return fallback
	return parsed

static func _read_project_setting_scale() -> float:
	if not ProjectSettings.has_setting(PROJECT_SETTING_KEY):
		return DEFAULT_TEXT_SCALE
	var value: Variant = ProjectSettings.get_setting(PROJECT_SETTING_KEY, DEFAULT_TEXT_SCALE)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return DEFAULT_TEXT_SCALE
	var as_float: float = float(value)
	if as_float <= 0.0:
		return DEFAULT_TEXT_SCALE
	return as_float

static func _clamp_scale(value: float) -> float:
	return clampf(value, MIN_TEXT_SCALE, MAX_TEXT_SCALE)
