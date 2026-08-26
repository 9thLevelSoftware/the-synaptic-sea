extends RefCounted
class_name GeneratedWorldSaveService

const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const Compatibility := preload("res://scripts/systems/generated_world_compatibility.gd")

const DIRECTORY := "user://generated-world-save-1"
const FILE_NAME := "generated-world.save.json"
const MAX_BYTES := 1048576
const _SLOT_RE := "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
var _request_counter: int = 0
var failpoint: String = ""

func path_for(slot_id := "world") -> String:
	if typeof(slot_id) != TYPE_STRING: return ""
	var re := RegEx.new()
	re.compile(_SLOT_RE)
	if re.search(str(slot_id)) == null:
		return ""
	return DIRECTORY.path_join(str(slot_id) + "." + FILE_NAME)

func load_and_validate(slot_id: String, compatibility: RefCounted):
	var path := path_for(slot_id)
	if path.is_empty(): return Result.make(Result.CORRUPT, "invalid_slot", "")
	if not FileAccess.file_exists(path):
		return Result.make(Result.IO_FAILURE, "missing_file", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return Result.make(Result.IO_FAILURE, "open_failed", path)
	if file.get_length() > MAX_BYTES:
		file.close()
		return Result.make(Result.CORRUPT, "document_too_large", path)
	var text := file.get_as_text(); file.close()
	var parsed: Variant = JSON.parse_string(text)
	if compatibility == null or not compatibility.has_method("evaluate"): return Result.make(Result.IO_FAILURE, "compatibility_unavailable", path)
	var result: Variant = compatibility.evaluate(parsed, path)
	return result

func save(slot_id: String, envelope: RefCounted) -> bool:
	if path_for(slot_id).is_empty() or envelope == null or not envelope is Envelope or Envelope.from_dict(envelope.to_dict()) == null: return false
	var dir := DirAccess.open("user://")
	if dir == null or _failed("directory") or dir.make_dir_recursive("generated-world-save-1") != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIRECTORY)):
		return false
	var final_path := path_for(slot_id)
	var stage_path := final_path + ".stage." + _request_token()
	var backup_path := final_path + ".backup." + _request_token()
	if _failed("stage_open"): return false
	var file := FileAccess.open(stage_path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(envelope.to_dict()))
	if _failed("stage_write"): file.close(); DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	file.flush(); file.close()
	var check := FileAccess.open(stage_path, FileAccess.READ)
	if _failed("stage_verify"): if check != null: check.close(); DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var valid := check != null and check.get_length() <= MAX_BYTES and Envelope.from_dict(JSON.parse_string(check.get_as_text())) != null
	if check != null: check.close()
	if not valid: DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var had_final := FileAccess.file_exists(final_path)
	if had_final and (_failed("backup") or DirAccess.rename_absolute(ProjectSettings.globalize_path(final_path), ProjectSettings.globalize_path(backup_path)) != OK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(stage_path), ProjectSettings.globalize_path(final_path)) if not _failed("promote") else ERR_CANT_CREATE
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path))
		if had_final and not _failed("restore"): DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(final_path))
		return false
	if had_final: DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return true

func _request_token() -> String:
	_request_counter += 1
	return "%s-%s-%s" % [str(Time.get_ticks_usec()), str(randi()), str(_request_counter)]

func _failed(stage: String) -> bool:
	return failpoint == stage
