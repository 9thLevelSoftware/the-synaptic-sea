extends SceneTree

const ProductAuditReportScript := preload("res://scripts/systems/product_audit_report.gd")
const IntegrationMatrixScript := preload("res://scripts/systems/integration_matrix.gd")

const ROOT_DEFAULT: String = "/Users/christopherwilloughby/the-synaptic-sea"

func _initialize() -> void:
	var root_path: String = OS.get_environment("ROOT")
	if root_path.is_empty():
		root_path = ROOT_DEFAULT
	var report_data: Dictionary = _load_json(root_path + "/data/integration/product_audit_report.json")
	var matrix_data: Dictionary = _load_json(root_path + "/data/integration/cross_system_integration_matrix.json")
	var issue_manifest: Dictionary = _load_json(root_path + "/data/integration/known_issue_fix_manifest.json")
	if report_data.is_empty() or matrix_data.is_empty() or issue_manifest.is_empty():
		_fail("audit report, matrix, or issue manifest missing")
		return

	var matrix = IntegrationMatrixScript.new()
	if not matrix.configure(matrix_data):
		_fail("matrix configure failed")
		return
	var report = ProductAuditReportScript.new()
	if not report.configure(report_data, issue_manifest):
		_fail("product audit report configure failed")
		return
	var validation: Dictionary = report.validate_against_matrix(matrix)
	if not bool(validation.get("pass", false)):
		_fail("audit report validation failed: %s" % JSON.stringify(validation))
		return
	if report.get_blocking_count() > 0:
		_fail("blocking product audit findings remain: %d" % report.get_blocking_count())
		return
	if report.get_fix_card_count() < 1:
		_fail("expected at least one explicit fix/follow-up card")
		return
	if not report.has_product_verdict():
		_fail("product verdict missing")
		return
	print("PRODUCT AUDIT PASS findings=%d fix_cards=%d verdict=%s" % [
		report.get_finding_count(),
		report.get_fix_card_count(),
		report.get_verdict(),
	])
	quit(0)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _fail(reason: String) -> void:
	push_error("PRODUCT AUDIT FAIL reason=%s" % reason)
	quit(1)
