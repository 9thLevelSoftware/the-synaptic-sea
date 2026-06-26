extends Control
class_name ClassPanel

## REQ-PM-001 / REQ-PM-010 / ADR-0033 class roster panel UI.
##
## Renders every class in `data/player/classes.json` with display name,
## description, and starting skills. Highlights the currently selected
## class. Read-only by design — class selection happens at run-start in
## the run setup scene, not in this panel.

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const CATALOG_PATH: String = "res://data/player/classes.json"

var _classes: Dictionary = {}
var _selected_class_id: String = ""
var _list_label: RichTextLabel = null

func _ready() -> void:
	_list_label = RichTextLabel.new()
	_list_label.name = "ClassList"
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	add_child(_list_label)

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
	var variant: Variant = (parsed as Dictionary).get("classes", [])
	if typeof(variant) != TYPE_ARRAY:
		return 0
	_classes.clear()
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cid: String = str((entry as Dictionary).get("class_id", ""))
		if cid.is_empty():
			continue
		_classes[cid] = (entry as Dictionary).duplicate(true)
	return _classes.size()

func set_selected_class(class_id: String) -> void:
	_selected_class_id = class_id

func get_class_count() -> int:
	return _classes.size()

func get_class_ids() -> Array:
	var keys: Array = _classes.keys()
	keys.sort()
	return keys

## Returns a per-class entry dict for the UI: id, display name, description,
## starting skills, and a "selected" flag.
func get_class_entries() -> Array:
	var out: Array = []
	for cid in _classes:
		var entry: Dictionary = _classes[cid]
		var starting: Dictionary = (entry.get("starting_skills", {}) as Dictionary).duplicate()
		out.append({
			"class_id": cid,
			"display_name": str(entry.get("name", cid)),
			"description": str(entry.get("description", "")),
			"starting_skills": starting,
			"selected": cid == _selected_class_id,
		})
	out.sort_custom(func(a, b): return String(a.get("class_id", "")) < String(b.get("class_id", "")))
	return out

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Class Roster: %d  Selected: %s" % [_classes.size(), _selected_class_id if not _selected_class_id.is_empty() else "(none)"])
	for entry in get_class_entries():
		var cid: String = str(entry.get("class_id", ""))
		var display: String = str(entry.get("display_name", cid))
		var selected: bool = bool(entry.get("selected", false))
		var marker: String = ">>" if selected else "  "
		var starting: Dictionary = entry.get("starting_skills", {}) as Dictionary
		var starting_str: String = ""
		if not starting.is_empty():
			var parts: Array = []
			for sid in starting:
				parts.append("%s=%d" % [sid, int(starting[sid])])
			starting_str = "  [%s]" % ", ".join(parts)
		lines.append("%s %s%s" % [marker, display, starting_str])
	return lines

func render() -> void:
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	var bb: String = ""
	for line in lines:
		bb += String(line) + "\n"
	_list_label.text = bb

## Static factory used by the smoke: loads the catalog from disk and
## pre-selects the given class (defaults to "engineer").
static func build_default(selected_class_id: String = "engineer"):
	var panel = load("res://scripts/ui/class_panel.gd").new()
	panel.load_catalog()
	panel.set_selected_class(selected_class_id)
	return panel