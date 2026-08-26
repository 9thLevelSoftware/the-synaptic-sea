extends RefCounted
class_name PortableSettingsStore

const SettingsState := preload("res://scripts/systems/settings_state.gd")
const Schema := preload("res://scripts/schemas/settings_state_schema.gd")
const FILE_PATH := "user://portable-settings/settings-state-1.json"
const MAX_BYTES := 65536
var storage_path: String = FILE_PATH
var failpoint := ""
var failpoint_hits: Dictionary = {}
var token_queue: Array[String] = []

func save(state: SettingsState) -> bool:
	if not _safe_path() or state == null or not _valid_payload(state.get_payload()): return false
	var document := JSON.stringify({"schema_version":"portable-settings-1", "settings":state.get_payload()})
	if document.to_utf8_buffer().size() > MAX_BYTES: return false
	var directory := storage_path.get_base_dir()
	if _failed("directory") or not _ensure_directory(directory): return false
	var token := _unique_token(storage_path); if token.is_empty(): return false
	var stage := storage_path + ".stage." + token; var backup := storage_path + ".backup." + token
	if _failed("stage_open"): return false
	var f := FileAccess.open(stage, FileAccess.WRITE); if f == null: return false
	f.store_string(document)
	if _failed("stage_write"): f.close(); _remove(stage); return false
	f.flush(); f.close()
	if _failed("stage_verify_open"): _remove(stage); return false
	var check := FileAccess.open(stage, FileAccess.READ); if check == null: _remove(stage); return false
	var text := check.get_as_text(); var length := check.get_length(); check.close()
	if _failed("stage_verify_content") or length > MAX_BYTES or text != document or not _valid_document(JSON.parse_string(text)):
		_remove(stage); return false
	var had_final := FileAccess.file_exists(storage_path)
	if had_final and (_failed("backup_rename") or DirAccess.rename_absolute(ProjectSettings.globalize_path(storage_path), ProjectSettings.globalize_path(backup)) != OK):
		_remove(stage); return false
	if _failed("promote_rename") or DirAccess.rename_absolute(ProjectSettings.globalize_path(stage), ProjectSettings.globalize_path(storage_path)) != OK:
		return _recover(stage, backup, had_final)
	if _failed("final_verify") or not _same_file(storage_path, document): return _recover(stage, backup, had_final)
	if had_final:
		if _failed("cleanup"): return _recover("", backup, true)
		_remove(backup)
	return true

func load() -> SettingsState:
	if not _safe_path(): return null
	var f := FileAccess.open(storage_path, FileAccess.READ); if f == null: return null
	if f.get_length() > MAX_BYTES: f.close(); return null
	var doc: Variant = JSON.parse_string(f.get_as_text()); f.close()
	if not _valid_document(doc): return null
	var result := SettingsState.new(); return result if result.configure(doc.settings) else null

func _valid_document(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != 2 or value.get("schema_version") != "portable-settings-1": return false
	return _valid_payload(value.get("settings"))

func _valid_payload(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY: return false
	var expected := Schema.default_payload().keys()
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	if typeof(value.schema) != TYPE_STRING or value.schema != Schema.SCHEMA_VERSION: return false
	if typeof(value.text_scale) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.text_scale)) or float(value.text_scale) < Schema.MIN_TEXT_SCALE or float(value.text_scale) > Schema.MAX_TEXT_SCALE: return false
	if typeof(value.colorblind_mode) != TYPE_STRING or not Schema.COLORBLIND_MODES.has(value.colorblind_mode): return false
	if typeof(value.difficulty) != TYPE_STRING or not Schema.DIFFICULTIES.has(value.difficulty): return false
	if typeof(value.glyph_scheme) != TYPE_STRING or not Schema.GLYPH_SCHEMES.has(value.glyph_scheme): return false
	if typeof(value.preset_id) != TYPE_STRING or value.preset_id.is_empty() or value.preset_id.length() > 128: return false
	for key in ["motion_reduce", "captions", "hold_to_tap"]:
		if typeof(value[key]) != TYPE_BOOL: return false
	return true

func _ensure_directory(directory: String) -> bool:
	var parent := DirAccess.open("user://"); if parent == null: return false
	var rel := directory.trim_prefix("user://")
	return parent.make_dir_recursive(rel) == OK or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory))

func _recover(stage: String, backup: String, had_final: bool) -> bool:
	_remove(stage); if not had_final: _remove(storage_path); return false
	_remove(storage_path)
	if not _failed("restore_rename") and DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(storage_path)) == OK: return false
	if _failed("restore_copy") or not FileAccess.file_exists(backup): return false
	var src := FileAccess.open(backup, FileAccess.READ); var dst := FileAccess.open(storage_path, FileAccess.WRITE)
	if src == null or dst == null:
		if src != null: src.close()
		if dst != null: dst.close()
		return false
	dst.store_buffer(src.get_buffer(src.get_length())); dst.flush(); src.close(); dst.close(); _same_bytes(storage_path, backup); return false

func _same_file(path: String, expected: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ); if f == null: return false
	var ok := f.get_length() <= MAX_BYTES and f.get_as_text() == expected; f.close(); return ok

func _same_bytes(left: String, right: String) -> bool:
	var a := FileAccess.open(left, FileAccess.READ); var b := FileAccess.open(right, FileAccess.READ)
	if a == null or b == null:
		if a != null: a.close()
		if b != null: b.close()
		return false
	var ok := a.get_length() == b.get_length() and a.get_buffer(a.get_length()) == b.get_buffer(b.get_length()); a.close(); b.close(); return ok

func _remove(path: String) -> void:
	if not path.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _unique_token(final: String) -> String:
	for _i in 32:
		var token: String = token_queue.pop_front() if not token_queue.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
		if token.length() != 32 or token.to_lower() != token or token.contains("-") or token.contains("_"): continue
		if not FileAccess.file_exists(final + ".stage." + token) and not FileAccess.file_exists(final + ".backup." + token): return token
	return ""

func _failed(name: String) -> bool:
	failpoint_hits[name] = int(failpoint_hits.get(name, 0)) + 1; return failpoint == name or failpoint.split(",").has(name)

func _safe_path() -> bool:
	return typeof(storage_path) == TYPE_STRING and storage_path.begins_with("user://") and storage_path.length() > 7 and not storage_path.contains("..")
