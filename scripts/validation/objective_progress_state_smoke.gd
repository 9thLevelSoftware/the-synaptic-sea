extends SceneTree

func _initialize() -> void:
	var model := ObjectiveProgressState.new()

	# Register a 2-step repair junction at sequence 2.
	model.register_objective(2, "restore_systems", 2)

	var initial: Dictionary = model.get_step_progress(2)
	if int(initial.get("required_steps", -1)) != 2:
		_fail("initial required_steps should be 2, got %s" % str(initial.get("required_steps", -1)))
		return
	if int(initial.get("completed_steps", -1)) != 0:
		_fail("initial completed_steps should be 0, got %s" % str(initial.get("completed_steps", -1)))
		return
	if bool(initial.get("complete", true)):
		_fail("initial complete should be false")
		return

	# Complete first step out of order.
	var first_changed: bool = model.complete_step(2, "secondary_coupling")
	if not first_changed:
		_fail("first complete_step should report changed")
		return
	if model.is_sequence_complete(2):
		_fail("sequence should not be complete after one step")
		return
	var after_one: Dictionary = model.get_step_progress(2)
	if int(after_one.get("completed_steps", -1)) != 1:
		_fail("completed_steps should be 1 after first step, got %s" % str(after_one.get("completed_steps", -1)))
		return
	if bool(after_one.get("complete", true)):
		_fail("complete should still be false after one step")
		return

	# Completing the same step again is idempotent.
	var duplicate: bool = model.complete_step(2, "secondary_coupling")
	if duplicate:
		_fail("duplicate complete_step should report unchanged")
		return
	var after_duplicate: Dictionary = model.get_step_progress(2)
	if int(after_duplicate.get("completed_steps", -1)) != 1:
		_fail("completed_steps should remain 1 after duplicate step")
		return

	# Complete second step.
	var second_changed: bool = model.complete_step(2, "primary_coupling")
	if not second_changed:
		_fail("second complete_step should report changed")
		return
	if not model.is_sequence_complete(2):
		_fail("sequence should be complete after both steps")
		return
	var after_two: Dictionary = model.get_step_progress(2)
	if int(after_two.get("completed_steps", -1)) != 2:
		_fail("completed_steps should be 2 after both steps, got %s" % str(after_two.get("completed_steps", -1)))
		return
	if not bool(after_two.get("complete", false)):
		_fail("complete should be true after both steps")
		return

	# Summary shape check.
	var summary: Dictionary = model.get_summary()
	if not summary.has(2):
		_fail("summary missing sequence 2")
		return
	var seq_summary: Dictionary = summary.get(2, {})
	if str(seq_summary.get("objective_type", "")) != "restore_systems":
		_fail("summary objective_type should be restore_systems")
		return
	var completed_ids: Array = seq_summary.get("completed_step_ids", [])
	if completed_ids.size() != 2:
		_fail("completed_step_ids should contain 2 entries")
		return

	print("OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("OBJECTIVE PROGRESS STATE FAIL reason=%s" % reason)
	quit(1)
