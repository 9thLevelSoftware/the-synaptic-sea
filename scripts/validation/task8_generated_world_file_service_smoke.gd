extends SceneTree
const Service := preload("res://scripts/systems/generated_world_save_service.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var cases := 0
var failures: Array[String] = []
var test_root := "user://task8-tests/file-" + str(Time.get_ticks_usec())

func _init() -> void:
	var service := Service.new(); service.storage_directory = test_root
	var unsafe := Service.new(); unsafe.storage_directory = "C:/unsafe"; _expect(unsafe.path_for("x").is_empty(), "unsafe configured path")
	for slot in ["a", "A0_-", "x".repeat(64)]: _expect(not service.path_for(slot).is_empty(), "valid slot")
	for slot in [true, 7, "", "../escape", "a/b", "a\\b", "a.b", "a:b", "é", "x".repeat(65)]: _expect(service.path_for(slot).is_empty(), "invalid slot")
	var env := _envelope(); _expect(service.save("smoke", env), "save"); var path := service.path_for("smoke"); _expect(FileAccess.file_exists(path), "final exists")
	var original := FileAccess.get_file_as_string(path); _expect(service.save("smoke", env), "consecutive save"); _expect(FileAccess.get_file_as_string(path) == original, "bytes stable")
	service.token_queue = ["bad", "B".repeat(32), "c".repeat(32)]; _expect(service.save("token", env), "token invalid then unique")
	for point in ["directory", "stage_open", "stage_write", "stage_verify_open", "stage_verify_content", "backup_rename", "promote_rename", "final_verify", "final_verify,restore_rename", "final_verify,restore_copy", "cleanup"]:
		service.failpoint = point; var before := FileAccess.get_file_as_string(path); var ok := service.save("smoke", env); _expect(not ok, "failpoint " + point); _expect(FileAccess.get_file_as_string(path) == before, "preserve " + point); service.failpoint = ""
	_expect(service.load_and_validate("smoke", null).reason_code == "compatibility_unavailable", "compat unavailable")
	_finish()

func _envelope() -> RefCounted:
	var map := {}; for key in Envelope.EXPORT_KEYS: map[key] = "v1"
	var e := Envelope.new(); _expect(e.configure(42, 3, HASH, map, []), "envelope"); return e

func _expect(value: bool, label: String) -> void:
	cases += 1; if not value: failures.append(label)

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root)); if failures.is_empty(): print("TASK8 GENERATED WORLD FILE SERVICE PASS cases=%d" % cases); quit(0)
	else: push_error("TASK8 GENERATED WORLD FILE SERVICE FAIL %s" % ",".join(failures)); quit(1)
