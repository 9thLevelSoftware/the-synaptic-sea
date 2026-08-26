extends RefCounted
class_name ProcgenDiagnosticStore

const ROOT: String = "user://procgen/diagnostics/"
const BundleScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_bundle.gd")
var last_error: String = ""

func save(document: Dictionary, request_scope: String = "") -> Dictionary:
	last_error = ""
	if not request_scope.is_empty(): return _fail("scope_not_supported")
	var validator: RefCounted = BundleScript.new()
	if not validator.validate(document): return _fail("invalid:%s" % validator.last_error)
	var identity: String = str(document.identity_hash)
	var capture: String = str(document.capture_hash)
	var path: String = ROOT + identity + "/" + capture + ".json"
	var dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if FileAccess.file_exists(path):
		var existing: String = FileAccess.get_file_as_string(path)
		if existing == JSON.stringify(document): return {"saved": true, "idempotent": true, "path": path}
		return _fail("conflict")
	var temp_path: String = path + ".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return _fail("open")
	file.store_string(JSON.stringify(document))
	file.close()
	if not FileAccess.file_exists(temp_path) or FileAccess.get_file_as_string(temp_path) != JSON.stringify(document):
		_remove_known_temp(temp_path)
		return _fail("readback")
	var temp_absolute: String = ProjectSettings.globalize_path(temp_path)
	var path_absolute: String = ProjectSettings.globalize_path(path)
	var rename_error: Error = DirAccess.rename_absolute(temp_absolute, path_absolute)
	if rename_error != OK:
		_remove_known_temp(temp_path)
		if FileAccess.file_exists(path):
			var raced: String = FileAccess.get_file_as_string(path)
			if raced == JSON.stringify(document): return {"saved": true, "idempotent": true, "path": path}
			return _fail("conflict")
		return _fail("rename")
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != JSON.stringify(document): return _fail("readback")
	return {"saved": true, "idempotent": false, "path": path}

func validate_path(path: String) -> bool:
	var parts: PackedStringArray = path.trim_prefix(ROOT).split("/")
	return path.begins_with(ROOT) and parts.size() == 2 and _is_hex(parts[0], 64) and parts[1].length() == 69 and parts[1].ends_with(".json") and _is_hex(parts[1].trim_suffix(".json"), 64)

func _is_hex(value: String, length: int) -> bool:
	if value.length() != length: return false
	for c in value:
		if not ((c >= "a" and c <= "f") or (c >= "0" and c <= "9")): return false
	return true

func _fail(code: String) -> Dictionary:
	last_error = code
	return {"saved": false, "idempotent": false, "error": code}

func _remove_known_temp(path: String) -> void:
	if path.begins_with(ROOT) and path.ends_with(".tmp") and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
