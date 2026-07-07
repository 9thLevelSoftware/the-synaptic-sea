extends SceneTree

const IntegrationMatrixScript := preload("res://scripts/systems/integration_matrix.gd")
const DependencyValidatorScript := preload("res://scripts/systems/dependency_validator.gd")

const REQUIRED_STAGES: Array = ["prepare", "derelict", "survive", "loot", "craft", "return", "upgrade"]

func _initialize() -> void:
	var root_path: String = ProjectSettings.globalize_path("res://")

	var matrix_data: Dictionary = _load_json(root_path.path_join("data/integration/cross_system_integration_matrix.json"))
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
	var req_text: String = _read_text(root_path.path_join("docs/game/05_requirements.md"))
	var req_result: Dictionary = validator.verify_requirement_rows(req_text)
	if not bool(req_result.get("ok", false)):
		_fail("requirement rows missing: %s" % JSON.stringify(req_result.get("missing", [])))
		return
	var validation_text: String = _validation_marker_evidence(root_path, matrix)
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

func _validation_marker_evidence(root_path: String, matrix) -> String:
	# Registered bundle markers live in 06_validation_plan.md; standalone
	# promotion-candidate markers live in the smoke scripts themselves.
	var evidence: String = _read_text(root_path.path_join("docs/game/06_validation_plan.md"))
	if matrix == null or not matrix.has_method("get_entries"):
		return evidence
	for entry_variant in matrix.get_entries():
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var markers: Array = _string_array(entry.get("smoke_markers", []))
		if markers.is_empty():
			continue
		var smoke_files: Variant = entry.get("smoke_files", [])
		if not (smoke_files is Array):
			continue
		for smoke_path_variant in smoke_files:
			var smoke_path: String = str(smoke_path_variant)
			if smoke_path.is_empty():
				continue
			var path: String = smoke_path if smoke_path.begins_with("res://") else root_path.path_join(smoke_path)
			var marker_lines: PackedStringArray = _extract_marker_print_lines(path, markers)
			if not marker_lines.is_empty():
				evidence += "\n" + "\n".join(marker_lines)
	return evidence

func _extract_marker_print_lines(path: String, markers: Array) -> PackedStringArray:
	var matches := PackedStringArray()
	var seen: Dictionary = {}
	var text: String = _read_text(path)
	if text.is_empty():
		return matches
	for raw_line in text.split("\n", false):
		var line: String = str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.find("#") == 0:
			continue
		if not line.contains("print("):
			continue
		for marker_variant in markers:
			var marker: String = str(marker_variant)
			if marker.is_empty() or seen.has(marker):
				continue
			if line.contains(marker):
				matches.append(line)
				seen[marker] = true
	return matches

func _string_array(value: Variant) -> Array:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(str(item))
		return out
	if value == null:
		return []
	return [str(value)]

func _fail(reason: String) -> void:
	push_error("CROSS SYSTEM DEPENDENCY FAIL reason=%s" % reason)
	quit(1)
