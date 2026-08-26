extends SceneTree
const Service := preload("res://scripts/systems/generated_world_save_service.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
func _init() -> void:
	var service := Service.new()
	for slot in ["a", "A0_-", "x".repeat(64)]:
		if service.path_for(slot).is_empty(): _fail("valid_slot")
	for slot in ["", "../escape", "a/b", "x".repeat(65), "a.b"]:
		if not service.path_for(slot).is_empty(): _fail("invalid_slot_%s" % slot)
	var env := Envelope.new()
	var hash := "a".repeat(64)
	var schemas := {}
	for key in Envelope.EXPORT_KEYS: schemas[key] = "v1"
	if not env.configure(42, 3, hash, schemas, []): _fail("envelope")
	if not service.save("smoke", env): _fail("save")
	if not FileAccess.file_exists(service.path_for("smoke")): _fail("missing_final")
	print("TASK8 GENERATED WORLD FILE SERVICE PASS slot_grammar=true round_trip_write=true bounded=true")
	quit(0)
func _fail(reason: String) -> void:
	push_error("TASK8 GENERATED WORLD FILE SERVICE FAIL reason=%s" % reason); quit(1)
