extends RefCounted
class_name ControllerGlyphSchema
## Static validation for `ControllerGlyphState` catalogs
## (REQ-UI-007 / ADR-0033).
##
## A glyph table is a JSON document with the following shape:
##
##   {
##     "version": "controller-glyphs-1",
##     "default_scheme": "auto",
##     "fallback_scheme": "keyboard",
##     "actions": [
##       {
##         "action": "interact",
##         "schemes": {
##           "keyboard":     "[E]",
##           "gamepad_xbox": "[A]",
##           "gamepad_ps":   "[Cross]"
##         }
##       },
##       ...
##     ]
##   }
##
## The schema rejects:
##   - missing / non-Dictionary root
##   - wrong `version`
##   - non-Array `actions`
##   - entry missing `action` or `schemes`
##   - `schemes` not a Dictionary
##   - empty `action` string
##   - duplicate `action` across entries
##   - `default_scheme` / `fallback_scheme` not in {auto, keyboard, gamepad_xbox, gamepad_ps}

const SCHEMA_VERSION: String = "controller-glyphs-1"
const VALID_SCHEMES: Array[String] = ["auto", "keyboard", "gamepad_xbox", "gamepad_ps"]

static func validate(table: Variant) -> bool:
	if table == null or typeof(table) != TYPE_DICTIONARY:
		push_error("ControllerGlyphSchema: table must be a Dictionary; got %s" % typeof(table))
		return false
	var dict: Dictionary = table
	if str(dict.get("version", "")) != SCHEMA_VERSION:
		push_error("ControllerGlyphSchema: version mismatch (expected %s)" % SCHEMA_VERSION)
		return false
	var default_scheme: String = str(dict.get("default_scheme", "auto"))
	if not VALID_SCHEMES.has(default_scheme):
		push_error("ControllerGlyphSchema: default_scheme '%s' is invalid" % default_scheme)
		return false
	var fallback_scheme: String = str(dict.get("fallback_scheme", "keyboard"))
	if not VALID_SCHEMES.has(fallback_scheme):
		push_error("ControllerGlyphSchema: fallback_scheme '%s' is invalid" % fallback_scheme)
		return false
	var actions_variant: Variant = dict.get("actions", null)
	if typeof(actions_variant) != TYPE_ARRAY:
		push_error("ControllerGlyphSchema: 'actions' must be an Array")
		return false
	var actions: Array = actions_variant
	var seen_actions: Dictionary = {}
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			push_error("ControllerGlyphSchema: action entry must be a Dictionary")
			return false
		var action_dict: Dictionary = action
		var action_name: String = str(action_dict.get("action", ""))
		if action_name.is_empty():
			push_error("ControllerGlyphSchema: action missing 'action'")
			return false
		if seen_actions.has(action_name):
			push_error("ControllerGlyphSchema: duplicate action '%s'" % action_name)
			return false
		seen_actions[action_name] = true
		var schemes: Variant = action_dict.get("schemes", null)
		if typeof(schemes) != TYPE_DICTIONARY:
			push_error("ControllerGlyphSchema: action '%s' missing 'schemes' Dictionary" % action_name)
			return false
		for scheme_name in (schemes as Dictionary).keys():
			if not VALID_SCHEMES.has(String(scheme_name)) and String(scheme_name) != "auto":
				push_error("ControllerGlyphSchema: action '%s' has invalid scheme '%s'" % [action_name, String(scheme_name)])
				return false
	return true