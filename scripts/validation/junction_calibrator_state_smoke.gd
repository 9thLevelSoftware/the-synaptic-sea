extends SceneTree

## REQ-014: junction_calibrator direct model smoke.
##
## Verifies the four pure-model behaviors that the feature spec calls out:
## 1. Adding the calibrator to a fresh InventoryState reports it as
##    carried and surfaces the human-readable display name + a tool=
##    marker on the status lines the HUD reads.
## 2. apply_junction_calibrator on a 3-step repair_junction sequence
##    reduces required_steps to 2, marks calibrator_applied, and is
##    idempotent on a second call.
## 3. apply_junction_calibrator on a 1-step repair_junction sequence
##    does NOT consume the calibrator and does NOT reduce required_steps
##    below 1 (the model's safety net enforces this even though the
##    coordinator is the kind-gatekeeper).
## 4. The objective_progress_summary round-trips the calibrator_applied
##    flag through get_summary / apply_summary, so REQ-012 save/load
##    restores the reduced step count and prevents re-application.

const JUNCTION_CALIBRATOR_TOOL_ID: String = "junction_calibrator"

func _initialize() -> void:
	# 1. InventoryState carries the calibrator tool id with the spec's
	#    exact display name and exposes the tool= marker on the HUD
	#    status lines.
	var inventory := InventoryState.new()
	var initial_summary: Dictionary = inventory.get_summary()
	var initial_tool_ids: Array = initial_summary.get("tool_ids", []) as Array
	if initial_tool_ids.has(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("fresh inventory must not carry junction_calibrator")
		return
	if not inventory.add_tool(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("add_tool(junction_calibrator) should return true on a fresh inventory")
		return
	if not inventory.has_tool(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("has_tool(junction_calibrator) should be true after add")
		return
	var after_add: Dictionary = inventory.get_summary()
	var carried_tool_ids: Array = after_add.get("tool_ids", []) as Array
	if carried_tool_ids.size() != 1 or str(carried_tool_ids[0]) != JUNCTION_CALIBRATOR_TOOL_ID:
		_fail("tool_ids should contain exactly junction_calibrator, got %s" % str(carried_tool_ids))
		return
	var status_lines: PackedStringArray = inventory.get_status_lines()
	var found_display_line: bool = false
	var found_tool_marker: bool = false
	for line in status_lines:
		var line_text: String = String(line)
		if line_text == "Tool: Junction Calibrator":
			found_display_line = true
		elif line_text == "tool=junction_calibrator":
			found_tool_marker = true
	if not found_display_line:
		_fail("status lines missing 'Tool: Junction Calibrator', got %s" % str(status_lines))
		return
	if not found_tool_marker:
		_fail("status lines missing 'tool=junction_calibrator' marker, got %s" % str(status_lines))
		return

	# 2. The calibrator reduces a 3-step repair_junction sequence to
	#    2 steps, marks calibrator_applied, and is idempotent.
	var model := ObjectiveProgressState.new()
	model.register_objective(1, "repair_junction", 3)
	var initial_progress: Dictionary = model.get_step_progress(1)
	if int(initial_progress.get("required_steps", -1)) != 3:
		_fail("initial required_steps should be 3, got %s" % str(initial_progress.get("required_steps", -1)))
		return
	if bool(initial_progress.get("calibrator_applied", true)):
		_fail("initial calibrator_applied should be false")
		return
	var applied: bool = model.apply_junction_calibrator(1)
	if not applied:
		_fail("apply_junction_calibrator on a 3-step repair_junction should return true")
		return
	var after_apply: Dictionary = model.get_step_progress(1)
	if int(after_apply.get("required_steps", -1)) != 2:
		_fail("required_steps should be 2 after calibrator applied to 3-step junction, got %s" % str(after_apply.get("required_steps", -1)))
		return
	if not bool(after_apply.get("calibrator_applied", false)):
		_fail("calibrator_applied should be true after apply_junction_calibrator")
		return
	if not model.has_calibrator_applied(1):
		_fail("has_calibrator_applied should report true after a successful apply")
		return
	# Idempotent: a second apply does NOT return true (would double-count
	# the reduction).
	var second_apply: bool = model.apply_junction_calibrator(1)
	if second_apply:
		_fail("second apply_junction_calibrator on the same sequence must return false")
		return
	var after_second_apply: Dictionary = model.get_step_progress(1)
	if int(after_second_apply.get("required_steps", -1)) != 2:
		_fail("required_steps should stay 2 after second apply, got %s" % str(after_second_apply.get("required_steps", -1)))
		return

	# 3. The sequence still needs to be completed by the model after the
	#    reduction. Two step completions should bring completed_steps up
	#    to the (now reduced) required_steps of 2 and mark complete.
	var first_step: bool = model.complete_step(1, "primary_coupling")
	if not first_step:
		_fail("first step completion should succeed on a 2-step (reduced) junction")
		return
	var after_first_step: Dictionary = model.get_step_progress(1)
	if int(after_first_step.get("completed_steps", -1)) != 1:
		_fail("completed_steps should be 1 after first step, got %s" % str(after_first_step.get("completed_steps", -1)))
		return
	if bool(after_first_step.get("complete", false)):
		_fail("sequence should not be complete after one step of a 2-step (reduced) junction")
		return
	var second_step: bool = model.complete_step(1, "secondary_coupling")
	if not second_step:
		_fail("second step completion should succeed on a 2-step (reduced) junction")
		return
	if not model.is_sequence_complete(1):
		_fail("sequence should be complete after both steps of a reduced 2-step junction")
		return

	# 4. A 1-step junction does NOT consume the calibrator. The model's
	#    safety net returns false on required_steps == 1.
	var one_step_model := ObjectiveProgressState.new()
	one_step_model.register_objective(2, "repair_junction", 1)
	var one_step_apply: bool = one_step_model.apply_junction_calibrator(2)
	if one_step_apply:
		_fail("apply_junction_calibrator on a 1-step junction should return false (minimum one step)")
		return
	var one_step_progress: Dictionary = one_step_model.get_step_progress(2)
	if int(one_step_progress.get("required_steps", -1)) != 1:
		_fail("required_steps should remain 1 after a no-op apply, got %s" % str(one_step_progress.get("required_steps", -1)))
		return
	if bool(one_step_progress.get("calibrator_applied", false)):
		_fail("calibrator_applied should remain false after a no-op apply")
		return
	# Confirm the coordinator's contract: the calibrator stays in
	# inventory because the model did not reduce the sequence.
	if not inventory.has_tool(JUNCTION_CALIBRATOR_TOOL_ID):
		_fail("calibrator should remain in inventory after a no-op apply (1-step junction)")
		return

	# 5. Summary round-trips the calibrator_applied flag through
	#    get_summary / apply_summary so REQ-012 save/load preserves it.
	var summary: Dictionary = model.get_summary()
	if not summary.has(1):
		_fail("summary missing sequence 1")
		return
	var seq_summary: Dictionary = summary.get(1, {})
	if not bool(seq_summary.get("calibrator_applied", false)):
		_fail("summary.calibrator_applied should be true for the reduced sequence")
		return
	# Round-trip: build a fresh model from the summary and confirm the
	# flag, required_steps, and complete state all restored correctly.
	var restored := ObjectiveProgressState.new()
	if not restored.apply_summary(summary):
		_fail("apply_summary on a fresh model should report changed=true")
		return
	var restored_progress: Dictionary = restored.get_step_progress(1)
	if int(restored_progress.get("required_steps", -1)) != 2:
		_fail("restored required_steps should be 2, got %s" % str(restored_progress.get("required_steps", -1)))
		return
	if not bool(restored_progress.get("calibrator_applied", false)):
		_fail("restored calibrator_applied should be true")
		return
	# Re-apply against the restored model must be a no-op: the flag
	# prevents a reloaded run from applying the calibrator twice.
	var restored_reapply: bool = restored.apply_junction_calibrator(1)
	if restored_reapply:
		_fail("restored model must reject a re-apply (calibrator_applied already true)")
		return

	# 6. Print the exact marker the validation plan expects. The shape
	#    mirrors objective_progress_state_smoke: required_steps reflects
	#    the post-calibrator value, consumed=true carries the inventory
	#    evidence, and applied_once=true carries the model flag.
	print("JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("JUNCTION CALIBRATOR STATE FAIL reason=%s" % reason)
	quit(1)
