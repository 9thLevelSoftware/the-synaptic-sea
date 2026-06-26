extends RefCounted
class_name ProductAuditReport

## REQ-INT-006 / REQ-INT-007 product audit report model.
##
## Pure model that validates Task 14's GPT-5.5 product audit artifact: every
## finding has evidence, open contradictions are tied to explicit fix cards, and
## the verdict evaluates the cross-system matrix rather than rubber-stamping it.

const TRACKED_STATUSES: Array = ["tracked", "resolved", "accepted", "deferred_with_card"]

var _report: Dictionary = {}
var _issue_manifest: Dictionary = {}
var _findings: Array = []
var _fix_cards: Array = []

func configure(report_data: Dictionary, issue_manifest: Dictionary) -> bool:
	_report = report_data.duplicate(true) if report_data != null else {}
	_issue_manifest = issue_manifest.duplicate(true) if issue_manifest != null else {}
	_findings = _as_array(_report.get("findings", []))
	_fix_cards = _as_array(_issue_manifest.get("fix_cards", _issue_manifest.get("issues", [])))
	if _report.is_empty() or _findings.is_empty():
		return false
	if not has_product_verdict():
		return false
	for raw_finding in _findings:
		var finding: Dictionary = _as_dict(raw_finding)
		if str(finding.get("finding_id", "")).is_empty():
			return false
		if _as_array(finding.get("evidence", [])).is_empty():
			return false
		var severity: String = str(finding.get("severity", "")).to_lower()
		if severity in ["blocking", "follow_up", "contradiction"] and str(finding.get("fix_key", "")).is_empty():
			return false
	return true

func validate_against_matrix(matrix) -> Dictionary:
	if matrix == null or not matrix.has_method("get_entry_count"):
		return {"pass": false, "reason": "matrix_missing"}
	var min_systems: int = int(_report.get("min_matrix_entries", 14))
	if int(matrix.get_entry_count()) < min_systems:
		return {"pass": false, "reason": "matrix_entry_count", "entry_count": matrix.get_entry_count(), "min": min_systems}
	var required_stages: Array = _as_array(_report.get("required_loop_stages", []))
	if matrix.has_method("covers_loop_stages") and not matrix.covers_loop_stages(required_stages):
		return {"pass": false, "reason": "loop_stage_coverage"}
	var missing_links: Array = []
	for raw_finding in _findings:
		var finding: Dictionary = _as_dict(raw_finding)
		var fix_key: String = str(finding.get("fix_key", ""))
		if fix_key.is_empty():
			continue
		if not _manifest_has_fix_key(fix_key):
			missing_links.append(fix_key)
	if not missing_links.is_empty():
		return {"pass": false, "reason": "fix_keys_missing", "missing": missing_links}
	return {"pass": true, "entry_count": matrix.get_entry_count(), "findings": get_finding_count(), "fix_cards": get_fix_card_count()}

func get_finding_count() -> int:
	return _findings.size()

func get_fix_card_count() -> int:
	var count: int = 0
	for raw in _fix_cards:
		var card: Dictionary = _as_dict(raw)
		var card_id: String = str(card.get("kanban_card_id", card.get("linked_task_id", "")))
		if not card_id.is_empty():
			count += 1
	return count

func get_blocking_count() -> int:
	var count: int = 0
	for raw_finding in _findings:
		var finding: Dictionary = _as_dict(raw_finding)
		var severity: String = str(finding.get("severity", "")).to_lower()
		var status: String = str(finding.get("status", "")).to_lower()
		if severity == "blocking" and not status in TRACKED_STATUSES:
			count += 1
	return count

func has_product_verdict() -> bool:
	var verdict: String = get_verdict()
	return not verdict.is_empty()

func get_verdict() -> String:
	return str(_report.get("verdict", ""))

func get_summary() -> Dictionary:
	return {
		"verdict": get_verdict(),
		"finding_count": get_finding_count(),
		"fix_card_count": get_fix_card_count(),
		"blocking_count": get_blocking_count(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Product Audit: verdict=%s findings=%d fix_cards=%d blocking=%d" % [
		get_verdict(),
		get_finding_count(),
		get_fix_card_count(),
		get_blocking_count(),
	])
	return lines

func _manifest_has_fix_key(fix_key: String) -> bool:
	for raw in _fix_cards:
		var card: Dictionary = _as_dict(raw)
		if str(card.get("fix_key", "")) == fix_key:
			var card_id: String = str(card.get("kanban_card_id", card.get("linked_task_id", "")))
			return not card_id.is_empty()
	return false

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if value == null:
		return []
	return [value]

func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}
