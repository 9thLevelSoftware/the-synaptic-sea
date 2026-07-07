extends RefCounted
class_name SettingsStateSchema
## Static validation for `SettingsState` payloads (REQ-UI-003 / ADR-0033).
## Live authority for settings payload shape; supersedes the deleted
## `data/ui/settings_schema.json` duplicate.
##
## A settings payload is a flat Dictionary of typed fields:
##
##   {
##     "schema": "settings-state-1",
##     "text_scale": 1.0,                    # float in [1.0, 2.0]
##     "colorblind_mode": "none",            # one of COLORBLIND_MODES
##     "motion_reduce": false,               # bool
##     "captions": true,                     # bool
##     "hold_to_tap": false,                 # bool
##     "difficulty": "standard",             # one of DIFFICULTIES
##     "glyph_scheme": "auto",               # one of GLYPH_SCHEMES
##     "preset_id": "default"                # non-empty string
##   }
##
## The schema rejects:
##   - wrong `schema` version (callers should not strip the version)
##   - text_scale outside [MIN_TEXT_SCALE, MAX_TEXT_SCALE]
##   - colorblind_mode outside the allowlist
##   - non-bool motion_reduce / captions / hold_to_tap
##   - difficulty outside the allowlist
##   - glyph_scheme outside the allowlist
##   - empty preset_id
##
## Unknown extra fields are ignored (forward-compat). Defaults are
## the pre-package values so a malformed / missing payload loads as
## the implicit baseline.

const SCHEMA_VERSION: String = "settings-state-1"

const COLORBLIND_MODES: Array[String] = ["none", "protanopia", "deuteranopia", "tritanopia"]
const DIFFICULTIES: Array[String] = ["standard", "hardened", "deep_dive"]
const GLYPH_SCHEMES: Array[String] = ["auto", "keyboard", "gamepad_xbox", "gamepad_ps"]

const MIN_TEXT_SCALE: float = 1.0
const MAX_TEXT_SCALE: float = 2.0
const DEFAULT_PRESET: String = "default"

static func validate(payload: Variant) -> bool:
	if payload == null or typeof(payload) != TYPE_DICTIONARY:
		push_error("SettingsStateSchema: payload must be a Dictionary; got %s" % typeof(payload))
		return false
	var dict: Dictionary = payload
	if str(dict.get("schema", "")) != SCHEMA_VERSION:
		push_error("SettingsStateSchema: schema version mismatch (expected %s)" % SCHEMA_VERSION)
		return false
	var text_scale: Variant = dict.get("text_scale", 1.0)
	if typeof(text_scale) != TYPE_FLOAT and typeof(text_scale) != TYPE_INT:
		push_error("SettingsStateSchema: text_scale must be a number")
		return false
	var scale_value: float = float(text_scale)
	if scale_value < MIN_TEXT_SCALE or scale_value > MAX_TEXT_SCALE:
		push_error("SettingsStateSchema: text_scale %.3f out of range [%.1f, %.1f]" % [scale_value, MIN_TEXT_SCALE, MAX_TEXT_SCALE])
		return false
	var colorblind: String = str(dict.get("colorblind_mode", "none"))
	if not COLORBLIND_MODES.has(colorblind):
		push_error("SettingsStateSchema: colorblind_mode '%s' is not in allowlist" % colorblind)
		return false
	var difficulty: String = str(dict.get("difficulty", "standard"))
	if not DIFFICULTIES.has(difficulty):
		push_error("SettingsStateSchema: difficulty '%s' is not in allowlist" % difficulty)
		return false
	var scheme: String = str(dict.get("glyph_scheme", "auto"))
	if not GLYPH_SCHEMES.has(scheme):
		push_error("SettingsStateSchema: glyph_scheme '%s' is not in allowlist" % scheme)
		return false
	var preset_id: String = str(dict.get("preset_id", DEFAULT_PRESET))
	if preset_id.is_empty():
		push_error("SettingsStateSchema: preset_id must not be empty")
		return false
	for bool_field in ["motion_reduce", "captions", "hold_to_tap"]:
		var value: Variant = dict.get(bool_field, false)
		if typeof(value) != TYPE_BOOL:
			push_error("SettingsStateSchema: %s must be a bool (got %s)" % [bool_field, typeof(value)])
			return false
	return true

## Returns the defaults dict used to bootstrap a brand-new state.
static func default_payload() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"text_scale": 1.0,
		"colorblind_mode": "none",
		"motion_reduce": false,
		"captions": true,
		"hold_to_tap": false,
		"difficulty": "standard",
		"glyph_scheme": "auto",
		"preset_id": DEFAULT_PRESET,
	}

## Returns a sanitized payload: missing fields are filled from defaults
## and out-of-range fields are clamped. Does not validate (use
## `validate` for that) but never produces an invalid payload.
static func sanitize(payload: Variant) -> Dictionary:
	var result: Dictionary = default_payload()
	if payload == null or typeof(payload) != TYPE_DICTIONARY:
		return result
	var dict: Dictionary = payload
	var scale_value: Variant = dict.get("text_scale", result["text_scale"])
	if typeof(scale_value) == TYPE_FLOAT or typeof(scale_value) == TYPE_INT:
		result["text_scale"] = clampf(float(scale_value), MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	var colorblind: String = str(dict.get("colorblind_mode", result["colorblind_mode"]))
	if COLORBLIND_MODES.has(colorblind):
		result["colorblind_mode"] = colorblind
	var difficulty: String = str(dict.get("difficulty", result["difficulty"]))
	if DIFFICULTIES.has(difficulty):
		result["difficulty"] = difficulty
	var scheme: String = str(dict.get("glyph_scheme", result["glyph_scheme"]))
	if GLYPH_SCHEMES.has(scheme):
		result["glyph_scheme"] = scheme
	var preset_id: String = str(dict.get("preset_id", result["preset_id"]))
	if not preset_id.is_empty():
		result["preset_id"] = preset_id
	for bool_field in ["motion_reduce", "captions", "hold_to_tap"]:
		var raw: Variant = dict.get(bool_field, result[bool_field])
		if typeof(raw) == TYPE_BOOL:
			result[bool_field] = raw
	return result
