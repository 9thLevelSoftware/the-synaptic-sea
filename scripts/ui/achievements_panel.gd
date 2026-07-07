extends Control
class_name AchievementsPanel

## REQ-RL-003 / REQ-RL-004 achievements panel.
##
## Pure UI control that renders the achievement catalog grouped by
## unlock status (unlocked / locked). Reads `AchievementState.get_summary()`
## and the catalog JSON. The smoke proves the script is loadable as a
## Godot script and the rendering path produces the expected counts.

const AchievementStateScript := preload("res://scripts/systems/achievement_state.gd")
const CATALOG_PATH: String = "res://data/release/achievement_catalog.json"

var _state = null
var _catalog: Dictionary = {}
var _list_label: RichTextLabel = null

func _ready() -> void:
	_list_label = RichTextLabel.new()
	_list_label.name = "AchievementsList"
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	add_child(_list_label)

func set_state(state) -> void:
	_state = state

func get_state():
	return _state

func load_catalog(json_text: String = "") -> int:
	if json_text.is_empty():
		if not FileAccess.file_exists(CATALOG_PATH):
			return 0
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if file == null:
			return 0
		json_text = file.get_as_text()
		file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return 0
	_catalog = parsed
	var list_variant: Variant = (parsed as Dictionary).get("achievements", [])
	if typeof(list_variant) != TYPE_ARRAY:
		return 0
	return (list_variant as Array).size()

func get_unlocked_count() -> int:
	if _state == null:
		return 0
	return _state.get_unlock_count()

func get_total_count() -> int:
	if not _catalog.has("achievements"):
		return 0
	var list_variant: Variant = _catalog["achievements"]
	if typeof(list_variant) != TYPE_ARRAY:
		return 0
	return (list_variant as Array).size()

func render() -> void:
	if _list_label == null:
		return
	if not _catalog.has("achievements"):
		_list_label.text = "(catalog empty)"
		return
	var bb: String = ""
	var list: Array = _catalog["achievements"]
	var unlocked_set: Dictionary = {}
	if _state != null:
		for id_str in _state.get_unlocked():
			unlocked_set[String(id_str)] = true
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var id_str: String = str(dict.get("id", ""))
		var display_name: String = str(dict.get("display_name", ""))
		var description: String = str(dict.get("description", ""))
		var marker: String = "[X]" if unlocked_set.has(id_str) else "[ ]"
		bb += "%s [b]%s[/b]\n  %s\n\n" % [marker, display_name, description]
	_list_label.text = bb
