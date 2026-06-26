extends RefCounted
class_name AchievementState

## REQ-RL-003 / REQ-RL-004 achievement state.
##
## Pure data service. Owns the per-run unlock set and the catalog.
##
## `unlock(id)` returns:
##   - `true`  on a successful first-time unlock
##   - `false` if the id is unknown (catalog is the only source of truth)
##   - `false` on a duplicate unlock (idempotent; no double-unlock)
##
## Per-run-only: a new run wipes the unlock set. Cross-run state is a
## deferred Steamworks concern (ADR-0029 / ADR-0030); this service is the
## per-run source of truth that the future Steamworks layer reconciles
## against `user://achievements.json` (ADR-0007 boundary preserved).

const SCHEMA_VERSION: String = "release-achievements-1"
const SAVE_PATH: String = "user://achievements.json"

var _catalog: Dictionary = {}
var _catalog_ids: Array = []
var _trigger_to_id: Dictionary = {}
var _unlocked: Dictionary = {}  # id -> {unlocked: true, unlocked_at: "iso"}
var _run_id: String = ""

func configure(catalog: Dictionary) -> void:
	_catalog = catalog if catalog != null else {}
	_catalog_ids.clear()
	_trigger_to_id.clear()
	var list_variant: Variant = _catalog.get("achievements", [])
	if typeof(list_variant) == TYPE_ARRAY:
		for entry in (list_variant as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var dict: Dictionary = entry
			var id_str: String = str(dict.get("id", ""))
			if id_str.is_empty():
				continue
			_catalog_ids.append(id_str)
			var trigger_event: String = str(dict.get("trigger_event", ""))
			var trigger_target: String = str(dict.get("trigger_target", ""))
			if not trigger_event.is_empty():
				var key: String = trigger_event + "|" + trigger_target
				_trigger_to_id[key] = id_str
				# Also register a wildcard target alias for "any".
				if trigger_target == "any":
					var any_key: String = trigger_event + "|*"
					_trigger_to_id[any_key] = id_str

func is_known(id: String) -> bool:
	return id in _catalog_ids

func get_catalog_ids() -> Array:
	return _catalog_ids.duplicate()

func get_catalog_size() -> int:
	return _catalog_ids.size()

func unlock(id: String) -> bool:
	if id.is_empty():
		return false
	if not id in _catalog_ids:
		return false
	if _unlocked.has(id):
		return false
	_unlocked[id] = {
		"unlocked": true,
		"unlocked_at": Time.get_datetime_string_from_system(true),
	}
	return true

# Resolves a (trigger_event, trigger_target) pair to an achievement id
# and unlocks it. Returns the unlocked id, or "" when no catalog entry
# matches. Unknown triggers are silent no-ops (the coordinator only
# emits events that the catalog could match).
func unlock_for_trigger(trigger_event: String, trigger_target: String) -> String:
	if trigger_event.is_empty():
		return ""
	var exact_key: String = trigger_event + "|" + trigger_target
	if _trigger_to_id.has(exact_key):
		var id_for_exact: String = str(_trigger_to_id[exact_key])
		if unlock(id_for_exact):
			return id_for_exact
		return ""
	var wildcard_key: String = trigger_event + "|*"
	if _trigger_to_id.has(wildcard_key):
		var id_for_wild: String = str(_trigger_to_id[wildcard_key])
		if unlock(id_for_wild):
			return id_for_wild
	return ""

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id) and bool(_unlocked[id].get("unlocked", false))

func get_unlocked() -> Array:
	var sorted_ids: Array = _unlocked.keys()
	sorted_ids.sort()
	return sorted_ids

func get_unlock_count() -> int:
	return _unlocked.size()

func start_new_run(run_id: String = "") -> void:
	_run_id = run_id
	_unlocked.clear()

func get_run_id() -> String:
	return _run_id

# Round-trip for the per-run save seam. Saving is current-run only.
func to_dict() -> Dictionary:
	var unlocked_dict: Dictionary = {}
	for id_str in _unlocked.keys():
		unlocked_dict[String(id_str)] = _unlocked[id_str]
	return {
		"schema": SCHEMA_VERSION,
		"run_id": _run_id,
		"unlocked": unlocked_dict,
		"saved_at": Time.get_datetime_string_from_system(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null:
		return false
	var schema: String = str(summary.get("schema", ""))
	if schema != SCHEMA_VERSION:
		return false
	_run_id = str(summary.get("run_id", ""))
	var unlocked_variant: Variant = summary.get("unlocked", {})
	if typeof(unlocked_variant) != TYPE_DICTIONARY:
		return false
	_unlocked.clear()
	for key in (unlocked_variant as Dictionary).keys():
		var id_str: String = str(key)
		if id_str.is_empty():
			continue
		if not id_str in _catalog_ids:
			continue
		var entry: Dictionary = {}
		var raw_entry: Variant = unlocked_variant[key]
		if typeof(raw_entry) == TYPE_DICTIONARY:
			entry = raw_entry
		_unlocked[id_str] = {
			"unlocked": bool(entry.get("unlocked", true)),
			"unlocked_at": str(entry.get("unlocked_at", "")),
		}
	return true

func get_summary() -> Dictionary:
	var sorted_ids: Array = _unlocked.keys()
	sorted_ids.sort()
	var unlocked_dict: Dictionary = {}
	for id_str in sorted_ids:
		unlocked_dict[String(id_str)] = {
			"unlocked": bool(_unlocked[id_str].get("unlocked", false)),
			"unlocked_at": str(_unlocked[id_str].get("unlocked_at", "")),
		}
	return {
		"schema": SCHEMA_VERSION,
		"run_id": _run_id,
		"catalog_size": _catalog_ids.size(),
		"unlock_count": _unlocked.size(),
		"unlocked": unlocked_dict,
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Achievements: %d / %d" % [_unlocked.size(), _catalog_ids.size()])
	for id_str in get_unlocked():
		lines.append("  - %s" % id_str)
	return lines

func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true

func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return false
	return apply_summary(parsed as Dictionary)