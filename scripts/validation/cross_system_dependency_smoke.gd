extends SceneTree

const IntegrationMatrixScript := preload("res://scripts/systems/integration_matrix.gd")
const DependencyValidatorScript := preload("res://scripts/systems/dependency_validator.gd")

const REQUIRED_STAGES: Array = ["prepare", "derelict", "survive", "loot", "craft", "return", "upgrade"]

func _initialize() -> void:
	var root_path: String = ProjectSettings.globalize_path("res://")

	var matrix_data: Dictionary = _load_json(root_path + "/data/integration/cross_system_integration_matrix.json")
	if matrix_data.is_empty():
		_fail("cross-system integration matrix missing or empty")
		return
	var matrix = IntegrationMatrixScript.new()
	if not matrix.configure(matrix_data):
		_fail("integration matrix rejected data")
		return
	if matrix.get_entry_count() < 14:
		_fail("expected >=14 package entries, got %d" % matrix.get_entry_count())
		return
	if not matrix.covers_loop_stages(REQUIRED_STAGES):
		_fail("matrix does not cover required loop stages: %s" % ",".join(REQUIRED_STAGES))
		return

	var validator = DependencyValidatorScript.new()
	validator.configure(matrix)
	var files_result: Dictionary = validator.verify_file_evidence(root_path)
	if not bool(files_result.get("ok", false)):
		_fail("file evidence missing: %s" % JSON.stringify(files_result.get("missing", [])))
		return
	var req_text: String = _read_text(root_path + "/docs/game/05_requirements.md")
	var req_result: Dictionary = validator.verify_requirement_rows(req_text)
	if not bool(req_result.get("ok", false)):
		_fail("requirement rows missing: %s" % JSON.stringify(req_result.get("missing", [])))
		return
	var validation_text: String = _read_text(root_path + "/docs/game/06_validation_plan.md")
	var marker_result: Dictionary = validator.verify_validation_markers(validation_text)
	if not bool(marker_result.get("ok", false)):
		_fail("validation markers missing: %s" % JSON.stringify(marker_result.get("missing", [])))
		return
	var docs_result: Dictionary = validator.verify_documentation_evidence(root_path)
	if not bool(docs_result.get("ok", false)):
		_fail("documentation evidence missing: %s" % JSON.stringify(docs_result.get("missing", [])))
		return

	print("CROSS SYSTEM DEPENDENCY PASS systems=%d requirements=%d smokes=%d docs=%d" % [
		matrix.get_entry_count(),
		int(req_result.get("checked", 0)),
		int(marker_result.get("checked", 0)),
		int(docs_result.get("checked", 0)),
	])
	quit(0)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _fail(reason: String) -> void:
	push_error("CROSS SYSTEM DEPENDENCY FAIL reason=%s" % reason)
	quit(1)
