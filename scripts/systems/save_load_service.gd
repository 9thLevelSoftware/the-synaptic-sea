extends RefCounted
class_name SaveLoadService

## REQ-012 current-run save/load service.
##
## Owned by PlayableGeneratedShip, not an autoload. Single save slot at
## `user://saves/current_run.json`. Backed by FileAccess + JSON.
##
## Per ADR-0007, this service is current-run only. No hub/meta/cross-run
## state is serialized through it. Adding fields to RunSnapshot requires
## an ADR; adding new save paths or slots is out of scope for Gate 2.

const SAVE_PATH: String = "user://saves/current_run.json"
const CURRENT_SLICE_VERSION: String = "gate2-current-run-1"
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func save_current_run(snapshot: RunSnapshot) -> bool:
	if snapshot == null:
		push_warning("SaveLoadService: cannot save null snapshot")
		return false
	var data: Dictionary = snapshot.to_dict()
	var json: String = JSON.stringify(data, "\t")
	if not _ensure_save_dir():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	return true

func load_current_run() -> RunSnapshot:
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for reading, error=%d" % FileAccess.get_open_error())
		return null
	var json: String = file.get_as_text()
	file.close()
	if json.is_empty():
		push_warning("SaveLoadService: save file is empty")
		return null
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveLoadService: save file is not valid JSON object")
		return null
	var expected_godot: String = Engine.get_version_info()["string"]
	var snapshot: RunSnapshot = RunSnapshot.from_dict(parsed as Dictionary, CURRENT_SLICE_VERSION, expected_godot)
	if snapshot == null:
		push_warning("SaveLoadService: save file rejected by from_dict (missing fields or version mismatch)")
		return null
	return snapshot

## REQ-0012 world save: serializes a whole WorldSnapshot to the single slot.
## Reuses SAVE_PATH; an old single-ship save at that path is rejected by
## WorldSnapshot.from_dict on the next load_world (version mismatch → fresh run).
func save_world(world_snapshot) -> bool:
	if world_snapshot == null:
		push_warning("SaveLoadService: cannot save null world snapshot")
		return false
	var json: String = JSON.stringify(world_snapshot.to_dict(), "\t")
	if not _ensure_save_dir():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	return true

## Reads the world save. Returns null when no save exists, the file is empty/
## not a JSON object, or the WorldSnapshot version markers do not match.
func load_world():
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for reading, error=%d" % FileAccess.get_open_error())
		return null
	var json: String = file.get_as_text()
	file.close()
	if json.is_empty():
		push_warning("SaveLoadService: save file is empty")
		return null
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveLoadService: save file is not valid JSON object")
		return null
	var expected_godot: String = Engine.get_version_info()["string"]
	var ws = WorldSnapshotScript.from_dict(parsed as Dictionary, WorldSnapshotScript.WORLD_SLICE_VERSION, expected_godot)
	if ws == null:
		push_warning("SaveLoadService: world save rejected by from_dict (missing fields or version mismatch)")
		return null
	return ws

func delete_current_run() -> bool:
	if not has_save():
		return true
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("SaveLoadService: failed to delete save file, error=%d" % err)
		return false
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Ensures the save slot's parent directory exists. `user://saves` may not exist
## on a fresh Godot install; without this, FileAccess.open silently returns null
## and the save fails without a useful error. Shared by save_current_run and
## save_world. Returns false only when directory creation genuinely fails.
func _ensure_save_dir() -> bool:
	var dir_path: String = SAVE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var make_err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if make_err != OK and make_err != ERR_ALREADY_EXISTS:
			push_warning("SaveLoadService: failed to create save dir, error=%d" % make_err)
			return false
	return true
