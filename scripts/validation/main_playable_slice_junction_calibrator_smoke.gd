extends SceneTree

## REQ-014: junction_calibrator main-scene smoke.
##
## Loads the playable slice, drives a real pickup acquisition for the
## second ToolPickup (junction_calibrator), then validates the
## coordinator's calibration path end-to-end on a synthetic 3-step
## repair_junction sequence registered through the validation seam.
##
## Why a synthetic sequence instead of the seed template's 2-step
## junction: REQ-014 acceptance criteria require reducing a 3-step
## junction to 2; the seed template's sequence 2 has exactly 2 steps,
## which the calibrator would reduce to 1 (and the model's minimum-one
## step guard would still pass, but the marker `required_steps=2`
## would not match). The seam registers a 3-step junction so the
## marker matches exactly while still routing through the same
## `_consume_junction_calibrator_if_eligible` path a real repair
## interaction would take.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SYNTHETIC_JUNCTION_SEQUENCE: int = 99
const SYNTHETIC_JUNCTION_STEPS: int = 3
const JUNCTION_CALIBRATOR_TOOL_ID: String = "junction_calibrator"

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var finished: bool = false

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_initial_state()
		"acquire_calibrator":
			_acquire_calibrator()
		"register_synthetic_junction":
			_register_synthetic_junction()
		"apply_calibrator":
			_apply_calibrator()
		"verify_reduction":
			_verify_reduction()
		"verify_consumption":
			_verify_consumption()

func _validate_initial_state() -> void:
	# Fresh inventory must not contain the calibrator.
	var initial_inventory: Dictionary = playable.get_inventory_summary()
	var initial_tool_ids: Array = initial_inventory.get("tool_ids", []) as Array
	if initial_tool_ids.has(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("fresh inventory must not contain junction_calibrator, got %s" % str(initial_inventory))
		return
	# Status lines must not advertise the calibrator before acquisition.
	var initial_lines: PackedStringArray = playable.get_combined_system_status_lines()
	for initial_line in initial_lines:
		var initial_text: String = String(initial_line)
		if initial_text == "tool=junction_calibrator" or initial_text == "Tool: Junction Calibrator":
			_fail("status output must not advertise junction_calibrator before acquisition, got %s" % str(initial_lines))
			return
	# The pickup node must exist with a visible marker.
	var pickup: Node = playable.get_junction_calibrator_pickup_node()
	if pickup == null:
		_fail("junction_calibrator pickup node missing")
		return
	var marker: Variant = pickup.get("marker")
	if marker == null or not (marker is Node3D) or not (marker as Node3D).visible:
		_fail("junction_calibrator pickup marker should be visible before acquisition, marker=%s" % str(marker))
		return
	# The pickup must be configured with the correct tool id.
	if str(pickup.get("tool_id")) != JUNCTION_CALIBRATOR_TOOL_ID:
		_fail("junction_calibrator pickup tool_id should be junction_calibrator, got %s" % str(pickup.get("tool_id")))
		return
	phase = "acquire_calibrator"

func _acquire_calibrator() -> void:
	if not playable.acquire_junction_calibrator_for_validation():
		_fail("acquire_junction_calibrator_for_validation failed")
		return
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	if tool_ids.size() != 1 or str(tool_ids[0]) != JUNCTION_CALIBRATOR_TOOL_ID:
		_fail("inventory should contain junction_calibrator after acquisition, got %s" % str(inventory))
		return
	# Pickup marker should now be hidden.
	var pickup: Node = playable.get_junction_calibrator_pickup_node()
	var marker: Variant = pickup.get("marker")
	if marker != null and (marker is Node3D) and (marker as Node3D).visible:
		_fail("junction_calibrator pickup marker should be hidden after acquisition, marker.visible=true")
		return
	# HUD should now include the calibrator status lines.
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	var found_tool_line: bool = false
	var found_tool_marker: bool = false
	for line in lines:
		var line_text: String = String(line)
		if line_text == "Tool: Junction Calibrator":
			found_tool_line = true
		elif line_text == "tool=junction_calibrator":
			found_tool_marker = true
	if not found_tool_line:
		_fail("HUD missing 'Tool: Junction Calibrator' line, got %s" % str(lines))
		return
	if not found_tool_marker:
		_fail("HUD missing 'tool=junction_calibrator' marker, got %s" % str(lines))
		return
	# Double acquisition is idempotent (already acquired -> inventory stays the same).
	if not playable.acquire_junction_calibrator_for_validation():
		# A second acquire with a hidden marker should fail the helper's
		# range check; the inventory must still contain exactly one tool.
		pass
	var inventory_after_second: Dictionary = playable.get_inventory_summary()
	var tool_ids_after_second: Array = inventory_after_second.get("tool_ids", []) as Array
	if tool_ids_after_second.size() != 1:
		_fail("inventory should still contain exactly one tool after double acquisition, got %s" % str(tool_ids_after_second))
		return
	phase = "register_synthetic_junction"

func _register_synthetic_junction() -> void:
	if not playable.register_junction_sequence_for_validation(SYNTHETIC_JUNCTION_SEQUENCE, SYNTHETIC_JUNCTION_STEPS):
		_fail("register_junction_sequence_for_validation returned false")
		return
	var progress: Dictionary = playable.get_objective_progress_summary()
	var seq_summary: Dictionary = progress.get(SYNTHETIC_JUNCTION_SEQUENCE, {})
	if int(seq_summary.get("required_steps", -1)) != SYNTHETIC_JUNCTION_STEPS:
		_fail("synthetic junction required_steps should be %d, got %s" % [SYNTHETIC_JUNCTION_STEPS, str(seq_summary.get("required_steps", -1))])
		return
	phase = "apply_calibrator"

func _apply_calibrator() -> void:
	# Drive the calibration through the coordinator's exact auto-consume
	# path; this is the same code _on_interactable_completed would run
	# for a real repair_junction interaction, just exposed via a
	# validation seam so the smoke does not have to drive the full
	# interactable handshake a second time.
	if not playable.apply_junction_calibrator_for_validation(SYNTHETIC_JUNCTION_SEQUENCE):
		_fail("apply_junction_calibrator_for_validation returned false")
		return
	phase = "verify_reduction"

func _verify_reduction() -> void:
	# The synthetic 3-step junction should now have required_steps == 2.
	var progress: Dictionary = playable.get_objective_progress_summary()
	var seq_summary: Dictionary = progress.get(SYNTHETIC_JUNCTION_SEQUENCE, {})
	var required_steps: int = int(seq_summary.get("required_steps", -1))
	if required_steps != 2:
		_fail("synthetic junction required_steps should be 2 after calibration, got %s" % str(required_steps))
		return
	if not bool(seq_summary.get("calibrator_applied", false)):
		_fail("synthetic junction calibrator_applied should be true after calibration")
		return
	# The 2-step completion must complete after two total step completions.
	# This is the spec's "completes after two total step completions" check
	# when starting from required_steps == 3 (calibrator reduces to 2).
	if not playable.objective_progress_state.complete_step(SYNTHETIC_JUNCTION_SEQUENCE, "primary_coupling"):
		_fail("first step completion on calibrated junction should succeed")
		return
	if playable.objective_progress_state.is_sequence_complete(SYNTHETIC_JUNCTION_SEQUENCE):
		_fail("calibrated 2-step junction should not be complete after one step")
		return
	if not playable.objective_progress_state.complete_step(SYNTHETIC_JUNCTION_SEQUENCE, "secondary_coupling"):
		_fail("second step completion on calibrated junction should succeed")
		return
	if not playable.objective_progress_state.is_sequence_complete(SYNTHETIC_JUNCTION_SEQUENCE):
		_fail("calibrated 2-step junction should be complete after two steps")
		return
	# Re-applying the calibrator after completion must be a no-op; this
	# is the safety net the coordinator relies on before consuming the
	# inventory tool.
	if playable.objective_progress_state.apply_junction_calibrator(SYNTHETIC_JUNCTION_SEQUENCE):
		_fail("calibrator re-apply on a complete sequence should return false")
		return
	phase = "verify_consumption"

func _verify_consumption() -> void:
	# Inventory must no longer contain the calibrator after a successful
	# calibration. The seed template's other objectives and pickups are
	# untouched.
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	if tool_ids.has(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("junction_calibrator should be consumed after a successful calibration, got %s" % str(inventory))
		return
	# HUD must no longer advertise the calibrator.
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	for line in lines:
		var line_text: String = String(line)
		if line_text == "tool=junction_calibrator" or line_text == "Tool: Junction Calibrator":
			_fail("status output must not advertise junction_calibrator after consumption, got %s" % str(lines))
			return
	# The pickup node should still be hidden (consumption does not
	# un-hide it; the pickup is one-shot per slice run regardless of
	# when the calibrator was acquired vs consumed).
	var pickup: Node = playable.get_junction_calibrator_pickup_node()
	var marker: Variant = pickup.get("marker")
	if marker != null and (marker is Node3D) and (marker as Node3D).visible:
		_fail("junction_calibrator pickup marker should still be hidden after consumption")
		return
	# Without the calibrator, a fresh reduction attempt should leave the
	# seed template's sequence 2 (2 steps) at 2 steps (model only acts
	# when the coordinator supplies the tool).
	var seq2_progress: Dictionary = playable.get_objective_progress_summary().get(2, {})
	if int(seq2_progress.get("required_steps", -1)) != 2:
		_fail("seed sequence 2 required_steps should remain 2 (no calibrator), got %s" % str(seq2_progress.get("required_steps", -1)))
		return
	finished = true
	# Print the exact marker the validation plan expects.
	print("MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE JUNCTION CALIBRATOR FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
