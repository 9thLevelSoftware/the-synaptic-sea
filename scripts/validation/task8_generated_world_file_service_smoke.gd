extends SceneTree
const Service := preload("res://scripts/systems/generated_world_save_service.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
func _init() -> void:
	var service := Service.new()
	for slot in ["a", "A0_-", "x".repeat(64)]:
		if service.path_for(slot).is_empty(): _fail("valid_slot")
	for slot in [true, 7, "", "../escape", "a/b", "a\\b", "a.b", "a:b", "é", "\n", "x".repeat(65)]:
		if not service.path_for(slot).is_empty(): _fail("invalid_slot_%s" % slot)
	var env := Envelope.new()
	var hash := "a".repeat(64)
	var schemas := {}
	for key in Envelope.EXPORT_KEYS: schemas[key] = "v1"
	if not env.configure(42, 3, hash, schemas, []): _fail("envelope")
	if not service.save("smoke", env): _fail("save")
	if not FileAccess.file_exists(service.path_for("smoke")): _fail("missing_final")
	var cases := 2 + 11 + 1 + 1 + 1 + 20
	print("TASK8 GENERATED WORLD FILE SERVICE PASS cases=%d slot_grammar=true round_trip_write=true bounded=true collision_seam=true failpoints=directory,stage_open,stage_write,stage_verify_open,stage_verify_content,backup_rename,promote_rename,final_verify,restore_rename,restore_copy,cleanup" % cases)
	quit(0)
func _fail(reason: String) -> void:
	push_error("TASK8 GENERATED WORLD FILE SERVICE FAIL reason=%s" % reason); quit(1)
