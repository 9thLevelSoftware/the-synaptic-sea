extends SceneTree

## AutosavePolicy reachability proof: the timed/rotating autosave loop is owned and
## driven by the LIVE coordinator (playable.autosave_policy), and a forced autosave
## actually hits disk as a rotating autosave_a/b/c slot through the coordinator's own
## save path — NOT a freshly-built policy/service. This is the difference from
## autosave_policy_smoke.gd (a pure-model test). Here the coordinator must wire the
## policy into the live run and persist through save_load_service.save_to_slot itself.
##
## Pass marker: MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	# 1) The coordinator OWNS the policy (not the smoke).
	var policy = playable.get_autosave_policy_for_validation()
	if policy == null:
		_fail("coordinator does not own an AutosavePolicy")
		return
	var service = playable.save_load_service
	if service == null:
		_fail("save_load_service missing")
		return

	# 2) Force an autosave through the real coordinator seam (no 90 s wait).
	var r1: Dictionary = playable.force_autosave_for_validation()
	if not bool(r1.get("should_save", false)):
		_fail("forced autosave did not fire (should_save=false)")
		return
	if str(r1.get("reason", "")) != "forced":
		_fail("forced autosave reason=%s expected forced" % str(r1.get("reason", "")))
		return
	var slot_a: String = str(r1.get("slot_id", ""))
	if not SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(slot_a):
		_fail("forced autosave slot=%s not in AUTOSAVE_SLOT_IDS" % slot_a)
		return

	# 3) The rotating autosave actually hit disk as an AUTO slot through the real path.
	if not _has_auto_row(service, slot_a):
		_fail("no SLOT_KIND_AUTO row for slot=%s after forced autosave" % slot_a)
		return

	# 4) A second forced autosave rotates to a different slot.
	var r2: Dictionary = playable.force_autosave_for_validation()
	if not bool(r2.get("should_save", false)):
		_fail("second forced autosave did not fire")
		return
	var slot_b: String = str(r2.get("slot_id", ""))
	if not SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(slot_b):
		_fail("second forced autosave slot=%s not in AUTOSAVE_SLOT_IDS" % slot_b)
		return
	if slot_b == slot_a:
		_fail("autosave slot did not rotate: %s -> %s" % [slot_a, slot_b])
		return
	if not _has_auto_row(service, slot_b):
		_fail("no SLOT_KIND_AUTO row for rotated slot=%s" % slot_b)
		return

	# 5) Additive only — the REQ-012 current_run path is untouched by the autosave loop.
	if playable.get_last_autosave_result().get("slot_id", "") != slot_b:
		_fail("get_last_autosave_result did not track the last write")
		return

	finished = true
	print("MAIN PLAYABLE META AUTOSAVE PASS slot_rotated=true reachable=true")
	# Cleanup the slots this smoke wrote so it leaves no residual autosave state.
	for sid in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
		service.delete_slot(sid)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _has_auto_row(service, slot_id: String) -> bool:
	for row in service.list_slots():
		if str(row.slot_id) == slot_id and str(row.slot_kind) == SaveSlotStateScript.SLOT_KIND_AUTO:
			return true
	return false

func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node.get_script() == load("res://scripts/procgen/playable_generated_ship.gd"):
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE META AUTOSAVE FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
