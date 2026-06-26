extends RefCounted
class_name SettingsState
## Pure settings state (REQ-UI-003 / REQ-UI-008 / ADR-0033).
##
## Owns a flat Dictionary of typed fields and provides:
##   - typed getters / setters for each field
##   - `apply_to_accessibility(a11y)` — single write-back path to the
##     existing `AccessibilitySettings` instance (never creates a duplicate)
##   - `get_summary` / `apply_summary` for save/load round-trip
##   - `apply_preset_dict` — apply a preset loaded from
##     `data/ui/accessibility_presets.json`
##
## Pure-model-first: no scene-tree access. The settings menu is a thin
## Control view over this state object; the only writer to
## AccessibilitySettings is `apply_to_accessibility`, so the
## "single accessibility seam" invariant is preserved.
##
## The schema is enforced by `SettingsStateSchema.validate` on every
## setter so a malformed value can never produce an invalid state.

const SettingsStateSchemaScript := preload("res://scripts/schemas/settings_state_schema.gd")

const SAVE_KEY: String = "settings_state"

var _payload: Dictionary = SettingsStateSchemaScript.default_payload()

## Apply a fully-formed settings payload (from the catalog or a save).
## `validate()` is called on the input; rejected payloads leave the
## state unchanged.
func configure(payload: Dictionary) -> bool:
	if not SettingsStateSchemaScript.validate(payload):
		return false
	_payload = SettingsStateSchemaScript.sanitize(payload)
	return true

## Apply a partial payload (e.g. one row from the settings menu).
## Unknown fields are ignored. The result is always schema-valid
## because `sanitize` fills missing fields from defaults.
func apply_partial(partial: Dictionary) -> bool:
	if partial == null:
		return false
	# Build a merged payload: existing + new, then sanitize.
	var merged: Dictionary = _payload.duplicate(true)
	for key in partial.keys():
		merged[String(key)] = partial[key]
	merged = SettingsStateSchemaScript.sanitize(merged)
	if not SettingsStateSchemaScript.validate(merged):
		return false
	_payload = merged
	return true

func get_payload() -> Dictionary:
	return _payload.duplicate(true)

## --- typed getters ---
func get_text_scale() -> float:
	return float(_payload.get("text_scale", 1.0))

func get_colorblind_mode() -> String:
	return String(_payload.get("colorblind_mode", "none"))

func is_motion_reduce() -> bool:
	return bool(_payload.get("motion_reduce", false))

func is_captions_enabled() -> bool:
	return bool(_payload.get("captions", true))

func is_hold_to_tap() -> bool:
	return bool(_payload.get("hold_to_tap", false))

func get_difficulty() -> String:
	return String(_payload.get("difficulty", "standard"))

func get_glyph_scheme() -> String:
	return String(_payload.get("glyph_scheme", "auto"))

func get_preset_id() -> String:
	return String(_payload.get("preset_id", "default"))

## --- typed setters (return true when the value was accepted) ---
func set_text_scale(scale: float) -> bool:
	if scale < SettingsStateSchemaScript.MIN_TEXT_SCALE or scale > SettingsStateSchemaScript.MAX_TEXT_SCALE:
		return false
	_payload["text_scale"] = clampf(scale, SettingsStateSchemaScript.MIN_TEXT_SCALE, SettingsStateSchemaScript.MAX_TEXT_SCALE)
	return true

func set_colorblind_mode(mode: String) -> bool:
	if not SettingsStateSchemaScript.COLORBLIND_MODES.has(mode):
		return false
	_payload["colorblind_mode"] = mode
	return true

func set_motion_reduce(value: bool) -> bool:
	_payload["motion_reduce"] = value
	return true

func set_captions_enabled(value: bool) -> bool:
	_payload["captions"] = value
	return true

func set_hold_to_tap(value: bool) -> bool:
	_payload["hold_to_tap"] = value
	return true

func set_difficulty(difficulty: String) -> bool:
	if not SettingsStateSchemaScript.DIFFICULTIES.has(difficulty):
		return false
	_payload["difficulty"] = difficulty
	return true

func set_glyph_scheme(scheme: String) -> bool:
	if not SettingsStateSchemaScript.GLYPH_SCHEMES.has(scheme):
		return false
	_payload["glyph_scheme"] = scheme
	return true

func set_preset_id(id: String) -> bool:
	if id.is_empty():
		return false
	_payload["preset_id"] = id
	return true

## Apply a preset dict (from `data/ui/accessibility_presets.json`).
## The preset may carry any subset of fields; missing fields stay at
## their current values.
func apply_preset_dict(preset: Dictionary) -> bool:
	if preset == null:
		return false
	var merged: Dictionary = _payload.duplicate(true)
	if preset.has("id"):
		merged["preset_id"] = str(preset.get("id", "default"))
	if preset.has("text_scale"):
		merged["text_scale"] = float(preset.get("text_scale", 1.0))
	if preset.has("colorblind_mode"):
		merged["colorblind_mode"] = str(preset.get("colorblind_mode", "none"))
	if preset.has("motion_reduce"):
		merged["motion_reduce"] = bool(preset.get("motion_reduce", false))
	if preset.has("captions"):
		merged["captions"] = bool(preset.get("captions", true))
	if preset.has("hold_to_tap"):
		merged["hold_to_tap"] = bool(preset.get("hold_to_tap", false))
	if preset.has("difficulty"):
		merged["difficulty"] = str(preset.get("difficulty", "standard"))
	if preset.has("glyph_scheme"):
		merged["glyph_scheme"] = str(preset.get("glyph_scheme", "auto"))
	merged = SettingsStateSchemaScript.sanitize(merged)
	if not SettingsStateSchemaScript.validate(merged):
		return false
	_payload = merged
	return true

## Write back to an `AccessibilitySettings` instance. This is the ONLY
## path that should write to AccessibilitySettings from settings code;
## every other caller goes through `apply_to_accessibility` to keep
## the seam single. Returns true when the write completed (a11y is
## always valid because setters clamp on their own).
func apply_to_accessibility(a11y: RefCounted) -> bool:
	if a11y == null:
		return false
	if not (a11y.has_method("set_text_scale") and a11y.has_method("set_colorblind_mode")):
		push_warning("SettingsState: apply_to_accessibility argument is not an AccessibilitySettings")
		return false
	a11y.set_text_scale(get_text_scale())
	a11y.set_colorblind_mode(get_colorblind_mode())
	a11y.set_motion_reduce(is_motion_reduce())
	a11y.set_captions_enabled(is_captions_enabled())
	a11y.set_hold_to_tap(is_hold_to_tap())
	a11y.set_difficulty(get_difficulty())
	a11y.set_glyph_scheme(get_glyph_scheme())
	a11y.set_preset_id(get_preset_id())
	return true

## Round-trip seam.
func get_summary() -> Dictionary:
	return _payload.duplicate(true)

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	var sanitized: Dictionary = SettingsStateSchemaScript.sanitize(summary)
	if not SettingsStateSchemaScript.validate(sanitized):
		return false
	_payload = sanitized
	return true

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("SettingsState: text_scale=%.2f colorblind=%s motion_reduce=%s captions=%s hold_to_tap=%s" % [
		get_text_scale(),
		get_colorblind_mode(),
		str(is_motion_reduce()),
		str(is_captions_enabled()),
		str(is_hold_to_tap()),
	])
	lines.append("  difficulty=%s glyph_scheme=%s preset_id=%s" % [
		get_difficulty(),
		get_glyph_scheme(),
		get_preset_id(),
	])
	return lines