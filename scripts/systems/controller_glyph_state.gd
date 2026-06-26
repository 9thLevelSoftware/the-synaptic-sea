extends RefCounted
class_name ControllerGlyphState
## Pure controller glyph resolver (REQ-UI-007 / ADR-0033).
##
## Owns per-scheme glyph maps loaded from `data/ui/input_glyphs.json`.
## `glyph_for(action_name, scheme)` returns the glyph text for the
## requested scheme and falls back to `keyboard` when the scheme key
## is missing or the action is unknown.
##
## The bindings table is a per-action list of keycodes read from the
## engine's InputMap; the glyph resolver does NOT bind inputs, it only
## reflects what the engine already has. The MenuCoordinator owns the
## `bindings_table` (read from `playable.get_input_action_keycodes_for_validation`).
##
## Pure-model-first: no scene-tree access.

const ControllerGlyphSchemaScript := preload("res://scripts/schemas/controller_glyph_schema.gd")

const SCHEMA_VERSION: String = "controller-glyph-state-1"
const SAVE_KEY: String = "controller_glyph_state"
const FALLBACK_SCHEME: String = "keyboard"
const VALID_SCHEMES: Array[String] = ["auto", "keyboard", "gamepad_xbox", "gamepad_ps"]

var _default_scheme: String = "auto"
var _fallback_scheme: String = FALLBACK_SCHEME
var _glyphs: Dictionary = {}                # action_name -> {scheme -> glyph}
var _action_names: Array = []
var _bindings: Dictionary = {}              # action_name -> Array of keycodes (int)

func configure(glyph_table: Dictionary, bindings_table: Dictionary = {}) -> bool:
	if not ControllerGlyphSchemaScript.validate(glyph_table):
		return false
	var dict: Dictionary = glyph_table
	_default_scheme = str(dict.get("default_scheme", "auto"))
	_fallback_scheme = str(dict.get("fallback_scheme", FALLBACK_SCHEME))
	_glyphs.clear()
	_action_names.clear()
	for action in (dict.get("actions", []) as Array):
		var action_dict: Dictionary = action
		var action_name: String = str(action_dict.get("action", ""))
		var schemes_dict: Dictionary = action_dict.get("schemes", {})
		_action_names.append(action_name)
		_glyphs[action_name] = {}
		for scheme_name in schemes_dict.keys():
			(_glyphs[action_name] as Dictionary)[String(scheme_name)] = String(schemes_dict[scheme_name])
	_bindings.clear()
	if bindings_table != null and typeof(bindings_table) == TYPE_DICTIONARY:
		for action_name in bindings_table.keys():
			var bindings_variant: Variant = bindings_table[action_name]
			var bindings_list: Array = []
			if typeof(bindings_variant) == TYPE_ARRAY:
				for keycode in (bindings_variant as Array):
					bindings_list.append(int(keycode))
			_bindings[String(action_name)] = bindings_list
	return true

func set_bindings(bindings_table: Dictionary) -> void:
	_bindings.clear()
	if bindings_table == null or typeof(bindings_table) != TYPE_DICTIONARY:
		return
	for action_name in bindings_table.keys():
		var bindings_variant: Variant = bindings_table[action_name]
		var bindings_list: Array = []
		if typeof(bindings_variant) == TYPE_ARRAY:
			for keycode in (bindings_variant as Array):
				bindings_list.append(int(keycode))
		_bindings[String(action_name)] = bindings_list

func get_action_names() -> Array:
	return _action_names.duplicate()

func get_default_scheme() -> String:
	return _default_scheme

func get_fallback_scheme() -> String:
	return _fallback_scheme

func is_known_action(action_name: String) -> bool:
	return action_name in _action_names

func get_bindings_for(action_name: String) -> Array:
	if not _bindings.has(action_name):
		return []
	return (_bindings[action_name] as Array).duplicate()

## Returns the glyph text for an action under the requested scheme.
## Falls back to `keyboard` when the scheme key is missing. Returns
## `""` (empty string) for unknown actions so callers can render a
## placeholder without bookkeeping.
func glyph_for(action_name: String, scheme: String = "auto") -> String:
	if not is_known_action(action_name):
		return ""
	var schemes_dict: Dictionary = _glyphs.get(action_name, {})
	if schemes_dict.has(scheme):
		return String(schemes_dict[scheme])
	if schemes_dict.has(_fallback_scheme):
		return String(schemes_dict[_fallback_scheme])
	return ""

## Resolve the requested scheme to a concrete scheme: `auto` becomes
## `gamepad_xbox` when any gamepad is connected (read from
## `Input.get_connected_joypads()`), else `keyboard`. This is the
## path the UI shell coordinator uses to pick a scheme.
func resolve_scheme(scheme: String) -> String:
	if scheme != "auto":
		return scheme
	if Input.get_connected_joypads().size() > 0:
		return "gamepad_xbox"
	return _fallback_scheme

func get_summary() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"default_scheme": _default_scheme,
		"fallback_scheme": _fallback_scheme,
		"action_count": _action_names.size(),
		"bindings_count": _bindings.size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	if str(summary.get("schema", "")) != SCHEMA_VERSION:
		return false
	_default_scheme = str(summary.get("default_scheme", "auto"))
	_fallback_scheme = str(summary.get("fallback_scheme", FALLBACK_SCHEME))
	if not VALID_SCHEMES.has(_default_scheme):
		_default_scheme = "auto"
	if not VALID_SCHEMES.has(_fallback_scheme):
		_fallback_scheme = FALLBACK_SCHEME
	return true

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("ControllerGlyphState: actions=%d default=%s fallback=%s bindings=%d" % [
		_action_names.size(),
		_default_scheme,
		_fallback_scheme,
		_bindings.size(),
	])
	return lines