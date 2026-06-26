extends RefCounted
class_name MetaProgressionState

## REQ-PM-006 / REQ-PM-008 / ADR-0033 meta-progression model.
##
## Cross-run state. Persists to `user://meta_progression.json` independent
## of RunSnapshot (ADR-0007 boundary). Owns meta-currency, the hub upgrade
## unlock set, the class unlock set, the codex unlock set, and the run
## counter. The model is pure: no scene tree, no RNG, deterministic for a
## fixed input sequence.

const SCHEMA_VERSION: String = "meta-progression-1"
const SAVE_PATH: String = "user://meta_progression.json"

var meta_currency: int = 0
var unlocked_class_ids: Dictionary = {}            # class_id -> true
var unlocked_hub_upgrade_ids: Dictionary = {}       # upgrade_id -> true
var unlocked_codex_entry_ids: Dictionary = {}      # unlock_id -> true
var total_runs_completed: int = 0
var total_runs_deaths: int = 0
var highest_skill_level_seen: int = 0
var last_payout_currency: int = 0
var last_payout_reason: String = ""
var _catalog_known_ids: Dictionary = {}            # optional whitelist (set by configure)

func configure(catalog: Dictionary = {}) -> void:
	_catalog_known_ids.clear()
	if catalog == null:
		catalog = {}
	var variant: Variant = catalog.get("unlocks", [])
	if typeof(variant) == TYPE_ARRAY:
		for entry in (variant as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var uid: String = str((entry as Dictionary).get("unlock_id", ""))
			if uid.is_empty():
				continue
			_catalog_known_ids[uid] = true

func is_known(unlock_id: String) -> bool:
	if _catalog_known_ids.is_empty():
		return true
	return _catalog_known_ids.has(unlock_id)

func get_meta_currency() -> int:
	return meta_currency

func add_meta_currency(amount: int) -> bool:
	if amount <= 0:
		return false
	meta_currency += amount
	return true

func spend_meta_currency(amount: int) -> bool:
	if amount <= 0:
		return false
	if meta_currency < amount:
		return false
	meta_currency -= amount
	return true

func unlock_class(class_id: String) -> bool:
	if class_id.is_empty():
		return false
	if unlocked_class_ids.has(class_id):
		return false
	unlocked_class_ids[class_id] = true
	return true

func unlock_hub_upgrade(upgrade_id: String) -> bool:
	if upgrade_id.is_empty():
		return false
	if unlocked_hub_upgrade_ids.has(upgrade_id):
		return false
	unlocked_hub_upgrade_ids[upgrade_id] = true
	return true

func unlock_codex_entry(entry_id: String) -> bool:
	if entry_id.is_empty():
		return false
	if not is_known(entry_id):
		return false
	if unlocked_codex_entry_ids.has(entry_id):
		return false
	unlocked_codex_entry_ids[entry_id] = true
	return true

func is_class_unlocked(class_id: String) -> bool:
	return unlocked_class_ids.has(class_id) and bool(unlocked_class_ids[class_id])

func is_hub_upgrade_unlocked(upgrade_id: String) -> bool:
	return unlocked_hub_upgrade_ids.has(upgrade_id) and bool(unlocked_hub_upgrade_ids[upgrade_id])

func is_codex_entry_unlocked(entry_id: String) -> bool:
	return unlocked_codex_entry_ids.has(entry_id) and bool(unlocked_codex_entry_ids[entry_id])

func get_unlocked_class_ids() -> Array:
	var keys: Array = unlocked_class_ids.keys()
	keys.sort()
	return keys

func get_unlocked_hub_upgrade_ids() -> Array:
	var keys: Array = unlocked_hub_upgrade_ids.keys()
	keys.sort()
	return keys

func get_unlocked_codex_entry_ids() -> Array:
	var keys: Array = unlocked_codex_entry_ids.keys()
	keys.sort()
	return keys

func get_unlock_count() -> int:
	return unlocked_class_ids.size() + unlocked_hub_upgrade_ids.size() + unlocked_codex_entry_ids.size()

## Applies the meta payout for a finished run. Deterministic for a fixed
## `run_summary` shape. Records the payout in `last_payout_*` fields for
## HUD / smoke inspection.
##
## `run_summary` keys consumed:
##   - completed_objectives: int  →  +10 each
##   - skill_levels: Dictionary  →  +5 per skill >= 5, +15 per skill >= 8
##   - discoveries: int          →  +2 each (optional)
##   - reason: String            →  "death" / "extraction" / "abandon" (default "completion")
##
## Returns the total amount added.
func apply_meta_payout(run_summary: Dictionary) -> int:
	var payout: int = 0
	if run_summary == null:
		run_summary = {}
	var objectives: int = int(run_summary.get("completed_objectives", 0))
	payout += objectives * 10
	var skill_levels_variant: Variant = run_summary.get("skill_levels", {})
	if typeof(skill_levels_variant) == TYPE_DICTIONARY:
		for sid in (skill_levels_variant as Dictionary):
			var lvl: int = int((skill_levels_variant as Dictionary)[sid])
			if lvl >= 8:
				payout += 15
			elif lvl >= 5:
				payout += 5
			if lvl > highest_skill_level_seen:
				highest_skill_level_seen = lvl
	var discoveries: int = int(run_summary.get("discoveries", 0))
	payout += discoveries * 2
	var reason: String = str(run_summary.get("reason", "completion"))
	last_payout_currency = payout
	last_payout_reason = reason
	if reason == "death":
		total_runs_deaths += 1
	else:
		total_runs_completed += 1
	meta_currency += payout
	return payout

## Resets the run-scoped counters (skill-highest is preserved across runs).
## Called on a fresh run when the player picks a class; does NOT wipe
## meta_currency, unlocked_*, or total_runs_*. To wipe, use reset_all()
## (intended for the meta settings menu, not gameplay code).
func start_new_run() -> void:
	last_payout_currency = 0
	last_payout_reason = ""

func reset_all() -> void:
	meta_currency = 0
	unlocked_class_ids.clear()
	unlocked_hub_upgrade_ids.clear()
	unlocked_codex_entry_ids.clear()
	total_runs_completed = 0
	total_runs_deaths = 0
	highest_skill_level_seen = 0
	last_payout_currency = 0
	last_payout_reason = ""

## Serializes the meta state to a Dictionary (save/load agnostic).
func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"meta_currency": meta_currency,
		"unlocked_class_ids": unlocked_class_ids.duplicate(),
		"unlocked_hub_upgrade_ids": unlocked_hub_upgrade_ids.duplicate(),
		"unlocked_codex_entry_ids": unlocked_codex_entry_ids.duplicate(),
		"total_runs_completed": total_runs_completed,
		"total_runs_deaths": total_runs_deaths,
		"highest_skill_level_seen": highest_skill_level_seen,
		"last_payout_currency": last_payout_currency,
		"last_payout_reason": last_payout_reason,
		"saved_at": Time.get_datetime_string_from_system(true),
	}

## Restores from a `to_dict()` dict. Returns false on schema mismatch or
## missing fields. Empty / null input is rejected.
func apply_summary(summary: Variant) -> bool:
	if summary == null or typeof(summary) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = summary as Dictionary
	var schema: String = str(dict.get("schema", ""))
	if schema != SCHEMA_VERSION:
		return false
	meta_currency = maxi(0, int(dict.get("meta_currency", 0)))
	unlocked_class_ids.clear()
	var cls_v: Variant = dict.get("unlocked_class_ids", {})
	if typeof(cls_v) == TYPE_DICTIONARY:
		for k in (cls_v as Dictionary):
			unlocked_class_ids[str(k)] = bool((cls_v as Dictionary)[k])
	unlocked_hub_upgrade_ids.clear()
	var hub_v: Variant = dict.get("unlocked_hub_upgrade_ids", {})
	if typeof(hub_v) == TYPE_DICTIONARY:
		for k in (hub_v as Dictionary):
			unlocked_hub_upgrade_ids[str(k)] = bool((hub_v as Dictionary)[k])
	unlocked_codex_entry_ids.clear()
	var codex_v: Variant = dict.get("unlocked_codex_entry_ids", {})
	if typeof(codex_v) == TYPE_DICTIONARY:
		for k in (codex_v as Dictionary):
			unlocked_codex_entry_ids[str(k)] = bool((codex_v as Dictionary)[k])
	total_runs_completed = maxi(0, int(dict.get("total_runs_completed", 0)))
	total_runs_deaths = maxi(0, int(dict.get("total_runs_deaths", 0)))
	highest_skill_level_seen = maxi(0, int(dict.get("highest_skill_level_seen", 0)))
	last_payout_currency = maxi(0, int(dict.get("last_payout_currency", 0)))
	last_payout_reason = str(dict.get("last_payout_reason", ""))
	return true

## Persists to `user://meta_progression.json`. Returns false on IO failure.
func save_to_disk(save_path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true

## Loads from `user://meta_progression.json`. Returns true on success,
## false when the file is missing, unparseable, or schema-mismatched.
## On any failure, the in-memory state is left at its default values.
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

func get_summary() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"meta_currency": meta_currency,
		"unlock_count": get_unlock_count(),
		"unlocked_class_count": unlocked_class_ids.size(),
		"unlocked_hub_upgrade_count": unlocked_hub_upgrade_ids.size(),
		"unlocked_codex_count": unlocked_codex_entry_ids.size(),
		"total_runs_completed": total_runs_completed,
		"total_runs_deaths": total_runs_deaths,
		"highest_skill_level_seen": highest_skill_level_seen,
		"last_payout_currency": last_payout_currency,
		"last_payout_reason": last_payout_reason,
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Meta Currency: %d" % meta_currency)
	lines.append("Runs Completed: %d   Deaths: %d" % [total_runs_completed, total_runs_deaths])
	lines.append("Hub Upgrades: %d   Classes: %d   Codex: %d" % [
		unlocked_hub_upgrade_ids.size(),
		unlocked_class_ids.size(),
		unlocked_codex_entry_ids.size(),
	])
	if last_payout_currency > 0:
		lines.append("Last Payout: +%d (%s)" % [last_payout_currency, last_payout_reason])
	return lines