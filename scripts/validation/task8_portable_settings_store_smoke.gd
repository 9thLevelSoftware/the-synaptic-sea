extends SceneTree

const Store := preload("res://scripts/systems/portable_settings_store.gd")
const State := preload("res://scripts/systems/settings_state.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const TOKENS := "0123456789abcdef"

var cases := 0
var failures: Array[String] = []
var test_root := "user://task8-tests/settings-" + str(Time.get_ticks_usec())

func _init() -> void:
	for unsafe_path in ["", "C:/unsafe.json", "user://", "user://../escape.json", "user://safe/../escape.json", "user://bad\\path.json", "user://bad:path.json"]:
		var unsafe := Store.new(); unsafe.storage_path = unsafe_path
		_expect(not unsafe.save(State.new()) and unsafe.load() == null, "unsafe configured path " + unsafe_path)

	var store := Store.new(); store.storage_path = test_root + "/settings.json"
	var state := State.new(); state.set_text_scale(1.5); state.set_captions_enabled(false); state.set_motion_reduce(true)
	for field in ["schema", "text_scale", "colorblind_mode", "motion_reduce", "captions", "hold_to_tap", "difficulty", "glyph_scheme", "preset_id"]:
		_expect(state.get_payload().has(field), "portable field " + field)
	_expect(store.save(state), "portable save")
	var loaded: Variant = store.load()
	_expect(loaded != null and loaded.get_payload() == state.get_payload(), "portable exact round trip")
	var original := FileAccess.get_file_as_string(store.storage_path)
	var outer: Variant = JSON.parse_string(original)
	_expect(typeof(outer) == TYPE_DICTIONARY and outer.size() == 2 and outer.has_all(["schema_version", "settings"]), "exact two-key outer document")
	_expect(outer.schema_version == "portable-settings-1" and outer.settings.size() == 9, "exact portable schemas")
	_expect(store.save(state) and FileAccess.get_file_as_string(store.storage_path) == original, "consecutive stable save")

	for index in 7:
		var point: String = ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "promote_rename", "final_verify"][index]
		var first := Store.new(); first.storage_path = test_root + "/first%d.json" % index
		var token := TOKENS.substr(index, 1).repeat(32); var stage := first.storage_path + ".stage." + token; var backup := first.storage_path + ".backup." + token
		first.failpoint = point; first.token_queue = [token]
		_expect(not first.save(state), "first settings fail " + point)
		_expect(not FileAccess.file_exists(first.storage_path), "first settings no final " + point)
		_expect(not FileAccess.file_exists(stage) and not FileAccess.file_exists(backup), "first settings no sidecar " + point)
		_expect(int(first.failpoint_hits.get(point, 0)) > 0, "first settings hit " + point)

	var collision_a := "a".repeat(32); var collision_b := "b".repeat(32); var collision_stage := store.storage_path + ".stage." + collision_a
	_write(collision_stage, "collision-sentinel")
	store.token_queue = [collision_a, collision_b]
	_expect(store.save(state), "settings collision advances")
	_expect(store.token_queue.is_empty() and FileAccess.get_file_as_string(collision_stage) == "collision-sentinel", "settings collision path isolated")
	_remove(collision_stage)
	var rejected := Store.new(); rejected.storage_path = test_root + "/badtoken.json"
	for _i in 32: rejected.token_queue.append("z".repeat(32))
	_expect(not rejected.save(state), "settings nonhex tokens exhaust")
	_expect(rejected.token_queue.is_empty() and not FileAccess.file_exists(rejected.storage_path), "settings nonhex creates nothing")

	var preserving_points := ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "backup_rename", "promote_rename", "final_verify", "final_verify,restore_rename", "cleanup"]
	for index in preserving_points.size():
		var point: String = preserving_points[index]
		var token := TOKENS.substr((index + 1) % TOKENS.length(), 1).repeat(32)
		var stage := store.storage_path + ".stage." + token; var backup := store.storage_path + ".backup." + token
		store.failpoint = point; store.failpoint_hits.clear(); store.token_queue = [token]
		_expect(not store.save(state), "existing settings fail " + point)
		_expect(FileAccess.file_exists(store.storage_path) and FileAccess.get_file_as_string(store.storage_path) == original, "existing settings preserved " + point)
		_expect(not FileAccess.file_exists(stage) and not FileAccess.file_exists(backup), "settings sidecars cleaned " + point)
		for name in point.split(","): _expect(int(store.failpoint_hits.get(name, 0)) > 0, "settings hit " + name)
	store.failpoint = ""; store.token_queue.clear()

	var failed_token := "f".repeat(32); var failed_backup := store.storage_path + ".backup." + failed_token
	store.failpoint = "final_verify,restore_rename,restore_copy"; store.failpoint_hits.clear(); store.token_queue = [failed_token]
	_expect(not store.save(state), "settings both restore paths fail")
	_expect(not FileAccess.file_exists(store.storage_path), "settings failed restore hides new final")
	_expect(FileAccess.file_exists(failed_backup) and FileAccess.get_file_as_string(failed_backup) == original, "settings failed restore preserves backup")
	_expect(int(store.failpoint_hits.get("restore_rename", 0)) > 0 and int(store.failpoint_hits.get("restore_copy", 0)) > 0, "settings both restore branches hit")
	_expect(DirAccess.rename_absolute(ProjectSettings.globalize_path(failed_backup), ProjectSettings.globalize_path(store.storage_path)) == OK, "test restores settings backup")
	store.failpoint = ""

	var invalid_documents: Array = [null, [], {}, {"schema_version":"portable-settings-1"}, {"settings":state.get_payload()}, {"schema_version":"portable-settings-2", "settings":state.get_payload()}, {"schema_version":"portable-settings-1", "settings":state.get_payload(), "extra":true}]
	for index in invalid_documents.size():
		_write(store.storage_path, JSON.stringify(invalid_documents[index]))
		_expect(store.load() == null, "outer document rejected %d" % index)

	var payload := state.get_payload()
	for key in payload.keys():
		var missing: Dictionary = payload.duplicate(true); missing.erase(key); _write_document(store, missing)
		_expect(store.load() == null, "missing settings field " + key)
	var wrong_values := {"schema":1, "text_scale":"1.5", "colorblind_mode":1, "motion_reduce":1, "captions":1, "hold_to_tap":1, "difficulty":1, "glyph_scheme":1, "preset_id":1}
	for key in wrong_values:
		var wrong: Dictionary = payload.duplicate(true); wrong[key] = wrong_values[key]; _write_document(store, wrong)
		_expect(store.load() == null, "wrong settings type " + key)
	var extra: Dictionary = payload.duplicate(true); extra.extra = true; _write_document(store, extra)
	_expect(store.load() == null, "extra settings field rejected")
	for forbidden in ["world_seed", "site_ir", "gameplay_ir", "mutation_delta"]:
		var forbidden_payload: Dictionary = payload.duplicate(true); forbidden_payload[forbidden] = 1; _write_document(store, forbidden_payload)
		_expect(store.load() == null, "forbidden portable field " + forbidden)

	for scale in [NAN, INF, -INF, 0.99, 2.01]:
		var invalid_scale: Dictionary = payload.duplicate(true); invalid_scale.text_scale = scale
		_expect(not store._valid_payload(invalid_scale), "finite bounded text scale " + str(scale))
	var long_preset: Dictionary = payload.duplicate(true); long_preset.preset_id = "p".repeat(129)
	_expect(not store._valid_payload(long_preset), "preset id byte bound")
	_write(store.storage_path, "x".repeat(Store.MAX_BYTES + 1))
	_expect(store.load() == null and FileAccess.get_file_as_string(store.storage_path).length() == Store.MAX_BYTES + 1, "oversized portable document preserved")

	_write(store.storage_path, original)
	var world_result: Variant = Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", "user://generated-world-save-1/world.generated-world.save.json")
	_expect(world_result.status == Result.NEW_WORLD_REQUIRED and store.load() != null, "portable settings survive world incompatibility")
	_expect(FileAccess.get_file_as_string(store.storage_path) == original, "world mismatch cannot rewrite portable settings")

	_finish()

func _write_document(store: RefCounted, payload: Dictionary) -> void:
	_write(store.storage_path, JSON.stringify({"schema_version":"portable-settings-1", "settings":payload}))

func _write(path: String, text: String) -> void:
	var directory := path.get_base_dir()
	var root := DirAccess.open("user://")
	root.make_dir_recursive(directory.trim_prefix("user://"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text); file.flush(); file.close()

func _remove(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _expect(value: bool, label: String) -> void:
	cases += 1
	if not value: failures.append("%d:%s" % [cases, label])

func _finish() -> void:
	var directory := DirAccess.open(test_root)
	if directory != null:
		for file in directory.get_files(): _remove(test_root.path_join(file))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root))
	if failures.is_empty() and cases >= 100:
		print("TASK8 PORTABLE SETTINGS STORE PASS cases=%d" % cases); quit(0)
	else:
		print("TASK8 PORTABLE SETTINGS STORE FAIL cases=%d failures=%s" % [cases, ",".join(failures)]); quit(1)
