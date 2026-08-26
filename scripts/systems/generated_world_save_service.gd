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

func path_for(slot_id := "world") -> String:
	var re := RegEx.new()
	re.compile(_SLOT_RE)
	if re.search(str(slot_id)) == null:
		return ""
	return DIRECTORY.path_join(str(slot_id) + "." + FILE_NAME)

func load_and_validate(slot_id: String, compatibility: RefCounted):
	var path := path_for(slot_id)
	if not FileAccess.file_exists(path):
		return Result.make(Result.IO_FAILURE, "missing_file", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return Result.make(Result.IO_FAILURE, "open_failed", path)
	if file.get_length() > MAX_BYTES:
		file.close()
		return Result.make(Result.CORRUPT, "document_too_large", path)
	var text := file.get_as_text(); file.close()
	var parsed: Variant = JSON.parse_string(text)
	var result: Variant = compatibility.evaluate(parsed, path)
	return result

func save(slot_id: String, envelope: RefCounted) -> bool:
	if envelope == null or Envelope.from_dict(envelope.to_dict()) == null: return false
	var dir := DirAccess.open("user://")
	if dir == null or dir.make_dir_recursive("generated-world-save-1") != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIRECTORY)):
		return false
	var final_path := path_for(slot_id)
	var stage_path := final_path + ".stage." + _request_token()
	var backup_path := final_path + ".backup." + _request_token()
	var file := FileAccess.open(stage_path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(envelope.to_dict()))
	file.flush(); file.close()
	var check := FileAccess.open(stage_path, FileAccess.READ)
	var valid := check != null and check.get_length() <= MAX_BYTES and Envelope.from_dict(JSON.parse_string(check.get_as_text())) != null
	if check != null: check.close()
	if not valid: DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var had_final := FileAccess.file_exists(final_path)
	if had_final and DirAccess.rename_absolute(ProjectSettings.globalize_path(final_path), ProjectSettings.globalize_path(backup_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(stage_path), ProjectSettings.globalize_path(final_path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path))
		if had_final: DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(final_path))
		return false
	if had_final: DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return true

func _request_token() -> String:
	_request_counter += 1
	return "%s-%s-%s" % [str(Time.get_ticks_usec()), str(randi()), str(_request_counter)]
