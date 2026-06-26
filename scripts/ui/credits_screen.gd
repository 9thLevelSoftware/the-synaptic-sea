extends Control
class_name CreditsScreen

## REQ-RL-009 credits screen.
##
## Pure UI control that loads `data/release/credits.json` and renders
## the catalog as a scrolling list. Emits `credits_dismissed` when the
## player closes the panel.
##
## The data is loaded by the caller (or by `_ready` if the catalog
## file is present); the smoke proves the script is loadable as a
## Godot script and the catalog parsing path returns the expected
## entries.

signal credits_dismissed

const CREDITS_PATH: String = "res://data/release/credits.json"

var _entries: Array = []
var _title_label: Label = null
var _list_label: RichTextLabel = null

func _ready() -> void:
	_title_label = Label.new()
	_title_label.name = "CreditsTitle"
	_title_label.text = "Credits & Attribution"
	add_child(_title_label)
	_list_label = RichTextLabel.new()
	_list_label.name = "CreditsList"
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	add_child(_list_label)

func load_catalog(json_text: String = "") -> int:
	if json_text.is_empty():
		if not FileAccess.file_exists(CREDITS_PATH):
			return 0
		var file := FileAccess.open(CREDITS_PATH, FileAccess.READ)
		if file == null:
			return 0
		json_text = file.get_as_text()
		file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return 0
	_entries.clear()
	var list_variant: Variant = (parsed as Dictionary).get("credits", [])
	if typeof(list_variant) != TYPE_ARRAY:
		return 0
	for entry in list_variant:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var role: String = str(dict.get("role", ""))
		var name_str: String = str(dict.get("name", ""))
		if role.is_empty() or name_str.is_empty():
			continue
		_entries.append({
			"role": role,
			"name": name_str,
			"license": str(dict.get("license", "")),
			"note": str(dict.get("note", "")),
		})
	_render()
	return _entries.size()

func get_entries() -> Array:
	return _entries.duplicate(true)

func get_entry_count() -> int:
	return _entries.size()

func dismiss() -> void:
	credits_dismissed.emit()

func _render() -> void:
	if _list_label == null:
		return
	var bb: String = ""
	for entry in _entries:
		var dict: Dictionary = entry
		bb += "[b]%s[/b] — %s\n" % [str(dict.get("role", "")), str(dict.get("name", ""))]
		var license_str: String = str(dict.get("license", ""))
		if not license_str.is_empty():
			bb += "  [i]%s[/i]\n" % license_str
		var note: String = str(dict.get("note", ""))
		if not note.is_empty():
			bb += "  %s\n" % note
	_list_label.text = bb