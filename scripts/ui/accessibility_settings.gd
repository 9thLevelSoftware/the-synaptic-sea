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
## 2. The headless overrides `synapse_sea/accessibility/text_scale` project setting.
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
const PROJECT_SETTING_KEY: String = "synapse_sea/accessibility/text_scale"
const ENV_VAR_NAME: String = "SYNAPSE_SEA_TEXT_SCALE"

# REQ-UI-008 / ADR-0033: extended accessibility seam. New fields live on
# the same instance so the existing text-scale smoke and the
# A11Y-P1-001 contract stay green. Defaults reproduce the pre-package
# behaviour exactly: text_scale=1.0, colorblind_mode="none",
# motion_reduce=false, captions=true, hold_to_tap=false,
# preset_id="default", difficulty="standard", glyph_scheme="auto".
const VALID_COLORBLIND_MODES: Array[String] = ["none", "protanopia", "deuteranopia", "tritanopia"]
const VALID_DIFFICULTIES: Array[String] = ["standard", "hardened", "deep_dive"]
const VALID_GLYPH_SCHEMES: Array[String] = ["auto", "keyboard", "gamepad_xbox", "gamepad_ps"]
const DEFAULT_PRESET_ID: String = "default"

var _text_scale: float = DEFAULT_TEXT_SCALE
var _colorblind_mode: String = "none"
var _motion_reduce: bool = false
var _captions: bool = true
var _hold_to_tap: bool = false
var _preset_id: String = DEFAULT_PRESET_ID
var _difficulty: String = "standard"
var _glyph_scheme: String = "auto"

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

## --- REQ-UI-008 / ADR-0033 extended accessibility fields ---
## All getters / setters clamp / validate against the allowlist so a
## malformed input never produces an invalid state. The defaults are
## chosen so the existing A11Y-P1-001 text-scale smoke stays green.

func get_colorblind_mode() -> String:
	return _colorblind_mode

func set_colorblind_mode(mode: String) -> void:
	if VALID_COLORBLIND_MODES.has(mode):
		_colorblind_mode = mode

func is_motion_reduce() -> bool:
	return _motion_reduce

func set_motion_reduce(value: bool) -> void:
	_motion_reduce = value

func is_captions_enabled() -> bool:
	return _captions

func set_captions_enabled(value: bool) -> void:
	_captions = value

func is_hold_to_tap() -> bool:
	return _hold_to_tap

func set_hold_to_tap(value: bool) -> void:
	_hold_to_tap = value

func get_preset_id() -> String:
	return _preset_id

func set_preset_id(id: String) -> void:
	if not id.is_empty():
		_preset_id = id

func get_difficulty() -> String:
	return _difficulty

func set_difficulty(difficulty: String) -> void:
	if VALID_DIFFICULTIES.has(difficulty):
		_difficulty = difficulty

func get_glyph_scheme() -> String:
	return _glyph_scheme

func set_glyph_scheme(scheme: String) -> void:
	if VALID_GLYPH_SCHEMES.has(scheme):
		_glyph_scheme = scheme

## Difficulty multiplier (REQ-UI-014). 1.0 = standard; the higher presets
## multiply hazard drain / spawn rate. Returns 1.0 for an unknown preset
## so a malformed catalog entry never causes a divide-by-zero downstream.
func get_difficulty_multiplier() -> float:
	match _difficulty:
		"standard": return 1.0
		"hardened": return 1.5
		"deep_dive": return 2.0
	return 1.0

## Apply a full preset dict to this instance. Used by the settings menu
## after loading `data/ui/accessibility_presets.json`. Unknown keys are
## ignored; out-of-range values are clamped.
func apply_preset_dict(preset: Dictionary) -> void:
	if preset == null:
		return
	if preset.has("text_scale"):
		set_text_scale(float(preset.get("text_scale", DEFAULT_TEXT_SCALE)))
	if preset.has("colorblind_mode"):
		set_colorblind_mode(str(preset.get("colorblind_mode", "none")))
	if preset.has("motion_reduce"):
		set_motion_reduce(bool(preset.get("motion_reduce", false)))
	if preset.has("captions"):
		set_captions_enabled(bool(preset.get("captions", true)))
	if preset.has("hold_to_tap"):
		set_hold_to_tap(bool(preset.get("hold_to_tap", false)))
	if preset.has("difficulty"):
		set_difficulty(str(preset.get("difficulty", "standard")))
	if preset.has("glyph_scheme"):
		set_glyph_scheme(str(preset.get("glyph_scheme", "auto")))
	if preset.has("id"):
		set_preset_id(str(preset.get("id", DEFAULT_PRESET_ID)))
