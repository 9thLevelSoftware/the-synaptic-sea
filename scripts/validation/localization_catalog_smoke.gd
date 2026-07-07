extends SceneTree

## REQ-RL-005 localization catalog smoke.
##
## Pure-model test for `LocalizationCatalog`. Asserts:
##  - catalog parses with at least one language (en) and >= 5 string ids
##  - `translate()` returns the translation when present
##  - unknown id returns empty / supplied fallback
##  - unknown language returns the default language's text
##  - missing key inside a known language returns the default text

const LocalizationCatalogScript := preload("res://scripts/systems/localization_catalog.gd")

func _initialize() -> void:
	var catalog_path: String = "res://data/release/localization_catalog.json"
	if not FileAccess.file_exists(catalog_path):
		_fail("catalog unreadable: %s" % catalog_path)
		return
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		_fail("catalog open failed: %s" % catalog_path)
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail("catalog parse failed: %s" % catalog_path)
		return

	var catalog := LocalizationCatalogScript.new()
	catalog.configure(parsed)

	var known_languages: Array = catalog.get_known_languages()
	if not "en" in known_languages:
		_fail("default language 'en' must be in known_languages; got %s" % str(known_languages))
		return
	if known_languages.size() < 1:
		_fail("known_languages is empty")
		return

	# Catalog must have at least 5 translations.
	var translation_count: int = catalog.get_translation_count()
	if translation_count < 5:
		_fail("translation count %d < 5" % translation_count)
		return

	# Known translation returns the catalog text.
	var known_translated: String = catalog.translate("oxygen.label", "en")
	if known_translated.is_empty():
		_fail("oxygen.label should translate to a non-empty string in en")
		return
	if known_translated != "Oxygen:":
		_fail("oxygen.label translation mismatch; expected 'Oxygen:' got '%s'" % known_translated)
		return

	# Unknown id returns empty.
	if not catalog.translate("definitely.not.in.catalog", "en").is_empty():
		_fail("unknown id should return empty string")
		return

	# translate_fallback returns the supplied text for unknown ids.
	var fallback_text: String = catalog.translate_fallback("definitely.not.in.catalog", "DEFAULT TEXT", "en")
	if fallback_text != "DEFAULT TEXT":
		_fail("translate_fallback should return supplied text for unknown id; got '%s'" % fallback_text)
		return

	# Unknown language falls back to default language's text.
	var fallback_lang_text: String = catalog.translate("oxygen.label", "zz")
	if fallback_lang_text != "Oxygen:":
		_fail("unknown language should fall back to default; got '%s'" % fallback_lang_text)
		return

	# Empty string id returns empty.
	if not catalog.translate("", "en").is_empty():
		_fail("empty string id should return empty")
		return
	if catalog.translate_fallback("", "DEFAULT", "en") != "DEFAULT":
		_fail("empty string id with fallback should return fallback")
		return

	# Summary.
	var summary: Dictionary = catalog.get_summary()
	if int(summary.get("translation_count", -1)) != translation_count:
		_fail("summary translation_count drift: %d vs %d" % [int(summary.get("translation_count", -1)), translation_count])
		return
	if str(summary.get("default_language", "")) != "en":
		_fail("summary default_language should be 'en'; got '%s'" % str(summary.get("default_language", "")))
		return

	print("LOCALIZATION CATALOG PASS languages=%d translations=%d fallback=true unknown_returns_default=true" % [
		known_languages.size(),
		translation_count,
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("LOCALIZATION CATALOG FAIL reason=%s" % reason)
	quit(1)
