extends RefCounted
class_name CharacterVisualCatalog

## Pure data loader for `data/characters/character_visual_catalog.json`
## (ADR-0070). Maps a character id (e.g. `player_survivor`) to the runtime GLB
## scene, the equipment-slot -> node-prefix visibility table, socket names and
## the logical -> clip animation names. It never touches the scene tree; the
## `CharacterVisual` node consumes an entry and applies scene consequences.
##
## Missing or malformed entries are reported through `get_errors()` and
## resolve to an empty Dictionary so callers keep their existing fallback
## (the capsule marker) instead of borrowing another visual (ADR-0052 §6).

const DEFAULT_CATALOG_PATH: String = "res://data/characters/character_visual_catalog.json"
const CATALOG_VERSION: String = "character-visual-1"
const REQUIRED_ENTRY_FIELDS: Array[String] = [
	"kit_id", "scene_path", "height_m", "forward_axis", "equipment_visuals", "animations",
]
const REQUIRED_ANIMATION_KEYS: Array[String] = [
	"idle", "walk", "crouch_idle", "crouch_walk", "work", "melee", "aim", "downed",
]

var _entries: Dictionary = {}
var _errors: Array[String] = []


## Loads and validates the catalog. Entries are committed only when the whole
## document is valid, so the return value and `get_entry()` always agree.
func load_from_path(path: String = DEFAULT_CATALOG_PATH) -> bool:
	_entries = {}
	_errors = []
	if path.is_empty() or not FileAccess.file_exists(path):
		_errors.append("catalog missing: %s" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("catalog unreadable: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_errors.append("catalog document must be an object")
		return false
	var root: Dictionary = parsed as Dictionary
	if str(root.get("version", "")) != CATALOG_VERSION:
		_errors.append("catalog version must be %s" % CATALOG_VERSION)
		return false
	var characters: Variant = root.get("characters", null)
	if not (characters is Dictionary):
		_errors.append("catalog characters must be an object")
		return false
	var validated: Dictionary = {}
	for character_id in (characters as Dictionary).keys():
		var entry: Variant = (characters as Dictionary)[character_id]
		if not (entry is Dictionary):
			_errors.append("entry %s must be an object" % character_id)
			continue
		var entry_errors: Array[String] = validate_entry(entry as Dictionary)
		if not entry_errors.is_empty():
			for e in entry_errors:
				_errors.append("entry %s: %s" % [character_id, e])
			continue
		validated[str(character_id)] = (entry as Dictionary).duplicate(true)
	if not _errors.is_empty():
		return false
	_entries = validated
	return true


static func validate_entry(entry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field in REQUIRED_ENTRY_FIELDS:
		if not entry.has(field):
			errors.append("missing field %s" % field)
	if errors.is_empty():
		if not str(entry.get("scene_path", "")).begins_with("res://"):
			errors.append("scene_path must be a res:// path")
		if str(entry.get("forward_axis", "")) != "+Z":
			errors.append("forward_axis must be +Z")
		if float(entry.get("height_m", 0.0)) <= 0.0:
			errors.append("height_m must be positive")
		if not (entry.get("equipment_visuals") is Dictionary):
			errors.append("equipment_visuals must be an object")
		var animations: Variant = entry.get("animations")
		if not (animations is Dictionary):
			errors.append("animations must be an object")
		else:
			for key in REQUIRED_ANIMATION_KEYS:
				if str((animations as Dictionary).get(key, "")).is_empty():
					errors.append("animations.%s missing" % key)
	return errors


## Returns a deep copy of the entry, or an empty Dictionary when unknown.
func get_entry(character_id: String) -> Dictionary:
	if not _entries.has(character_id):
		return {}
	return (_entries[character_id] as Dictionary).duplicate(true)


func get_errors() -> Array[String]:
	return _errors.duplicate()
