extends SceneTree
const Store := preload("res://scripts/systems/portable_settings_store.gd")
const State := preload("res://scripts/systems/settings_state.gd")
var cases := 0
var failures: Array[String] = []
var test_root := "user://task8-tests/settings-" + str(Time.get_ticks_usec())

func _init() -> void:
	var store := Store.new(); store.storage_path = test_root + "/settings.json"; var state := State.new()
	for field in ["schema", "text_scale", "colorblind_mode", "motion_reduce", "captions", "hold_to_tap", "difficulty", "glyph_scheme", "preset_id"]: _expect(state.get_payload().has(field), "field " + field)
	_expect(store.save(state), "save"); _expect(store.load() != null, "load"); _expect(store.save(state), "consecutive")
	store.token_queue = ["bad", "A".repeat(32), "d".repeat(32)]; _expect(store.save(state), "token invalid then unique")
	var path := store.storage_path; var original := FileAccess.get_file_as_string(path)
	for point in ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "backup_rename", "promote_rename", "final_verify", "final_verify,restore_rename", "final_verify,restore_copy", "cleanup"]:
		store.failpoint = point; var before := FileAccess.get_file_as_string(path); _expect(not store.save(state), "failpoint " + point); _expect(FileAccess.get_file_as_string(path) == before, "preserve " + point); store.failpoint = ""
	_expect(FileAccess.get_file_as_string(path) == original, "final bytes")
	_finish()

func _expect(value: bool, label: String) -> void:
	cases += 1; if not value: failures.append(label)

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root)); if failures.is_empty(): print("TASK8 PORTABLE SETTINGS STORE PASS cases=%d" % cases); quit(0)
	else: push_error("TASK8 PORTABLE SETTINGS STORE FAIL %s" % ",".join(failures)); quit(1)
