extends RefCounted
class_name TutorialState
## Pure tutorial trigger state (REQ-UI-005 / ADR-0033).
##
## Owns:
##   - `_catalog` — loaded from `data/ui/tutorial_triggers.json`
##   - `_fired` — set of `event|target` pairs already fired
##   - `_dismissed` — set of tutorial ids dismissed in this run
##   - `_codex_unlocks` — set of codex entry ids unlocked in this run
##
## `trigger(event, target)`:
##   - returns the tutorial id on first call (and emits `triggered`)
##   - returns "" on re-fire (no signal, idempotent)
##   - returns "" on unknown `(event, target)` (and emits no signal)
##
## `dismiss(tutorial_id)`:
##   - marks the tutorial dismissed (no further trigger emissions)
##   - unlocks the matching codex entry (if a codex_entry_id is set)
##   - emits `codex_unlocked` when a codex entry is unlocked
##
## `reset()` clears fired / dismissed / unlocks for a new run.
##
## Pure-model-first: no scene-tree access. The TutorialOverlayPanel and
## CodexPanel subscribe via signals.

signal triggered(tutorial_id: String, title: String, body: String)
signal dismissed(tutorial_id: String)
signal codex_unlocked(codex_entry_id: String)

const TutorialStateSchemaScript := preload("res://scripts/schemas/tutorial_state_schema.gd")

const SCHEMA_VERSION: String = "tutorial-state-1"
const SAVE_KEY: String = "tutorial_state"

var _catalog: Dictionary = {}
var _tutorial_ids: Array = []
var _trigger_to_id: Dictionary = {}        # event|target -> tutorial_id
var _id_to_entry: Dictionary = {}          # tutorial_id -> entry_dict
var _fired: Dictionary = {}                # event|target -> tutorial_id (fired this run)
var _dismissed: Dictionary = {}            # tutorial_id -> true
var _codex_unlocks: Dictionary = {}        # codex_entry_id -> tutorial_id that unlocked it
var _latest_tutorial_id: String = ""       # id of the most recently triggered tutorial

func configure(catalog: Dictionary) -> bool:
	if not TutorialStateSchemaScript.validate(catalog):
		return false
	_catalog = (catalog as Dictionary).duplicate(true)
	_tutorial_ids.clear()
	_trigger_to_id.clear()
	_id_to_entry.clear()
	for tutorial in ((_catalog.get("tutorials", []) as Array)):
		var t_dict: Dictionary = tutorial
		var id_str: String = str(t_dict.get("id", ""))
		_tutorial_ids.append(id_str)
		_id_to_entry[id_str] = t_dict
		var event_str: String = str(t_dict.get("trigger_event", ""))
		var target_str: String = str(t_dict.get("trigger_target", ""))
		var key: String = event_str + "|" + target_str
		_trigger_to_id[key] = id_str
	_fired.clear()
	_dismissed.clear()
	_codex_unlocks.clear()
	_latest_tutorial_id = ""
	return true

func is_known(tutorial_id: String) -> bool:
	return tutorial_id in _tutorial_ids

func get_tutorial_ids() -> Array:
	return _tutorial_ids.duplicate()

func get_catalog_size() -> int:
	return _tutorial_ids.size()

func get_entry(tutorial_id: String) -> Dictionary:
	if not is_known(tutorial_id):
		return {}
	return (_id_to_entry[tutorial_id] as Dictionary).duplicate(true)

## Returns the title / body for a tutorial id, or "" / "" when unknown.
func get_title(tutorial_id: String) -> String:
	if not is_known(tutorial_id):
		return ""
	return String(_id_to_entry[tutorial_id].get("title", ""))

func get_body(tutorial_id: String) -> String:
	if not is_known(tutorial_id):
		return ""
	return String(_id_to_entry[tutorial_id].get("body", ""))

## Trigger a tutorial. Returns the tutorial id on first call; "" on
## re-fire or unknown trigger. Emits `triggered` exactly once per
## `(event, target)` pair per run.
func trigger(event: String, target: String) -> String:
	if event.is_empty() or target.is_empty():
		return ""
	var key: String = event + "|" + target
	if not _trigger_to_id.has(key):
		return ""
	var tutorial_id: String = str(_trigger_to_id[key])
	if _fired.has(key):
		return ""
	_fired[key] = tutorial_id
	_latest_tutorial_id = tutorial_id
	emit_signal("triggered", tutorial_id, get_title(tutorial_id), get_body(tutorial_id))
	return tutorial_id

## Dismiss a tutorial. Marks it dismissed and unlocks the matching
## codex entry (if one is configured).
func dismiss(tutorial_id: String) -> bool:
	if not is_known(tutorial_id):
		push_warning("TutorialState: dismiss unknown tutorial '%s'" % tutorial_id)
		return false
	if _dismissed.has(tutorial_id):
		return true
	_dismissed[tutorial_id] = true
	emit_signal("dismissed", tutorial_id)
	var entry: Dictionary = _id_to_entry[tutorial_id]
	var codex_entry_id: String = str(entry.get("codex_entry_id", ""))
	if not codex_entry_id.is_empty() and not _codex_unlocks.has(codex_entry_id):
		_codex_unlocks[codex_entry_id] = tutorial_id
		emit_signal("codex_unlocked", codex_entry_id)
	return true

## Mark a codex entry unlocked without going through `dismiss`. Used
## by the codex panel when the player reads an entry manually.
func unlock_codex(codex_entry_id: String) -> bool:
	if codex_entry_id.is_empty():
		return false
	if _codex_unlocks.has(codex_entry_id):
		return true
	_codex_unlocks[codex_entry_id] = ""
	emit_signal("codex_unlocked", codex_entry_id)
	return true

## Returns the latest fired tutorial id (or "" if none fired in this
## run). The TutorialOverlayPanel reads this to render the banner.
func get_latest_tutorial_id() -> String:
	return _latest_tutorial_id

## Returns true when a tutorial has fired in this run and has not been
## dismissed.
func has_pending_banner() -> bool:
	if _latest_tutorial_id.is_empty():
		return false
	return not _dismissed.has(_latest_tutorial_id)

func is_dismissed(tutorial_id: String) -> bool:
	return _dismissed.has(tutorial_id)

## Returns the list of codex entry ids unlocked in this run.
func get_unlocked_codex_ids() -> Array:
	var unlocked: Array = []
	for key in _codex_unlocks.keys():
		unlocked.append(String(key))
	unlocked.sort()
	return unlocked

## Returns true when the codex entry id has been unlocked.
func is_codex_unlocked(codex_entry_id: String) -> bool:
	return _codex_unlocks.has(codex_entry_id)

## Number of fired / dismissed / unlocked counters (for status dumps).
func get_fired_count() -> int:
	return _fired.size()

func get_dismissed_count() -> int:
	return _dismissed.size()

func get_codex_unlock_count() -> int:
	return _codex_unlocks.size()

## Reset fired / dismissed / unlocks for a new run. The catalog stays
## loaded so a fresh run starts at the same baseline.
func reset() -> void:
	_fired.clear()
	_dismissed.clear()
	_codex_unlocks.clear()
	_latest_tutorial_id = ""

## Round-trip seam.
func get_summary() -> Dictionary:
	var fired_keys: Array = []
	for key in _fired.keys():
		fired_keys.append(String(key))
	fired_keys.sort()
	var dismissed_ids: Array = []
	for id_str in _dismissed.keys():
		dismissed_ids.append(String(id_str))
	dismissed_ids.sort()
	var codex_ids: Array = get_unlocked_codex_ids()
	return {
		"schema": SCHEMA_VERSION,
		"catalog_size": _tutorial_ids.size(),
		"fired_count": _fired.size(),
		"dismissed_count": _dismissed.size(),
		"codex_unlock_count": _codex_unlocks.size(),
		"fired_keys": fired_keys,
		"dismissed_ids": dismissed_ids,
		"codex_unlocked_ids": codex_ids,
		"latest_tutorial_id": _latest_tutorial_id,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	if str(summary.get("schema", "")) != SCHEMA_VERSION:
		return false
	_fired.clear()
	_dismissed.clear()
	_codex_unlocks.clear()
	var fired_variant: Variant = summary.get("fired_keys", [])
	if typeof(fired_variant) == TYPE_ARRAY:
		for key in (fired_variant as Array):
			var key_str: String = str(key)
			if _trigger_to_id.has(key_str):
				_fired[key_str] = str(_trigger_to_id[key_str])
	var dismissed_variant: Variant = summary.get("dismissed_ids", [])
	if typeof(dismissed_variant) == TYPE_ARRAY:
		for id_str in (dismissed_variant as Array):
			var id_str_s: String = str(id_str)
			if is_known(id_str_s):
				_dismissed[id_str_s] = true
	var codex_variant: Variant = summary.get("codex_unlocked_ids", [])
	if typeof(codex_variant) == TYPE_ARRAY:
		for entry_id in (codex_variant as Array):
			var entry_id_s: String = str(entry_id)
			if not entry_id_s.is_empty():
				_codex_unlocks[entry_id_s] = ""
	_latest_tutorial_id = str(summary.get("latest_tutorial_id", ""))
	if not _latest_tutorial_id.is_empty() and not is_known(_latest_tutorial_id):
		_latest_tutorial_id = ""
	return true

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("TutorialState: catalog=%d fired=%d dismissed=%d codex_unlocks=%d latest=%s" % [
		_tutorial_ids.size(),
		_fired.size(),
		_dismissed.size(),
		_codex_unlocks.size(),
		_latest_tutorial_id if not _latest_tutorial_id.is_empty() else "<none>",
	])
	return lines