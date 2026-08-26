extends RefCounted
class_name GeneratedWorldSaveService

const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const DIRECTORY := "user://generated-world-save-1"
const FILE_NAME := "generated-world.save.json"
const MAX_BYTES := 1048576
const SLOT_RE := "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
var storage_directory: String = DIRECTORY
var failpoint: String = ""
var failpoint_hits: Dictionary = {}
var token_queue: Array[String] = []
var _request_counter: int = 0

func path_for(slot_id: Variant = "world") -> String:
	if not _safe_directory() or typeof(slot_id) != TYPE_STRING: return ""
	var re := RegEx.new(); re.compile(SLOT_RE)
	return storage_directory.path_join(slot_id + "." + FILE_NAME) if re.search(slot_id) != null else ""

func load_and_validate(slot_id: String, compatibility: RefCounted):
	var path := path_for(slot_id)
	if path.is_empty(): return Result.make(Result.CORRUPT, "invalid_slot", "")
	if not FileAccess.file_exists(path): return Result.make(Result.IO_FAILURE, "missing_file", path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return Result.make(Result.IO_FAILURE, "open_failed", path)
	var length := f.get_length()
	if length > MAX_BYTES: f.close(); return Result.make(Result.CORRUPT, "document_too_large", path)
	var bytes := f.get_buffer(length); f.close()
	if bytes.size() != length: return Result.make(Result.IO_FAILURE, "read_failed", path)
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return Result.make(Result.CORRUPT, "json_parse_failed", path)
	var parsed: Variant = parser.data
	if compatibility == null or not compatibility.has_method("evaluate"): return Result.make(Result.IO_FAILURE, "compatibility_unavailable", path)
	var evaluated: Variant = compatibility.evaluate(parsed, path)
	if typeof(evaluated) != TYPE_OBJECT or not is_instance_valid(evaluated) or not (evaluated is Result) or not evaluated.validate():
		return Result.make(Result.IO_FAILURE, "compatibility_unavailable", path)
	return evaluated

func save(slot_id: String, envelope: RefCounted) -> bool:
	var final := path_for(slot_id)
	if final.is_empty() or envelope == null or not envelope is Envelope: return false
	var normalized: Variant = Envelope.from_dict(envelope.to_dict())
	if normalized == null: return false
	var document := JSON.stringify(normalized.to_dict())
	if document.to_utf8_buffer().size() > MAX_BYTES or Envelope.from_dict(JSON.parse_string(document)) == null: return false
	if _failed("directory") or not _ensure_directory(): return false
	var token := _unique_token(final)
	if token.is_empty(): return false
	var stage := final + ".stage." + token; var backup := final + ".backup." + token
	if _failed("stage_open"): return false
	var f := FileAccess.open(stage, FileAccess.WRITE)
	if f == null: return false
	f.store_string(document)
	if _failed("stage_write"): f.close(); _remove(stage); return false
	f.flush(); f.close()
	if _failed("stage_verify_open"): _remove(stage); return false
	var check := FileAccess.open(stage, FileAccess.READ)
	if check == null: _remove(stage); return false
	var bytes := check.get_length(); var text := check.get_as_text(); check.close()
	if _failed("stage_verify_content") or bytes > MAX_BYTES or text != document or Envelope.from_dict(JSON.parse_string(text)) == null:
		_remove(stage); return false
	var had_final := FileAccess.file_exists(final)
	if had_final:
		if _failed("backup_rename") or DirAccess.rename_absolute(ProjectSettings.globalize_path(final), ProjectSettings.globalize_path(backup)) != OK:
			_remove(stage); return false
	if _failed("promote_rename") or DirAccess.rename_absolute(ProjectSettings.globalize_path(stage), ProjectSettings.globalize_path(final)) != OK:
		return _recover(final, stage, backup, had_final)
	if _failed("final_verify") or not _same_file(final, document): return _recover(final, stage, backup, had_final)
	if had_final:
		if _failed("cleanup"): return _recover(final, "", backup, true)
		_remove(backup)
	return true

func _ensure_directory() -> bool:
	if not _safe_directory(): return false
	var d := DirAccess.open("user://")
	if d == null: return false
	var rel := storage_directory.trim_prefix("user://")
	return d.make_dir_recursive(rel) == OK or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(storage_directory))

func _recover(final: String, stage: String, backup: String, had_final: bool) -> bool:
	_remove(stage)
	if not had_final:
		_remove(final)
		return false
	_remove(final)
	if not _failed("restore_rename") and DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(final)) == OK: return false
	if _failed("restore_copy") or not FileAccess.file_exists(backup): return false
	var src := FileAccess.open(backup, FileAccess.READ); var dst := FileAccess.open(final, FileAccess.WRITE)
	if src == null or dst == null:
		if src != null: src.close()
		if dst != null: dst.close()
		return false
	var source_length := src.get_length(); var source_bytes := src.get_buffer(source_length); src.close()
	if source_bytes.size() != source_length: dst.close(); _remove(final); return false
	dst.store_buffer(source_bytes); dst.flush(); dst.close()
	if _same_bytes(final, backup): _remove(backup)
	else: _remove(final)
	return false

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
		var token: String = token_queue.pop_front() if not token_queue.is_empty() else _crypto_token()
		if not _valid_token(token): continue
		if not FileAccess.file_exists(final + ".stage." + token) and not FileAccess.file_exists(final + ".backup." + token): return token
	return ""

func _crypto_token() -> String:
	_request_counter += 1
	var random_hex := Crypto.new().generate_random_bytes(12).hex_encode()
	return random_hex + ("%08x" % (_request_counter & 0xffffffff))

func _valid_token(token: String) -> bool:
	if token.length() != 32: return false
	for character in token:
		if not (character >= "0" and character <= "9" or character >= "a" and character <= "f"): return false
	return true

func _failed(name: String) -> bool:
	failpoint_hits[name] = int(failpoint_hits.get(name, 0)) + 1
	return failpoint == name or failpoint.split(",").has(name)

func _safe_directory() -> bool:
	if typeof(storage_directory) != TYPE_STRING or not storage_directory.begins_with("user://"): return false
	var relative := storage_directory.trim_prefix("user://").trim_suffix("/")
	if relative.is_empty() or relative.contains("\\"): return false
	var segment_re := RegEx.new(); segment_re.compile("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
	for segment in relative.split("/", false):
		if segment in [".", ".."] or segment_re.search(segment) == null: return false
	return true
