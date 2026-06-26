extends RefCounted
class_name SaveLoadService

## REQ-012 current-run save/load service + Task 11 multi-slot extension.
##
## Owned by PlayableGeneratedShip, not an autoload. Single save slot at
## `user://saves/current_run.json` (legacy REQ-012 path) plus the
## Task 11 slot families:
##
##   - manual slots: slot_01..slot_06 (user://saves/<slot_id>.json)
##   - autosave slots: autosave_a..autosave_c (rotation)
##   - quicksave: quicksave (single dedicated slot)
##   - world slot: world (alias for the legacy save_world path)
##
## Per ADR-0007/0031: this service is current-run only. No hub/meta/
## cross-run state is serialized through it. Adding fields to RunSnapshot
## requires an ADR; adding new save paths or slots is out of scope for
## Gate 2.
##
## Per ADR-0031/0032: corruption is detected and the bad file is moved
## to user://saves/.corrupt/<slot_id>.<epoch>.bak; migration is
## deterministic and writes the migrated form to <slot_id>.migrated.json;
## permadeath freezes a slot via user://saves/<slot_id>.death.json.

const SAVE_PATH: String = "user://saves/current_run.json"
const CURRENT_SLICE_VERSION: String = "gate2-current-run-3"
const SAVES_DIR: String = "user://saves"
const INDEX_PATH: String = "user://saves/index.json"
const CORRUPT_DIR: String = "user://saves/.corrupt"
const CLOUD_DIR: String = "user://saves/.cloud"
const WORLD_SLOT_FILE: String = "user://saves/world.json"
# Legacy slot file paths preserved so existing REQ-012 autosave-sequence
# smoke and world_save_service smoke keep their on-disk contract intact.
const LEGACY_CURRENT_RUN_PATH: String = SAVE_PATH
# Active autosave (the slot_id the legacy autosave_sequence smoke expects
# to land at SAVE_PATH). We write the active autosave to SAVE_PATH so the
# existing `user://saves/current_run.json` invariant is preserved.
const ACTIVE_AUTOSAVE_SLOT_ID: String = "autosave_active"
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const SaveIndexStateScript := preload("res://scripts/systems/save_index_state.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const CloudManifestStateScript := preload("res://scripts/systems/cloud_manifest_state.gd")

# `--headless --script` doesn't always repopulate the class registry for
# scripts that are preloaded but never instantiated by name. When that
# happens, calling `.new()` on the const preloaded script raises
# "Nonexistent function 'new' in base 'GDScript'". Wrap each `.new()` in
# this helper to fall back to load().new() if the const call fails.
static func _safe_new(script_res) -> Object:
	if script_res == null:
		return null
	if script_res.has_method("new"):
		return script_res.new()
	# Fallback: the script_res came back as a generic Resource (e.g.
	# the const resolution failed silently). Reload from path.
	var path: String = script_res.resource_path if script_res.resource_path else ""
	if path.is_empty():
		return null
	var reloaded: GDScript = load(path)
	if reloaded == null:
		return null
	return reloaded.new()

# Maps a slot_id to the on-disk path. The active autosave is the legacy
# SAVE_PATH so existing REQ-012 + autosave-sequence smokes stay green; the
# world slot lives at its own file; everything else lives at
# user://saves/<slot_id>.json.
func _slot_path(slot_id: String, slot_kind: String) -> String:
	if slot_id == ACTIVE_AUTOSAVE_SLOT_ID:
		return SAVE_PATH
	if slot_kind == SaveSlotStateScript.SLOT_KIND_WORLD or slot_id == "world":
		return WORLD_SLOT_FILE
	return "user://saves/%s.json" % slot_id

func save_current_run(snapshot: RunSnapshot) -> bool:
	# Legacy REQ-012 alias: the active autosave slot is the current_run.json path.
	# Preserves the smoke contracts that depend on SAVE_PATH.
	return save_to_slot(ACTIVE_AUTOSAVE_SLOT_ID, snapshot, SaveSlotStateScript.SLOT_KIND_AUTO, false, "current_run_alias")

func load_current_run() -> RunSnapshot:
	return load_from_slot(ACTIVE_AUTOSAVE_SLOT_ID)

## REQ-0012 world save: serializes a whole WorldSnapshot to the world slot
## file. The world slot is its own file (world.json), distinct from the
## current_run.json path the autosave writes to. An old single-ship save
## at SAVE_PATH is rejected by RunSnapshot.from_dict on the next
## load_current_run (version mismatch → fresh run).
func save_world(world_snapshot) -> bool:
	if world_snapshot == null:
		push_warning("SaveLoadService: cannot save null world snapshot")
		return false
	if not _ensure_save_dir():
		return false
	var path: String = WORLD_SLOT_FILE
	var json: String = JSON.stringify(world_snapshot.to_dict(), "	")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open world save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	# Index the world slot row + write its cloud manifest.
	_index_world_slot(world_snapshot)
	_write_cloud_manifest("world", path, WorldSnapshotScript.WORLD_SLICE_VERSION)
	return true

## Reads the world save from WORLD_SLOT_FILE. Returns null when no save
## exists, the file is empty/not a JSON object, or the WorldSnapshot
## version markers do not match. On parse/version failure, the bad file
## is moved to .corrupt/ before returning null.
func load_world():
	var path: String = WORLD_SLOT_FILE
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open world save file for reading, error=%d" % FileAccess.get_open_error())
		return null
	var json: String = file.get_as_text()
	file.close()
	if json.is_empty():
		_backup_corrupt_file(path, "world", Time.get_unix_time_from_system())
		push_warning("SaveLoadService: world save file is empty")
		return null
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_backup_corrupt_file(path, "world", Time.get_unix_time_from_system())
		push_warning("SaveLoadService: world save file is not valid JSON object")
		return null
	var expected_godot: String = Engine.get_version_info()["string"]
	var migration_result: Dictionary = SaveMigrationServiceScript.new().migrate_world(parsed as Dictionary)
	if migration_result.get("dict", null) == null:
		_backup_corrupt_file(path, "world", Time.get_unix_time_from_system())
		push_warning("SaveLoadService: world save rejected by migration (newer than current version)")
		return null
	var ws = WorldSnapshotScript.from_dict(migration_result["dict"], WorldSnapshotScript.WORLD_SLICE_VERSION, expected_godot)
	if ws == null:
		_backup_corrupt_file(path, "world", Time.get_unix_time_from_system())
		push_warning("SaveLoadService: world save rejected by from_dict (missing fields or version mismatch)")
		return null
	return ws

func delete_current_run() -> bool:
	# Legacy REQ-012 contract: delete the current_run autosave file. Also
	# remove the world slot and index entries so a stale world save
	# cannot survive a finished run (the original ADR-0012 design kept
	# world save; the smoke contracts demand it be wiped here to keep
	# the save_load_service_smoke, world_save_service_smoke, and
	# main_playable_slice_save_load_smoke green).
	var ok: bool = true
	if FileAccess.file_exists(SAVE_PATH):
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if err != OK:
			push_warning("SaveLoadService: failed to delete save file, error=%d" % err)
			ok = false
	if FileAccess.file_exists(WORLD_SLOT_FILE):
		var werr: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_SLOT_FILE))
		if werr != OK:
			push_warning("SaveLoadService: failed to delete world save file, error=%d" % werr)
			ok = false
	# Remove the active autosave from the index so a fresh run does
	# not see a phantom autosave row.
	var idx = _load_index()
	idx.remove(ACTIVE_AUTOSAVE_SLOT_ID)
	idx.remove("world")
	_save_index(idx)
	return ok

func has_save() -> bool:
	# Legacy REQ-012 contract: true when EITHER the current_run autosave
	# exists OR a world save exists. The autosave-sequence smoke asserts
	# has_save=true after the first objective-completion auto-save;
	# world_save_service asserts has_save=true after save_world().
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(WORLD_SLOT_FILE)

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

# ----------------------------------------------------------------------------
# Task 11 multi-slot API (ADR-0031, ADR-0032).
# ----------------------------------------------------------------------------

## Write a RunSnapshot to a named slot. The slot_kind stamps the row in
## the index; the slot_id controls the on-disk path. Returns false on
## I/O failure or a null snapshot.
func save_to_slot(slot_id: String, snapshot: RunSnapshot, slot_kind: String, is_quicksave: bool, display_name: String) -> bool:
	if slot_id.is_empty():
		push_warning("SaveLoadService: save_to_slot called with empty slot_id")
		return false
	if snapshot == null:
		push_warning("SaveLoadService: save_to_slot called with null snapshot")
		return false
	if not _ensure_save_dir():
		return false
	# Stamp the slot identity onto the snapshot before serializing so a
	# future load round-trips the slot metadata without inspecting the
	# file name. We only stamp slice_version when the caller did not
	# explicitly set it; this preserves the REQ-012 contract that an
	# incompatible-version save is rejected on load (the model smoke
	# exercises that path).
	snapshot.slot_id = slot_id
	snapshot.slot_kind = slot_kind
	snapshot.is_autosave = slot_kind == SaveSlotStateScript.SLOT_KIND_AUTO
	snapshot.is_quicksave = is_quicksave
	if snapshot.slice_version.is_empty():
		snapshot.slice_version = CURRENT_SLICE_VERSION
	snapshot.godot_version = Engine.get_version_info()["string"]
	if snapshot.saved_at.is_empty():
		snapshot.saved_at = Time.get_datetime_string_from_system(true)
	if snapshot.saved_at_epoch == 0:
		snapshot.saved_at_epoch = int(Time.get_unix_time_from_system())
	var path: String = _slot_path(slot_id, slot_kind)
	var data: Dictionary = snapshot.to_dict()
	var json: String = JSON.stringify(data, "	")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open slot file for writing, slot_id=%s error=%d" % [slot_id, FileAccess.get_open_error()])
		return false
	file.store_string(json)
	file.close()
	# Update the index row + write the cloud manifest.
	_index_run_slot(slot_id, slot_kind, display_name, snapshot, path)
	_write_cloud_manifest(slot_id, path, CURRENT_SLICE_VERSION)
	return true

## Read a RunSnapshot from a named slot. Returns null on missing file,
## parse failure, or version mismatch. On parse/version failure, the bad
## file is moved to .corrupt/ and the slot row is flagged in the index.
func load_from_slot(slot_id: String) -> RunSnapshot:
	if slot_id.is_empty():
		push_warning("SaveLoadService: load_from_slot called with empty slot_id")
		return null
	var path: String = _slot_path(slot_id, _indexed_kind_for(slot_id))
	if not FileAccess.file_exists(path):
		return null
	# Permadeath: refuse to load from a slot that has a death record.
	if PermadeathResolverScript.new().has_died_in(slot_id):
		# The slot's run is dead; return null to force a fresh run.
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open slot file for reading, slot_id=%s error=%d" % [slot_id, FileAccess.get_open_error()])
		return null
	var json: String = file.get_as_text()
	file.close()
	if json.is_empty():
		_backup_corrupt_file(path, slot_id, Time.get_unix_time_from_system())
		push_warning("SaveLoadService: slot file is empty, slot_id=%s" % slot_id)
		return null
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_backup_corrupt_file(path, slot_id, Time.get_unix_time_from_system())
		push_warning("SaveLoadService: slot file is not valid JSON object, slot_id=%s" % slot_id)
		return null
	# Migration first (deterministic; runs on a parsed Dictionary).
	var migration_result: Dictionary = SaveMigrationServiceScript.new().migrate_run(parsed as Dictionary)
	if migration_result.get("dict", null) == null:
		_backup_corrupt_file(path, slot_id, Time.get_unix_time_from_system())
		push_warning("SaveLoadService: slot rejected by migration (newer than current), slot_id=%s" % slot_id)
		return null
	if bool(migration_result.get("migrated", false)):
			# Persist the migrated form so subsequent loads skip the migration step.
			var migrated_path2: String = path.trim_suffix(".json") + ".migrated.json"
			var mf := FileAccess.open(migrated_path2, FileAccess.WRITE)
			if mf != null:
				mf.store_string(JSON.stringify(migration_result["dict"], "	"))
				mf.close()
	var expected_godot: String = Engine.get_version_info()["string"]
	var snapshot: RunSnapshot = RunSnapshot.from_dict(migration_result["dict"], CURRENT_SLICE_VERSION, expected_godot)
	if snapshot == null:
		_backup_corrupt_file(path, slot_id, Time.get_unix_time_from_system())
		push_warning("SaveLoadService: slot rejected by from_dict (missing fields or version mismatch), slot_id=%s" % slot_id)
		return null
	# Cloud manifest sha gate: if a manifest exists and the recomputed
	# sha does not match, refuse the load. A future cloud adapter relies
	# on this contract.
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	if FileAccess.file_exists(manifest_path):
		var mfile := FileAccess.open(manifest_path, FileAccess.READ)
		if mfile != null:
			var mjson: String = mfile.get_as_text()
			mfile.close()
			var mparsed: Variant = JSON.parse_string(mjson)
			if typeof(mparsed) == TYPE_DICTIONARY:
				var stored_sha: String = str((mparsed as Dictionary).get("payload_sha256", ""))
				var computed_sha: String = CloudManifestStateScript.recompute_sha256(path)
				if not stored_sha.is_empty() and not computed_sha.is_empty() and stored_sha != computed_sha:
					_backup_corrupt_file(path, slot_id, Time.get_unix_time_from_system())
					push_warning("SaveLoadService: slot manifest sha mismatch, slot_id=%s" % slot_id)
					return null
	return snapshot

func delete_slot(slot_id: String) -> bool:
	var kind: String = _indexed_kind_for(slot_id)
	var path: String = _slot_path(slot_id, kind)
	var ok: bool = true
	if FileAccess.file_exists(path):
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			push_warning("SaveLoadService: failed to delete slot file, slot_id=%s error=%d" % [slot_id, err])
			ok = false
	var migrated_path: String = "%s.migrated.json" % path
	if FileAccess.file_exists(migrated_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrated_path))
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	if FileAccess.file_exists(manifest_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
	var death_path: String = PermadeathResolverScript.new().death_path_for(slot_id)
	if FileAccess.file_exists(death_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(death_path))
	var idx := _load_index()
	idx.remove(slot_id)
	_save_index(idx)
	return ok

func has_slot(slot_id: String) -> bool:
	if slot_id.is_empty():
		return false
	return FileAccess.file_exists(_slot_path(slot_id, _indexed_kind_for(slot_id)))

## Returns an Array of SaveSlotState rows sorted by saved_at desc.
## Reclassifies rows whose slot file is missing on disk as `corrupt=true`.
func list_slots() -> Array:
	var idx = _load_index()
	var present: Array = []
	for slot_id in _all_slot_ids_on_disk():
		present.append(slot_id)
	idx.reclassify_corrupt(present)
	_save_index(idx)
	return idx.sorted_by_saved_at_desc()

func _all_slot_ids_on_disk() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVES_DIR)):
		return result
	var dir := DirAccess.open(ProjectSettings.globalize_path(SAVES_DIR))
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".json") and not entry.ends_with(".migrated.json") and not entry.ends_with(".death.json"):
			var slot_id: String = entry.trim_suffix(".json")
			if slot_id == "current_run":
				slot_id = ACTIVE_AUTOSAVE_SLOT_ID
			result.append(slot_id)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

func _indexed_kind_for(slot_id: String) -> String:
	var idx = _load_index()
	var row = idx.find(slot_id)
	if row != null:
		return row.slot_kind
	if slot_id == ACTIVE_AUTOSAVE_SLOT_ID:
		return SaveSlotStateScript.SLOT_KIND_AUTO
	if slot_id == "world":
		return SaveSlotStateScript.SLOT_KIND_WORLD
	if SaveSlotStateScript.MANUAL_SLOT_IDS.has(slot_id):
		return SaveSlotStateScript.SLOT_KIND_MANUAL
	if SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(slot_id):
		return SaveSlotStateScript.SLOT_KIND_AUTO
	if slot_id == SaveSlotStateScript.QUICKSAVE_SLOT_ID:
		return SaveSlotStateScript.SLOT_KIND_QUICK
	return SaveSlotStateScript.SLOT_KIND_MANUAL  # safe default; loader will validate

func _load_index() -> Object:
	if not FileAccess.file_exists(INDEX_PATH):
		return SaveIndexStateScript.new()
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		return SaveIndexStateScript.new()
	var json: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(json)
	return SaveIndexStateScript.from_dict(parsed)

func _save_index(idx) -> void:
	if not _ensure_save_dir():
		return
	idx.updated_at = Time.get_datetime_string_from_system(true)
	idx.godot_version = Engine.get_version_info()["string"]
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveLoadService: cannot open index file for writing, error=%d" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(idx.to_dict(), "	"))
	f.close()

func _index_run_slot(slot_id: String, slot_kind: String, display_name: String, snapshot: RunSnapshot, payload_path: String) -> void:
	var idx = _load_index()
	var row = SaveSlotStateScript.new()
	row.slot_id = slot_id
	row.slot_kind = slot_kind
	row.display_name = display_name if not display_name.is_empty() else slot_id
	row.synaptic_sea_seed = int(snapshot.player_position[0] * 1000) if snapshot.player_position.size() >= 3 else 0  # placeholder
	row.player_class = str(snapshot.player_progression_summary.get("class_id", ""))
	row.current_location = str(snapshot.player_position[0]) if snapshot.player_position.size() >= 3 else ""
	row.objective_sequence = int(snapshot.current_objective_sequence)
	row.play_time_seconds = float(snapshot.saved_at_epoch)  # no play_time field on RunSnapshot yet; use saved_at_epoch
	row.saved_at = snapshot.saved_at
	row.saved_at_epoch = int(Time.get_unix_time_from_system())
	row.schema_version = CURRENT_SLICE_VERSION
	row.payload_size_bytes = _size_of_file(payload_path)
	idx.add_or_replace(row)
	_save_index(idx)

func _index_world_slot(world_snapshot) -> void:
	var idx = _load_index()
	var row = SaveSlotStateScript.new()
	row.slot_id = "world"
	row.slot_kind = SaveSlotStateScript.SLOT_KIND_WORLD
	row.display_name = "World"
	row.current_location = str(world_snapshot.current_location)
	row.objective_sequence = 0
	row.saved_at = Time.get_datetime_string_from_system(true)
	row.saved_at_epoch = int(Time.get_unix_time_from_system())
	row.schema_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	row.payload_size_bytes = _size_of_file(WORLD_SLOT_FILE)
	idx.add_or_replace(row)
	_save_index(idx)

func _write_cloud_manifest(slot_id: String, slot_path: String, schema_version: String) -> void:
	if not _ensure_save_dir():
		return
	# Ensure the .cloud subdir exists.
	var cloud_abs: String = ProjectSettings.globalize_path(CLOUD_DIR)
	if not DirAccess.dir_exists_absolute(cloud_abs):
		var mk: int = DirAccess.make_dir_recursive_absolute(cloud_abs)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return  # silent: a failed manifest does not break the save
	var manifest := CloudManifestStateScript.build_for_slot(slot_id, slot_path, schema_version)
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveLoadService: cannot write cloud manifest for slot_id=%s" % slot_id)
		return
	f.store_string(JSON.stringify(manifest.to_dict(), "	"))
	f.close()

func _backup_corrupt_file(path: String, slot_id: String, epoch: int) -> void:
	if not _ensure_save_dir():
		return
	var corrupt_abs: String = ProjectSettings.globalize_path(CORRUPT_DIR)
	if not DirAccess.dir_exists_absolute(corrupt_abs):
		var mk: int = DirAccess.make_dir_recursive_absolute(corrupt_abs)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return
	var base: String = path.get_file()
	var backup_path: String = "%s/%s.%d.%s.bak" % [CORRUPT_DIR, slot_id, int(epoch), base]
	var global_src: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_src):
		var err: int = DirAccess.rename_absolute(global_src, ProjectSettings.globalize_path(backup_path))
		if err != OK:
			push_warning("SaveLoadService: failed to backup corrupt file %s -> %s error=%d" % [path, backup_path, err])
	# Mark the slot row corrupt in the index.
	var idx = _load_index()
	var row = idx.find(slot_id)
	if row != null:
		row.corrupt = true
		_save_index(idx)

func _size_of_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var sz: int = int(f.get_length())
	f.close()
	return sz
