extends Control
class_name LanguageSelector

## REQ-RL-005 language selector.
##
## Pure UI control that owns a `LocalizationCatalog` and emits
## `language_changed(language_id)` when the user picks a language. The
## HUD label shows the active language code. Listens to the catalog's
## known_languages list and populates an OptionButton at _ready.
##
## Wired as a child of the main HUD; the HUD re-renders labels via the
## `language_changed` signal.

const LocalizationCatalogScript := preload("res://scripts/systems/localization_catalog.gd")

var _catalog: LocalizationCatalog = null
var _option_button: OptionButton = null
var _active_language: String = "en"

signal language_changed(language_id: String)

func _ready() -> void:
	_option_button = OptionButton.new()
	_option_button.name = "LanguageSelector"
	add_child(_option_button)
	_option_button.item_selected.connect(_on_item_selected)

func set_catalog(catalog: LocalizationCatalog) -> void:
	_catalog = catalog
	if _option_button != null:
		_populate_options()

func get_catalog() -> LocalizationCatalog:
	return _catalog

func get_active_language() -> String:
	return _active_language

func set_active_language(language_id: String) -> void:
	_active_language = language_id
	if _option_button != null:
		_select_option_for(_active_language)

func translate(string_id: String) -> String:
	if _catalog == null:
		return ""
	return _catalog.translate(string_id, _active_language)

func translate_fallback(string_id: String, default_text: String) -> String:
	if _catalog == null:
		return default_text
	return _catalog.translate_fallback(string_id, default_text, _active_language)

func get_known_languages() -> Array:
	if _catalog == null:
		return []
	return _catalog.get_known_languages()

func _populate_options() -> void:
	if _option_button == null or _catalog == null:
		return
	_option_button.clear()
	var languages: Array = _catalog.get_known_languages()
	for idx in range(languages.size()):
		var lang_id: String = str(languages[idx])
		_option_button.add_item(lang_id, idx)
	_select_option_for(_active_language)

func _select_option_for(language_id: String) -> void:
	if _option_button == null:
		return
	for idx in range(_option_button.item_count):
		if str(_option_button.get_item_text(idx)) == language_id:
			_option_button.select(idx)
			return

func _on_item_selected(idx: int) -> void:
	if _option_button == null:
		return
	var selected: String = _option_button.get_item_text(idx)
	if selected == _active_language:
		return
	_active_language = selected
	language_changed.emit(_active_language)