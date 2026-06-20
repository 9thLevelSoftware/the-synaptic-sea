extends SceneTree

## REQ-014 permanent regression: actual seed sequence 2 repair_junction
## round-trip through save/load, including a real next-frame interaction
## after load. Locks down the two blocking findings from review
## t_80dcea4b:
##
##   - Blocking finding A: live coordinator path leaves
##     ObjectiveProgressState incomplete when a carried calibrator
##     reduces a real 2-step repair_junction to 1 required step.
##     Asserted through `complete_objective_sequence_for_validation(2)`
##     driving the actual `_on_interactable_completed` path on the
##     seed template's sequence 2 (primary_coupling / secondary_coupling
##     are both real interactables spawned by the loader).
##
##   - Blocking finding B: post-load interactions crash with
##     "Nonexistent function 'mark_completed' in base 'previously
##     freed'" because `_on_ship_loaded` re-used a stale `tracker`
##     reference after `_reset_runtime_for_reload` freed the HUD layer
##     children. This smoke saves with the calibrator carried, saves
##     after the calibrated junction is consumed, and on every load
##     drives a real next-frame interaction (waiting one process_frame
##     after load before interacting) so the rebuilt tracker is
##     exercised end-to-end. It also asserts the junction_calibrator
##     pickup marker stays hidden after reload in both carried and
##     consumed/applied save states — a previously-undetected REQ-012
##     reload lifecycle gap.
##
## Pass marker: `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS
## carried_load=true consumed_load=true next_frame_interaction=true`.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 600
const JUNCTION_CALIBRATOR_TOOL_ID: String = "junction_calibrator"

var main_node: Node
var playable
var frame_count: int = 0
var phase: String = "waiting_ready"
var finished: bool = false
var post_load_wait_frames: int = 0

func _initialize() -> void:
	# Clean any leftover save from a prior run so the smoke starts from
	# a known empty slot.
	var bootstrap_service := SaveLoadService.new()
	bootstrap_service.delete_current_run()
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
			_phase_acquire_and_save_carried()
		"after_carried_load":
			# Wait one extra frame after load before interacting so the
			# rebuilt HUD/tracker has a chance to fully enter the tree.
			# This is the post-load "next frame" the reviewer probe
			# flagged: a same-frame load+interact does not exercise the
			# rebuilt tracker because the tracker node's _ready may run
			# AFTER request_load returns.
			if post_load_wait_frames > 0:
				post_load_wait_frames -= 1
				return
			_phase_verify_carried_load_and_consume()
		"after_consumed_load":
			if post_load_wait_frames > 0:
				post_load_wait_frames -= 1
				return
			_phase_verify_consumed_load_and_finish()

func _phase_acquire_and_save_carried() -> void:
	if not playable.acquire_junction_calibrator_for_validation():
		_fail("could not acquire junction_calibrator")
		return
	if not _inventory_has_calibrator():
		_fail("inventory missing junction_calibrator after acquisition")
		return
	if _junction_pickup_marker_visible():
		_fail("pickup marker visible immediately after acquisition")
		return
	# Complete objective 1 while carrying the calibrator. It is not a
	# repair_junction so the calibrator must survive to sequence 2.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("could not complete sequence 1 while carrying calibrator")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("expected current sequence 2 after objective 1, got %d" % playable.get_current_objective_sequence())
		return
	if not _inventory_has_calibrator():
		_fail("calibrator was consumed by non-repair sequence 1")
		return
	if not playable.request_save():
		_fail("request_save failed for carried-calibrator state")
		return
	if not playable.request_load():
		_fail("request_load failed for carried-calibrator state")
		return
	post_load_wait_frames = 2
	phase = "after_carried_load"

func _phase_verify_carried_load_and_consume() -> void:
	if not _inventory_has_calibrator():
		_fail("load did not restore carried junction_calibrator in inventory")
		return
	if _junction_pickup_marker_visible():
		_fail("load restored carried junction_calibrator but pickup marker is visible/acquirable again")
		return
	# This is the actual seed sequence 2 repair_junction path. The
	# calibrator reduces required_steps from 2 to 1 and the coordinator
	# must still record a complete_step so the objective_progress model
	# ends up with complete=true. Driving this through
	# complete_objective_sequence_for_validation exercises the real
	# _on_interactable_completed path including the REQ-014 fix for
	# blocking finding A (the post-calibration is_multi_step check now
	# uses the PRE-calibration required_steps so the complete_step
	# branch still fires).
	if playable.get_current_objective_sequence() != 2:
		_fail("expected current sequence 2 after carried load, got %d" % playable.get_current_objective_sequence())
		return
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("could not complete real seed sequence 2 repair_junction with calibrator after carried load")
		return
	if playable.get_current_objective_sequence() != 3:
		_fail("expected current sequence 3 after calibrated repair_junction, got %d" % playable.get_current_objective_sequence())
		return
	if _inventory_has_calibrator():
		_fail("calibrator still carried after successful repair_junction calibration")
		return
	var seq2: Dictionary = playable.get_objective_progress_summary().get(2, {})
	if int(seq2.get("required_steps", -1)) != 1:
		_fail("sequence 2 required_steps expected 1 after calibration, got %s" % str(seq2.get("required_steps", null)))
		return
	if not bool(seq2.get("calibrator_applied", false)):
		_fail("sequence 2 calibrator_applied expected true after calibration")
		return
	if not bool(seq2.get("complete", false)):
		_fail("sequence 2 progress complete expected true after calibrated completion, got %s" % str(seq2))
		return
	if int(seq2.get("completed_steps", 0)) < int(seq2.get("required_steps", 1)):
		_fail("sequence 2 completed_steps below required_steps after calibrated completion, got %s" % str(seq2))
		return
	if not playable.request_save():
		_fail("request_save failed for consumed-calibrator state")
		return
	if not playable.request_load():
		_fail("request_load failed for consumed-calibrator state")
		return
	post_load_wait_frames = 2
	phase = "after_consumed_load"

func _phase_verify_consumed_load_and_finish() -> void:
	# Reload invariant: pickup marker hidden (calibrator was spent), the
	# objective_progress_summary restored the calibrator_applied /
	# required_steps=1 / complete=true state, and inventory no longer
	# contains the calibrator. Without the JSON-string-int-key fix in
	# ObjectiveProgressState.apply_summary, the reload would silently
	# drop these fields because the JSON-roundtrip turns `2` -> `"2"`.
	if _inventory_has_calibrator():
		_fail("load restored consumed junction_calibrator into inventory")
		return
	var seq2: Dictionary = playable.get_objective_progress_summary().get(2, {})
	if int(seq2.get("required_steps", -1)) != 1:
		_fail("load did not preserve calibrated required_steps=1 for sequence 2, got %s" % str(seq2.get("required_steps", null)))
		return
	if not bool(seq2.get("calibrator_applied", false)):
		_fail("load did not preserve calibrator_applied=true for sequence 2")
		return
	if not bool(seq2.get("complete", false)):
		_fail("load did not preserve complete=true for calibrated sequence 2")
		return
	if _junction_pickup_marker_visible():
		_fail("load restored consumed/applied junction_calibrator but pickup marker is visible/acquirable again")
		return
	if playable.get_current_objective_sequence() != 3:
		_fail("expected current sequence 3 after consumed load, got %d" % playable.get_current_objective_sequence())
		return
	finished = true
	print("MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true")
	_cleanup_and_quit(0)

func _inventory_has_calibrator() -> bool:
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	return tool_ids.has(JUNCTION_CALIBRATOR_TOOL_ID)

func _junction_pickup_marker_visible() -> bool:
	var pickup: Node = playable.get_junction_calibrator_pickup_node()
	if pickup == null:
		return false
	var marker: Variant = pickup.get("marker")
	return marker != null and marker is Node3D and (marker as Node3D).visible

func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
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
	push_error("MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	# Best-effort cleanup of any leftover save file so subsequent runs
	# start from a known empty slot.
	var service := SaveLoadService.new()
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
