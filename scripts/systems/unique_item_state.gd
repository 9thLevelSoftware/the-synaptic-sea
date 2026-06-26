extends RefCounted
class_name UniqueItemState

var claimed_unique_ids: Dictionary = {}
var claimed_seed_keys: Dictionary = {}
var unlocked_codex_entry_ids: Dictionary = {}

func configure(data: Dictionary = {}) -> void:
	claimed_unique_ids.clear()
	claimed_seed_keys.clear()
	unlocked_codex_entry_ids.clear()
	if data.is_empty():
		return
	apply_summary(data)

func is_claimed(unique_id: String) -> bool:
	return not unique_id.is_empty() and claimed_unique_ids.has(unique_id)

func is_seed_claimed(seed_key: String) -> bool:
	return not seed_key.is_empty() and claimed_seed_keys.has(seed_key)

func can_claim(unique_id: String, seed_key: String = "") -> bool:
	if unique_id.is_empty():
		return false
	if is_claimed(unique_id):
		return false
	if not seed_key.is_empty() and is_seed_claimed(seed_key):
		return false
	return true

func claim(unique_id: String, seed_key: String = "", codex_entry_id: String = "") -> bool:
	if not can_claim(unique_id, seed_key):
		return false
	claimed_unique_ids[unique_id] = true
	if not seed_key.is_empty():
		claimed_seed_keys[seed_key] = true
	if not codex_entry_id.is_empty():
		unlocked_codex_entry_ids[codex_entry_id] = true
	return true

func record_codex_unlock(entry_id: String) -> bool:
	if entry_id.is_empty() or unlocked_codex_entry_ids.has(entry_id):
		return false
	unlocked_codex_entry_ids[entry_id] = true
	return true

func reset() -> void:
	claimed_unique_ids.clear()
	claimed_seed_keys.clear()
	unlocked_codex_entry_ids.clear()

func get_summary() -> Dictionary:
	return {
		"claimed_unique_ids": claimed_unique_ids.duplicate(),
		"claimed_seed_keys": claimed_seed_keys.duplicate(),
		"unlocked_codex_entry_ids": unlocked_codex_entry_ids.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	claimed_unique_ids.clear()
	claimed_seed_keys.clear()
	unlocked_codex_entry_ids.clear()
	var unique_v: Variant = summary.get("claimed_unique_ids", {})
	if unique_v is Dictionary:
		for key in (unique_v as Dictionary):
			if bool((unique_v as Dictionary)[key]):
				claimed_unique_ids[str(key)] = true
	var seed_v: Variant = summary.get("claimed_seed_keys", {})
	if seed_v is Dictionary:
		for key in (seed_v as Dictionary):
			if bool((seed_v as Dictionary)[key]):
				claimed_seed_keys[str(key)] = true
	var codex_v: Variant = summary.get("unlocked_codex_entry_ids", {})
	if codex_v is Dictionary:
		for key in (codex_v as Dictionary):
			if bool((codex_v as Dictionary)[key]):
				unlocked_codex_entry_ids[str(key)] = true
	return true

func get_status_lines() -> PackedStringArray:
	return PackedStringArray([
		"unique_claimed=%d" % claimed_unique_ids.size(),
		"unique_seed_keys=%d" % claimed_seed_keys.size(),
		"unique_codex=%d" % unlocked_codex_entry_ids.size(),
	])
