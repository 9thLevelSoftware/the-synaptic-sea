extends RefCounted
class_name LocalizationCatalog

## REQ-RL-005 localization catalog.
##
## Pure data service. Loads `{language_id: {string_id: translation}}`
## from a Dictionary (read from JSON by the caller) and exposes
## `translate()` / `translate_fallback()` with deterministic fallback
## rules:
##
##  - unknown string_id            -> default text (or empty)
##  - unknown language_id          -> default language's text
##  - missing key inside known lang -> default language's text
##
## The HUD never goes blank because every fallback returns a non-empty
## string. The smoke locks down all three rules.

const DEFAULT_LANGUAGE: String = "en"

var _catalog: Dictionary = {}
var _default_language: String = DEFAULT_LANGUAGE
var _known_languages: Array = []

func configure(catalog: Dictionary, default_language: String = DEFAULT_LANGUAGE) -> void:
	_catalog.clear()
	_known_languages.clear()
	if catalog == null:
		catalog = {}
	_default_language = default_language if not default_language.is_empty() else DEFAULT_LANGUAGE
	if typeof(catalog) != TYPE_DICTIONARY:
		return
	for lang_id_variant in (catalog as Dictionary).keys():
		var lang_id: String = str(lang_id_variant)
		if lang_id.is_empty():
			continue
		var lang_dict_variant: Variant = catalog[lang_id_variant]
		if typeof(lang_dict_variant) != TYPE_DICTIONARY:
			continue
		_known_languages.append(lang_id)
		var lang_dict: Dictionary = {}
		for string_id_variant in (lang_dict_variant as Dictionary).keys():
			var string_id: String = str(string_id_variant)
			lang_dict[string_id] = str(lang_dict_variant[string_id_variant])
		_catalog[lang_id] = lang_dict
	if not _default_language in _known_languages:
		_known_languages.append(_default_language)
		if not _catalog.has(_default_language):
			_catalog[_default_language] = {}

func translate(string_id: String, language_id: String) -> String:
	if string_id.is_empty():
		return ""
	if _catalog.has(language_id):
		var lang_dict: Dictionary = _catalog[language_id]
		if lang_dict.has(string_id):
			return str(lang_dict[string_id])
	# Fall back to default language.
	if _catalog.has(_default_language):
		var default_dict: Dictionary = _catalog[_default_language]
		if default_dict.has(string_id):
			return str(default_dict[string_id])
	return ""

func translate_fallback(string_id: String, default_text: String, language_id: String) -> String:
	if string_id.is_empty():
		return default_text
	var translated: String = translate(string_id, language_id)
	if translated.is_empty():
		return default_text
	return translated

func has_translation(string_id: String, language_id: String) -> bool:
	if not _catalog.has(language_id):
		return false
	var lang_dict: Dictionary = _catalog[language_id]
	return lang_dict.has(string_id)

func get_known_languages() -> Array:
	return _known_languages.duplicate()

func get_default_language() -> String:
	return _default_language

func get_translation_count() -> int:
	var count: int = 0
	for lang_id in _known_languages:
		if _catalog.has(lang_id):
			count += (_catalog[lang_id] as Dictionary).size()
	return count

func get_summary() -> Dictionary:
	return {
		"default_language": _default_language,
		"known_languages": _known_languages.duplicate(),
		"translation_count": get_translation_count(),
	}