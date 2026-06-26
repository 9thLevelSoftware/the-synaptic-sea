extends RefCounted
class_name PermadeathResolver

## Permadeath / epitaph flow (ADR-0032).
##
## Pure model + file I/O for the per-slot death record. The resolver
## never reaches into the scene tree; the coordinator drives it on the
## player-death signal and reads the result via `has_died_in(slot_id)`
## / `load_epitaph(slot_id)`.

const DEATH_KIND_SUFFIX: String = ".death.json"

func death_path_for(slot_id: String) -> String:
	# Slots live under user://saves/<slot_id>.json; the death record is
	# <slot_id>.death.json in the same directory. We do not embed the
	# death record into the slot file because the slot's payload is the
	# RunSnapshot schema; mixing them would break the migration chain.
	return "user://saves/%s%s" % [slot_id, DEATH_KIND_SUFFIX]

func has_died_in(slot_id: String) -> bool:
	return FileAccess.file_exists(death_path_for(slot_id))

func load_epitaph(slot_id: String) -> Dictionary:
	var path: String = death_path_for(slot_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func record_death(slot_id: String, cause: String, epitaph: String, run_time_seconds: float, final_objective_sequence: int) -> Dictionary:
	var record: Dictionary = {
		"slot_id": slot_id,
		"cause": cause,
		"epitaph": epitaph,
		"died_at": Time.get_datetime_string_from_system(true),
		"died_at_epoch": int(Time.get_unix_time_from_system()),
		"run_time_seconds": run_time_seconds,
		"final_objective_sequence": final_objective_sequence,
		"schema_version": "death-1",
	}
	var dir_path: String = "user://saves"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if mk_err != OK and mk_err != ERR_ALREADY_EXISTS:
			push_warning("PermadeathResolver: failed to create saves dir, error=%d" % mk_err)
			return {}
	var file := FileAccess.open(death_path_for(slot_id), FileAccess.WRITE)
	if file == null:
		push_warning("PermadeathResolver: cannot open death file for writing, error=%d" % FileAccess.get_open_error())
		return {}
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return record

func clear_death(slot_id: String) -> bool:
	if not has_died_in(slot_id):
		return true
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(death_path_for(slot_id)))
	return err == OK