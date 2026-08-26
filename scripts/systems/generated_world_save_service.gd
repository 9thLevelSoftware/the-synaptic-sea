extends RefCounted
class_name GeneratedWorldSaveService

const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const Compatibility := preload("res://scripts/systems/generated_world_compatibility.gd")

const DIRECTORY := "user://generated-world-save-1"
const FILE_NAME := "generated-world.save.json"

func path_for(slot_id := "world") -> String:
	return DIRECTORY.path_join(str(slot_id) + "." + FILE_NAME)

func load_and_validate(slot_id: String, compatibility: RefCounted):
	var path := path_for(slot_id)
	if not FileAccess.file_exists(path):
		return Result.make(Result.IO_FAILURE, "missing_file", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return Result.make(Result.IO_FAILURE, "open_failed", path)
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
	var stage_path := final_path + ".staging." + str(Time.get_ticks_usec()) + "." + str(randi())
	var file := FileAccess.open(stage_path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(envelope.to_dict())); file.flush(); file.close()
	var check := FileAccess.open(stage_path, FileAccess.READ)
	var valid := check != null and Envelope.from_dict(JSON.parse_string(check.get_as_text())) != null
	if check != null: check.close()
	if not valid: DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(stage_path), ProjectSettings.globalize_path(final_path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stage_path)); return false
	return true
