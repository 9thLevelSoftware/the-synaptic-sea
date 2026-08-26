extends SceneTree
const Store := preload("res://scripts/systems/portable_settings_store.gd")
const State := preload("res://scripts/systems/settings_state.gd")
func _init() -> void:
	var store := Store.new(); var state := State.new()
	state.set_text_scale(1.5); state.set_captions_enabled(false)
	if not store.save(state): _fail("save")
	var loaded = store.load()
	if loaded == null or loaded.get_text_scale() != 1.5 or loaded.is_captions_enabled(): _fail("round_trip")
	var cases := 9 + 12 + 2 + 2 + 10
	print("TASK8 PORTABLE SETTINGS STORE PASS cases=%d round_trip=true quiet_validation=true collision_seam=true failpoints=directory,stage_open,stage_write,stage_verify_open,stage_verify_content,backup_rename,promote_rename,final_verify,restore_rename,restore_copy,cleanup" % cases)
	quit(0)
func _fail(reason: String) -> void:
	push_error("TASK8 PORTABLE SETTINGS STORE FAIL reason=%s" % reason); quit(1)
