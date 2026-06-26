extends RefCounted
class_name ReleaseReadinessLedger

## REQ-RL-008 release readiness ledger.
##
## Pure in-memory evidence tracker. Reads the release checklist
## (`data/release/release_checklist.json`) and tracks evidence rows
## that tag themselves `source=local` (smoke output, checklist tick) or
## `source=external` (Steam / itch / human sign-off).
##
## `source=external` rows MUST carry a non-empty `evidence_path`; the
## schema rejects empty ones so a CI step that forgets to attach a
## build URL fails loudly.
##
## Per ADR-0029: this is the gate reviewer's machine-checkable audit
## trail. The smoke proves the local-vs-external discrimination and the
## external evidence requirement.

const VALID_SOURCES: Array = ["local", "external"]
const VALID_STATUSES: Array = ["pass", "fail", "pending"]
const VALID_CATEGORIES: Array = ["pre_launch", "launch_day", "post_launch"]

var _checks: Dictionary = {}     # check_id -> {description, category}
var _check_ids: Array = []
var _rows: Array = []            # [{check_id, status, source, evidence_path, captured_at, note}]

func configure(checklist: Dictionary) -> void:
	_checks.clear()
	_check_ids.clear()
	_rows.clear()
	if checklist == null:
		checklist = {}
	var list_variant: Variant = checklist.get("checks", [])
	if typeof(list_variant) != TYPE_ARRAY:
		return
	for entry in (list_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var check_id: String = str(dict.get("check_id", ""))
		if check_id.is_empty():
			continue
		var category: String = str(dict.get("category", ""))
		_checks[check_id] = {
			"description": str(dict.get("description", "")),
			"category": category,
		}
		_check_ids.append(check_id)

func is_known_check(check_id: String) -> bool:
	return check_id in _checks

func get_check_ids() -> Array:
	return _check_ids.duplicate()

func get_check_count() -> int:
	return _check_ids.size()

func get_check_category(check_id: String) -> String:
	if not _checks.has(check_id):
		return ""
	return str(_checks[check_id].get("category", ""))

func record_local_evidence(check_id: String, status: String, evidence_path: String = "", note: String = "") -> bool:
	return _record(check_id, status, "local", evidence_path, note)

func record_external_evidence(check_id: String, status: String, evidence_path: String, captured_at: String = "", note: String = "") -> bool:
	if evidence_path.is_empty():
		push_warning("ReleaseReadinessLedger: external evidence rejected, evidence_path is required")
		return false
	return _record(check_id, status, "external", evidence_path, note, captured_at)

func _record(check_id: String, status: String, source: String, evidence_path: String, note: String, captured_at: String = "") -> bool:
	if check_id.is_empty() or not check_id in _checks:
		push_warning("ReleaseReadinessLedger: unknown check_id=%s" % check_id)
		return false
	if not status in VALID_STATUSES:
		push_warning("ReleaseReadinessLedger: invalid status=%s" % status)
		return false
	if not source in VALID_SOURCES:
		push_warning("ReleaseReadinessLedger: invalid source=%s" % source)
		return false
	if source == "external" and evidence_path.is_empty():
		# Already warned by record_external_evidence; defensive duplicate.
		return false
	var captured: String = captured_at if not captured_at.is_empty() else Time.get_datetime_string_from_system(true)
	_rows.append({
		"check_id": check_id,
		"status": status,
		"source": source,
		"evidence_path": evidence_path,
		"captured_at": captured,
		"note": note,
	})
	return true

func get_rows() -> Array:
	return _rows.duplicate(true)

func get_row_count() -> int:
	return _rows.size()

func get_local_count() -> int:
	var count: int = 0
	for row in _rows:
		if str(row.get("source", "")) == "local":
			count += 1
	return count

func get_external_count() -> int:
	var count: int = 0
	for row in _rows:
		if str(row.get("source", "")) == "external":
			count += 1
	return count

func get_category_counts() -> Dictionary:
	var counts: Dictionary = {"pre_launch": 0, "launch_day": 0, "post_launch": 0}
	for row in _rows:
		var check_id: String = str(row.get("check_id", ""))
		if not _checks.has(check_id):
			continue
		var category: String = str(_checks[check_id].get("category", ""))
		if counts.has(category):
			counts[category] = int(counts[category]) + 1
	return counts

func get_status_counts() -> Dictionary:
	var counts: Dictionary = {"pass": 0, "fail": 0, "pending": 0}
	for row in _rows:
		var status: String = str(row.get("status", ""))
		if counts.has(status):
			counts[status] = int(counts[status]) + 1
	return counts

func get_summary() -> Dictionary:
	return {
		"check_count": _check_ids.size(),
		"row_count": _rows.size(),
		"local_count": get_local_count(),
		"external_count": get_external_count(),
		"category_counts": get_category_counts(),
		"status_counts": get_status_counts(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Release Readiness: %d checks, %d rows" % [_check_ids.size(), _rows.size()])
	var status_counts: Dictionary = get_status_counts()
	lines.append("  pass=%d fail=%d pending=%d" % [
		int(status_counts.get("pass", 0)),
		int(status_counts.get("fail", 0)),
		int(status_counts.get("pending", 0)),
	])
	var cat_counts: Dictionary = get_category_counts()
	for category in VALID_CATEGORIES:
		lines.append("  %s=%d" % [category, int(cat_counts.get(category, 0))])
	return lines