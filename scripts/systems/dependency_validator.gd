extends RefCounted
class_name DependencyValidator

## REQ-INT-002 cross-system dependency verifier.
##
## Verifies that every matrix row has concrete file, requirement, marker, and
## documentation evidence. This is intentionally a pure host-file validator for
## headless smokes; it does not run subprocesses or touch the scene tree.

var _entries: Array = []

func configure(matrix) -> void:
	_entries.clear()
	if matrix != null and matrix.has_method("get_entries"):
		_entries = matrix.get_entries()

func verify_file_evidence(root_path: String) -> Dictionary:
	var missing: Array = []
	var checked: int = 0
	for entry in _entries:
		var row: Dictionary = entry as Dictionary
		for field_name in ["code_files", "smoke_files", "data_files"]:
			for path in _as_array(row.get(field_name, [])):
				var file_path: String = str(path)
				if file_path.is_empty():
					continue
				checked += 1
				if not _file_exists(root_path, file_path):
					missing.append({"package_id": str(row.get("package_id", "")), "field": field_name, "path": file_path})
	return {"ok": missing.is_empty(), "checked": checked, "missing": missing}

func verify_documentation_evidence(root_path: String) -> Dictionary:
	var missing: Array = []
	var checked: int = 0
	for entry in _entries:
		var row: Dictionary = entry as Dictionary
		for path in _as_array(row.get("docs_files", [])):
			var file_path: String = str(path)
			if file_path.is_empty():
				continue
			checked += 1
			if not _file_exists(root_path, file_path):
				missing.append({"package_id": str(row.get("package_id", "")), "path": file_path})
	return {"ok": missing.is_empty(), "checked": checked, "missing": missing}

func verify_requirement_rows(requirements_text: String) -> Dictionary:
	var missing: Array = []
	var checked: int = 0
	for entry in _entries:
		var row: Dictionary = entry as Dictionary
		for req_id in _as_array(row.get("requirements", [])):
			var rid: String = str(req_id)
			if rid.is_empty():
				continue
			checked += 1
			if not requirements_text.contains("## %s:" % rid):
				missing.append({"package_id": str(row.get("package_id", "")), "requirement": rid})
	return {"ok": missing.is_empty(), "checked": checked, "missing": missing}

func verify_validation_markers(validation_text: String) -> Dictionary:
	var missing: Array = []
	var checked: int = 0
	for entry in _entries:
		var row: Dictionary = entry as Dictionary
		if not bool(row.get("requires_smoke", true)):
			continue
		for marker in _as_array(row.get("smoke_markers", [])):
			var marker_text: String = str(marker)
			if marker_text.is_empty():
				continue
			checked += 1
			if not validation_text.contains(marker_text):
				missing.append({"package_id": str(row.get("package_id", "")), "marker": marker_text})
	return {"ok": missing.is_empty(), "checked": checked, "missing": missing}

func get_summary() -> Dictionary:
	return {"entry_count": _entries.size()}

func _file_exists(root_path: String, path: String) -> bool:
	if path.begins_with("res://"):
		return FileAccess.file_exists(path)
	if path.begins_with("/"):
		return FileAccess.file_exists(path)
	return FileAccess.file_exists(root_path.path_join(path))

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if value == null:
		return []
	return [value]
