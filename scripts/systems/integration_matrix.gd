extends RefCounted
class_name IntegrationMatrix

## REQ-INT-001 / REQ-INT-002 cross-system package dependency matrix.
##
## Pure model. It normalizes the data-driven integration manifest into
## package rows that can be audited by `DependencyValidator` and the Task 14
## smokes. It never touches the scene tree.

var _metadata: Dictionary = {}
var _entries: Array = []
var _entries_by_id: Dictionary = {}

func configure(data: Dictionary) -> bool:
	_metadata.clear()
	_entries.clear()
	_entries_by_id.clear()
	if data == null or data.is_empty():
		return false
	_metadata = _as_dict(data.get("metadata", {}))
	var raw_entries: Array = _as_array(data.get("systems", data.get("entries", [])))
	if raw_entries.is_empty():
		return false
	for raw in raw_entries:
		var row: Dictionary = _as_dict(raw)
		if row.is_empty():
			continue
		var package_id: String = str(row.get("package_id", row.get("id", "")))
		if package_id.is_empty():
			continue
		var normalized: Dictionary = row.duplicate(true)
		normalized["package_id"] = package_id
		normalized["requirements"] = _to_string_array(row.get("requirements", []))
		normalized["code_files"] = _to_string_array(row.get("code_files", []))
		normalized["docs_files"] = _to_string_array(row.get("docs_files", []))
		normalized["data_files"] = _to_string_array(row.get("data_files", []))
		normalized["smoke_files"] = _to_string_array(row.get("smoke_files", []))
		normalized["smoke_markers"] = _to_string_array(row.get("smoke_markers", []))
		normalized["loop_stages"] = _to_string_array(row.get("loop_stages", []))
		normalized["dependencies"] = _to_string_array(row.get("dependencies", []))
		normalized["requires_smoke"] = bool(row.get("requires_smoke", true))
		_entries.append(normalized)
		_entries_by_id[package_id] = normalized
	return not _entries.is_empty()

func get_entry_count() -> int:
	return _entries.size()

func get_entries() -> Array:
	return _entries.duplicate(true)

func get_entry(package_id: String) -> Dictionary:
	return _as_dict(_entries_by_id.get(package_id, {})).duplicate(true)

func has_entry(package_id: String) -> bool:
	return _entries_by_id.has(package_id)

func get_package_ids() -> Array:
	var ids: Array = _entries_by_id.keys()
	ids.sort()
	return ids

func get_requirement_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	for entry in _entries:
		for rid in _as_array((entry as Dictionary).get("requirements", [])):
			seen[str(rid)] = true
	var ids: Array = seen.keys()
	ids.sort()
	var out := PackedStringArray()
	for rid in ids:
		out.append(str(rid))
	return out

func get_smoke_markers() -> PackedStringArray:
	var seen: Dictionary = {}
	for entry in _entries:
		for marker in _as_array((entry as Dictionary).get("smoke_markers", [])):
			if not str(marker).is_empty():
				seen[str(marker)] = true
	var markers: Array = seen.keys()
	markers.sort()
	var out := PackedStringArray()
	for marker in markers:
		out.append(str(marker))
	return out

func get_document_paths() -> PackedStringArray:
	var seen: Dictionary = {}
	for entry in _entries:
		for path in _as_array((entry as Dictionary).get("docs_files", [])):
			if not str(path).is_empty():
				seen[str(path)] = true
	var paths: Array = seen.keys()
	paths.sort()
	var out := PackedStringArray()
	for path in paths:
		out.append(str(path))
	return out

func covers_loop_stages(required_stages: Array) -> bool:
	var coverage: Dictionary = get_loop_stage_coverage()
	for stage in required_stages:
		if not coverage.has(str(stage)):
			return false
	return true

func get_loop_stage_coverage() -> Dictionary:
	var coverage: Dictionary = {}
	for entry in _entries:
		for stage in _as_array((entry as Dictionary).get("loop_stages", [])):
			var key: String = str(stage)
			if key.is_empty():
				continue
			coverage[key] = int(coverage.get(key, 0)) + 1
	return coverage

func get_missing_required_fields() -> Array:
	var missing: Array = []
	for entry in _entries:
		var row: Dictionary = entry as Dictionary
		var package_id: String = str(row.get("package_id", ""))
		for field_name in ["title", "task_id", "status", "loop_stages"]:
			if not row.has(field_name) or _is_empty(row.get(field_name)):
				missing.append({"package_id": package_id, "field": field_name})
		if bool(row.get("requires_smoke", true)) and _as_array(row.get("smoke_markers", [])).is_empty():
			missing.append({"package_id": package_id, "field": "smoke_markers"})
	return missing

func get_summary() -> Dictionary:
	return {
		"entry_count": get_entry_count(),
		"requirement_count": get_requirement_ids().size(),
		"smoke_marker_count": get_smoke_markers().size(),
		"document_count": get_document_paths().size(),
		"loop_stage_coverage": get_loop_stage_coverage(),
		"missing_required_fields": get_missing_required_fields(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var summary: Dictionary = get_summary()
	lines.append("Integration Matrix: %d package rows" % int(summary.get("entry_count", 0)))
	lines.append("  requirements=%d smoke_markers=%d docs=%d" % [
		int(summary.get("requirement_count", 0)),
		int(summary.get("smoke_marker_count", 0)),
		int(summary.get("document_count", 0)),
	])
	var coverage: Dictionary = summary.get("loop_stage_coverage", {}) as Dictionary
	var stages: Array = coverage.keys()
	stages.sort()
	for stage in stages:
		lines.append("  %s=%d" % [str(stage), int(coverage[stage])])
	return lines

func _to_string_array(value: Variant) -> Array:
	var out: Array = []
	for item in _as_array(value):
		out.append(str(item))
	return out

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

func _is_empty(value: Variant) -> bool:
	if value == null:
		return true
	if typeof(value) == TYPE_STRING:
		return str(value).is_empty()
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).is_empty()
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).is_empty()
	return false
