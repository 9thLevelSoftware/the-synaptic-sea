extends RefCounted
class_name UnlockRegistry

## REQ-PM-009 / ADR-0033 cross-run unlock registry.
##
## Wraps a codex/hub-scene/class-unlock catalog and persists to
## `user://unlock_registry.json` independently of `MetaProgressionState`.
## The split keeps per-currency meta state separate from codex/scene
## unlocks, which can grow larger and have different cadence (unlocks
## fire on first-discovery, currency fires on run-end).
##
## Pure: no scene tree, no RNG. The codex panel reads from this model.

const SCHEMA_VERSION: String = "unlock-registry-1"
const SAVE_PATH: String = "user://unlock_registry.json"

var _catalog_by_id: Dictionary = {}   # unlock_id -> {category, display_name, ...}
var _unlocked: Dictionary = {}        # unlock_id -> true (idempotent)

## Configures from a parsed Dictionary (the JSON content). Returns
## false on parse error. The catalog is the source of truth — unlock
## calls for unknown ids are rejected.
func configure(catalog: Dictionary = {}) -> bool:
	_catalog_by_id.clear()
	_unlocked.clear()
	if catalog == null:
		catalog = {}
	var variant: Variant = catalog.get("unlocks", [])
	if typeof(variant) != TYPE_ARRAY:
		return false
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid: String = str((entry as Dictionary).get("unlock_id", ""))
		if uid.is_empty():
			continue
		_catalog_by_id[uid] = (entry as Dictionary).duplicate(true)
	return true

## Reloads the in-memory catalog at runtime (after a config reload).
## Preserves the existing unlock set so live unlocks don't drop.
func set_catalog(catalog: Dictionary) -> void:
	_catalog_by_id.clear()
	if catalog == null:
		return
	var variant: Variant = catalog.get("unlocks", [])
	if typeof(variant) != TYPE_ARRAY:
		return
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid: String = str((entry as Dictionary).get("unlock_id", ""))
		if uid.is_empty():
			continue
		_catalog_by_id[uid] = (entry as Dictionary).duplicate(true)

func get_catalog_size() -> int:
	return _catalog_by_id.size()

func is_known(unlock_id: String) -> bool:
	return _catalog_by_id.has(unlock_id)

func get_category(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("category", ""))

func get_display_name(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("display_name", unlock_id))

func get_trigger_event(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("trigger_event", ""))

func get_trigger_target(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("trigger_target", ""))

func get_class_id(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("class_id", ""))

## True when a catalog row's (event,target) matches a fired (event,target).
## Row-side "*" AND "any" are wildcards matching any fired target (unlock_tables
## encodes wildcard rows as "any"). PR #55 Codex P1.
func _trigger_matches(row_event: String, row_target: String, fired_event: String, fired_target: String) -> bool:
	if row_event != fired_event:
		return false
	if row_target == "*" or row_target == "any":
		return true
	return row_target == fired_target

## Returns the class_ids of ALL class-category catalog rows whose trigger matches
## (event,target), unlocking each in the registry (idempotent). The run-end bridge
## uses this so a class unlock is not starved when a codex row shares the trigger
## and sorts first (unlock_for_trigger only returns the first match).
func class_ids_for_trigger(trigger_event: String, trigger_target: String) -> Array:
	var out: Array = []
	if trigger_event.is_empty():
		return out
	for uid in _catalog_by_id:
		var entry: Dictionary = _catalog_by_id[uid]
		if str(entry.get("category", "")) != "class":
			continue
		if _trigger_matches(str(entry.get("trigger_event", "")), str(entry.get("trigger_target", "")), trigger_event, trigger_target):
			unlock(uid)
			var cls: String = str(entry.get("class_id", ""))
			if not cls.is_empty():
				out.append(cls)
	return out

## Returns true on first-time unlock; false when the id is unknown,
## already unlocked, or empty. The `trigger_event` / `trigger_target`
## are stored on the catalog entry — callers pass the event id and
## target id, not the unlock id directly.
func unlock(unlock_id: String) -> bool:
	if unlock_id.is_empty():
		return false
	if not is_known(unlock_id):
		return false
	if _unlocked.has(unlock_id):
		return false
	_unlocked[unlock_id] = true
	return true

## Trigger-based unlock. Resolves the (event, target) pair against the
## catalog (using exact match and "any" wildcard, like
## AchievementState.unlock_for_trigger) and unlocks the first matching
## id. Returns the unlocked id, or "" when nothing matches.
func unlock_for_trigger(trigger_event: String, trigger_target: String) -> String:
	if trigger_event.is_empty():
		return ""
	var resolved: String = ""
	for uid in _catalog_by_id:
		var entry: Dictionary = _catalog_by_id[uid]
		var evt: String = str(entry.get("trigger_event", ""))
		var tgt: String = str(entry.get("trigger_target", ""))
		if _trigger_matches(evt, tgt, trigger_event, trigger_target):
			if unlock(uid):
				resolved = uid
				break
	return resolved

func is_unlocked(unlock_id: String) -> bool:
	return _unlocked.has(unlock_id) and bool(_unlocked[unlock_id])

func get_unlocked_ids() -> Array:
	var keys: Array = _unlocked.keys()
	keys.sort()
	return keys

func get_unlock_count() -> int:
	return _unlocked.size()

func get_entries_for_category(category: String) -> Array:
	var out: Array = []
	for uid in _catalog_by_id:
		if str(_catalog_by_id[uid].get("category", "")) == category:
			out.append({
				"unlock_id": uid,
				"display_name": str(_catalog_by_id[uid].get("display_name", uid)),
				"description": str(_catalog_by_id[uid].get("description", "")),
				"unlocked": is_unlocked(uid),
			})
	out.sort_custom(func(a, b): return String(a.get("unlock_id", "")) < String(b.get("unlock_id", "")))
	return out

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Unlock Registry: %d / %d" % [_unlocked.size(), _catalog_by_id.size()])
	return lines

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"unlocked": _unlocked.duplicate(),
		"saved_at": Time.get_datetime_string_from_system(true),
	}

func apply_summary(summary: Variant) -> bool:
	if summary == null or typeof(summary) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = summary as Dictionary
	var schema: String = str(dict.get("schema", ""))
	if schema != SCHEMA_VERSION:
		return false
	_unlocked.clear()
	var variant: Variant = dict.get("unlocked", {})
	if typeof(variant) != TYPE_DICTIONARY:
		return false
	for k in (variant as Dictionary):
		if bool((variant as Dictionary)[k]):
			var uid: String = str(k)
			if is_known(uid):
				_unlocked[uid] = true
	return true

func save_to_disk(save_path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true

func load_from_disk(source_path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(source_path):
		return false
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return false
	return apply_summary(parsed as Dictionary)