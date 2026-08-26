extends RefCounted
class_name PortableSettingsStore

const SettingsState := preload("res://scripts/systems/settings_state.gd")
const Schema := preload("res://scripts/schemas/settings_state_schema.gd")
const FILE_PATH := "user://portable-settings/settings-state-1.json"
const DIRECTORY := "user://portable-settings"
const MAX_BYTES := 65536
var failpoint: String = ""

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
	if state == null or not _valid_payload(state.get_payload()): return false
	var dir := DirAccess.open("user://")
	if dir == null or dir.make_dir_recursive("portable-settings") != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://portable-settings")): return false
	var path := FILE_PATH + ".stage." + str(Time.get_ticks_usec()) + "." + str(randi())
	var backup_path := FILE_PATH + ".backup." + str(Time.get_ticks_usec()) + "." + str(randi())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	var document := JSON.stringify({"schema_version":"portable-settings-1", "settings":state.get_payload()})
	if document.to_utf8_buffer().size() > MAX_BYTES or _failed("stage_write"): f.close(); DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return false
	f.store_string(document); f.flush(); f.close()
	var check := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(check.get_as_text()) if check != null and check.get_length() <= MAX_BYTES else null
	if check != null: check.close()
	if typeof(parsed) != TYPE_DICTIONARY or parsed.size() != 2 or parsed.get("schema_version") != "portable-settings-1" or not _valid_payload(parsed.get("settings")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return false
	var had_final := FileAccess.file_exists(FILE_PATH)
	if had_final and (_failed("backup") or DirAccess.rename_absolute(ProjectSettings.globalize_path(FILE_PATH), ProjectSettings.globalize_path(backup_path)) != OK): DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return false
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(FILE_PATH)) if not _failed("promote") else ERR_CANT_CREATE
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); if had_final and not _failed("restore"): DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(FILE_PATH)); return false
	if had_final: DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return true

func load() -> SettingsState:
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null: return null
	if f.get_length() > MAX_BYTES: f.close(); return null
	var document: Variant = JSON.parse_string(f.get_as_text()); f.close()
	if typeof(document) != TYPE_DICTIONARY or document.size() != 2 or document.get("schema_version") != "portable-settings-1": return null
	var payload: Variant = document.get("settings")
	if typeof(payload) != TYPE_DICTIONARY or not _valid_payload(payload): return null
	var result := SettingsState.new()
	return result if result.configure(payload) else null

func _valid_payload(payload: Variant) -> bool:
	if typeof(payload) != TYPE_DICTIONARY or not _closed_payload(payload): return false
	if str(payload.get("schema", "")) != Schema.SCHEMA_VERSION: return false
	if typeof(payload.get("text_scale")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(payload.text_scale)) or float(payload.text_scale) < Schema.MIN_TEXT_SCALE or float(payload.text_scale) > Schema.MAX_TEXT_SCALE: return false
	if typeof(payload.colorblind_mode) != TYPE_STRING or not Schema.COLORBLIND_MODES.has(payload.colorblind_mode): return false
	if typeof(payload.difficulty) != TYPE_STRING or not Schema.DIFFICULTIES.has(payload.difficulty): return false
	if typeof(payload.glyph_scheme) != TYPE_STRING or not Schema.GLYPH_SCHEMES.has(payload.glyph_scheme): return false
	if typeof(payload.preset_id) != TYPE_STRING or payload.preset_id.is_empty() or payload.preset_id.length() > 128: return false
	for key in ["motion_reduce", "captions", "hold_to_tap"]:
		if typeof(payload[key]) != TYPE_BOOL: return false
	return true

func _failed(stage: String) -> bool:
	return failpoint == stage
