extends SceneTree

const Service := preload("res://scripts/systems/generated_world_save_service.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const TOKENS := "0123456789abcdef"

class CompatibilityProbe extends RefCounted:
	var calls := 0
	var mode := "compatible"
	var last_document: Variant = null
	func evaluate(document: Variant, path: String):
		calls += 1
		last_document = document
		if mode == "new_world": return Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", path)
		if mode == "corrupt": return Result.make(Result.CORRUPT, "malformed_envelope", path)
		if mode == "invalid": return {"status":"compatible"}
		return Result.make(Result.COMPATIBLE, "validated", path)

var cases := 0
var failures: Array[String] = []
var test_root := "user://task8-tests/file-" + str(Time.get_ticks_usec())

func _init() -> void:
	var service := Service.new()
	service.storage_directory = test_root
	for unsafe_path in ["", "C:/unsafe", "user://", "user://../escape", "user://safe/../escape", "user://bad\\path", "user://bad:path"]:
		var unsafe := Service.new(); unsafe.storage_directory = unsafe_path
		_expect(unsafe.path_for("x").is_empty(), "unsafe configured path " + unsafe_path)
	for slot in ["a", "A0_-", "x".repeat(64)]: _expect(not service.path_for(slot).is_empty(), "valid slot " + slot)
	for slot in [true, 7, "", "../escape", "a/b", "a\\b", "a.b", "a:b", "é", "x".repeat(65)]: _expect(service.path_for(slot).is_empty(), "invalid slot " + str(slot))
	var missing_path := service.path_for("missing")
	var missing: Variant = service.load_and_validate("missing", CompatibilityProbe.new())
	_expect(missing.status == Result.IO_FAILURE and missing.reason_code == "missing_file" and missing.preserved_path == missing_path, "missing file result")

	var envelope := _envelope()
	for index in 7:
		var point: String = ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "promote_rename", "final_verify"][index]
		var slot := "first%d" % index
		var token := TOKENS.substr(index, 1).repeat(32)
		var final := service.path_for(slot); var stage := final + ".stage." + token; var backup := final + ".backup." + token
		service.failpoint = point; service.failpoint_hits.clear(); service.token_queue = [token]
		_expect(not service.save(slot, envelope), "first save fail " + point)
		_expect(not FileAccess.file_exists(final), "first save no final " + point)
		_expect(not FileAccess.file_exists(stage) and not FileAccess.file_exists(backup), "first save no sidecar " + point)
		_expect(int(service.failpoint_hits.get(point, 0)) > 0, "first save hit " + point)
	service.failpoint = ""; service.token_queue.clear()

	_expect(service.save("smoke", envelope), "initial save")
	var path := service.path_for("smoke")
	var original := FileAccess.get_file_as_string(path)
	_expect(FileAccess.file_exists(path) and not original.is_empty(), "initial final exists")
	_expect(service.save("smoke", envelope), "consecutive save")
	_expect(FileAccess.get_file_as_string(path) == original, "consecutive bytes stable")

	var collision_slot := "collision"; var collision_final := service.path_for(collision_slot)
	var collision_a := "a".repeat(32); var collision_b := "b".repeat(32); var collision_stage := collision_final + ".stage." + collision_a
	_write(collision_stage, "collision-sentinel")
	service.token_queue = [collision_a, collision_b]
	_expect(service.save(collision_slot, envelope), "collision advances to unique token")
	_expect(service.token_queue.is_empty(), "collision consumed distinct token")
	_expect(FileAccess.get_file_as_string(collision_stage) == "collision-sentinel", "collision sidecar untouched")
	_remove(collision_stage)

	var rejected := Service.new(); rejected.storage_directory = test_root
	rejected.token_queue = []
	for _i in 32: rejected.token_queue.append("z".repeat(32))
	_expect(not rejected.save("badtoken", envelope), "nonhex tokens exhaust")
	_expect(rejected.token_queue.is_empty() and not FileAccess.file_exists(rejected.path_for("badtoken")), "nonhex tokens create nothing")

	var mutated := _envelope(); mutated.content_manifest_hash = "bad"
	_expect(not service.save("mutated", mutated), "mutated envelope rejected before write")
	_expect(not FileAccess.file_exists(service.path_for("mutated")), "mutated envelope creates nothing")

	var preserving_points := ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "backup_rename", "promote_rename", "final_verify", "final_verify,restore_rename", "cleanup"]
	for index in preserving_points.size():
		var point: String = preserving_points[index]
		var token := TOKENS.substr((index + 1) % TOKENS.length(), 1).repeat(32)
		var stage := path + ".stage." + token; var backup := path + ".backup." + token
		service.failpoint = point; service.failpoint_hits.clear(); service.token_queue = [token]
		_expect(not service.save("smoke", envelope), "existing save fail " + point)
		_expect(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == original, "existing bytes preserved " + point)
		_expect(not FileAccess.file_exists(stage) and not FileAccess.file_exists(backup), "existing sidecars cleaned " + point)
		for name in point.split(","): _expect(int(service.failpoint_hits.get(name, 0)) > 0, "existing hit " + name)
	service.failpoint = ""; service.token_queue.clear()

	var failed_restore_token := "f".repeat(32); var failed_backup := path + ".backup." + failed_restore_token
	service.failpoint = "final_verify,restore_rename,restore_copy"; service.failpoint_hits.clear(); service.token_queue = [failed_restore_token]
	_expect(not service.save("smoke", envelope), "both restore paths fail")
	_expect(not FileAccess.file_exists(path), "failed restore does not expose new final")
	_expect(FileAccess.file_exists(failed_backup) and FileAccess.get_file_as_string(failed_backup) == original, "failed restore preserves backup evidence")
	_expect(int(service.failpoint_hits.get("restore_rename", 0)) > 0 and int(service.failpoint_hits.get("restore_copy", 0)) > 0, "both restore branches hit")
	_expect(DirAccess.rename_absolute(ProjectSettings.globalize_path(failed_backup), ProjectSettings.globalize_path(path)) == OK, "test restores preserved backup")
	service.failpoint = ""

	var probe := CompatibilityProbe.new()
	var malformed_path := service.path_for("malformed"); _write(malformed_path, "{")
	var malformed_before := FileAccess.get_file_as_string(malformed_path)
	var malformed: Variant = service.load_and_validate("malformed", probe)
	_expect(malformed.status == Result.CORRUPT and malformed.reason_code == "json_parse_failed" and probe.calls == 0, "malformed json blocked before compatibility")
	_expect(FileAccess.get_file_as_string(malformed_path) == malformed_before, "malformed bytes preserved")

	var null_path := service.path_for("nulljson"); _write(null_path, "null"); probe = CompatibilityProbe.new(); probe.mode = "corrupt"
	var null_result: Variant = service.load_and_validate("nulljson", probe)
	_expect(null_result.reason_code == "malformed_envelope" and probe.calls == 1 and probe.last_document == null, "valid json null reaches compatibility")
	_expect(FileAccess.get_file_as_string(null_path) == "null", "null bytes preserved")

	var oversized_path := service.path_for("oversized"); _write(oversized_path, "x".repeat(Service.MAX_BYTES + 1)); probe = CompatibilityProbe.new()
	var oversized: Variant = service.load_and_validate("oversized", probe)
	_expect(oversized.reason_code == "document_too_large" and probe.calls == 0, "oversized blocked before read and compatibility")
	_expect(FileAccess.get_file_as_string(oversized_path).length() == Service.MAX_BYTES + 1, "oversized bytes preserved")

	var incompatible_path := service.path_for("incompatible"); var valid_text := JSON.stringify(envelope.to_dict()); _write(incompatible_path, valid_text)
	probe = CompatibilityProbe.new(); probe.mode = "new_world"
	var incompatible: Variant = service.load_and_validate("incompatible", probe)
	_expect(incompatible.status == Result.NEW_WORLD_REQUIRED and incompatible.reason_code == "platform_generator_mismatch" and incompatible.preserved_path == incompatible_path, "incompatible typed result")
	_expect(probe.calls == 1 and FileAccess.get_file_as_string(incompatible_path) == valid_text, "incompatible probe is read only")
	probe = CompatibilityProbe.new(); probe.mode = "corrupt"
	var corrupt: Variant = service.load_and_validate("incompatible", probe)
	_expect(corrupt.status == Result.CORRUPT and FileAccess.get_file_as_string(incompatible_path) == valid_text, "corrupt probe is read only")
	var unavailable: Variant = service.load_and_validate("incompatible", null)
	_expect(unavailable.reason_code == "compatibility_unavailable" and FileAccess.get_file_as_string(incompatible_path) == valid_text, "unavailable compatibility is read only")
	probe = CompatibilityProbe.new(); probe.mode = "invalid"
	var invalid_result: Variant = service.load_and_validate("incompatible", probe)
	_expect(invalid_result.status == Result.IO_FAILURE and invalid_result.reason_code == "compatibility_unavailable", "untyped compatibility result rejected")
	_expect(FileAccess.get_file_as_string(incompatible_path) == valid_text, "invalid compatibility result is read only")

	_finish()

func _envelope() -> RefCounted:
	var schemas := {}; for key in Envelope.EXPORT_KEYS: schemas[key] = "v1"
	var result := Envelope.new(); _expect(result.configure(42, 3, HASH, schemas, []), "envelope configured"); return result

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
	if failures.is_empty() and cases >= 80:
		print("TASK8 GENERATED WORLD FILE SERVICE PASS cases=%d" % cases); quit(0)
	else:
		print("TASK8 GENERATED WORLD FILE SERVICE FAIL cases=%d failures=%s" % [cases, ",".join(failures)]); quit(1)
