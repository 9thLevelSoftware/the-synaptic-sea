extends RefCounted
class_name PortableSettingsStore

const SettingsState := preload("res://scripts/systems/settings_state.gd")
const Schema := preload("res://scripts/schemas/settings_state_schema.gd")
const FILE_PATH := "user://portable-settings/settings-state-1.json"

func _closed_payload(payload: Variant) -> bool:
	if typeof(payload) != TYPE_DICTIONARY: return false
	var expected := Schema.default_payload().keys()
	var actual: Array = payload.keys()
	for key in expected:
		if not payload.has(key): return false
	for key in actual:
		if not expected.has(key): return false
	return true

func save(state: SettingsState) -> bool:
	if state == null or not _closed_payload(state.get_payload()) or not Schema.validate(state.get_payload()): return false
	var dir := DirAccess.open("user://")
	if dir == null or dir.make_dir_recursive("portable-settings") != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://portable-settings")): return false
	var path := FILE_PATH + ".staging." + str(Time.get_ticks_usec()) + "." + str(randi())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(state.get_payload())); f.flush(); f.close()
	var check := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(check.get_as_text()) if check != null else null
	if check != null: check.close()
	if not Schema.validate(parsed): DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(FILE_PATH)) == OK

func load() -> SettingsState:
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null: return null
	var payload := JSON.parse_string(f.get_as_text()); f.close()
	if typeof(payload) != TYPE_DICTIONARY or not _closed_payload(payload) or not Schema.validate(payload): return null
	var result := SettingsState.new()
	return result if result.configure(payload) else null
