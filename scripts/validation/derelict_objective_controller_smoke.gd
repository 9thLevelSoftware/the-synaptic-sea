extends SceneTree

## Unit smoke for DerelictObjectiveController: configure from generated specs,
## complete salvage + reach_goal, cleared semantics, summary round-trip.

const ControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")

func _initialize() -> void:
	var specs: Array = [
		{"id": "obj_salvage_cargo_01", "sequence": 1, "type": "salvage", "kind": "single", "room_id": "cargo_01"},
		{
			"id": "obj_repair_eng_01", "sequence": 2, "type": "restore_systems",
			"kind": "repair_junction", "room_id": "eng_01",
			"steps": [{"step_id": "primary_coupling"}, {"step_id": "secondary_coupling"}],
		},
		{"id": "obj_reach_goal", "sequence": 3, "type": "interact", "kind": "single", "room_id": "bridge_01"},
	]
	var c = ControllerScript.create()
	if c == null:
		_fail("create returned null")
		return
	c.configure(specs)
	if c.is_cleared():
		_fail("cleared should be false before reach_goal")
		return

	# Complete a salvage objective.
	if not c.complete(1):
		_fail("complete(1) should return true")
		return
	if not c.is_objective_complete(1):
		_fail("objective 1 should be complete")
		return
	if c.is_cleared():
		_fail("cleared should still be false after a salvage completion")
		return
	# Duplicate completion is idempotent (no double-credit).
	if c.complete(1):
		_fail("complete(1) again should return false (already complete)")
		return

	# A boarded repair junction preserves every authored step. The first
	# interaction advances progress but cannot complete the objective.
	if not c.complete(2, "primary_coupling"):
		_fail("first repair-junction step should advance progress")
		return
	if c.is_objective_complete(2):
		_fail("repair junction completed before every authored step")
		return
	var partial: Dictionary = c.get_step_progress(2)
	if int(partial.get("required_steps", 0)) != 2 or int(partial.get("completed_steps", 0)) != 1:
		_fail("repair-junction progress did not preserve authored step count")
		return

	# Complete reach_goal -> cleared.
	if not c.complete(3):
		_fail("complete(3) reach_goal should return true")
		return
	if not c.is_cleared():
		_fail("cleared should be true after reach_goal completion")
		return

	# configure() is idempotent: a second call must NOT reset progress.
	c.configure(specs)
	if not c.is_objective_complete(1) or not c.is_cleared():
		_fail("configure() wiped progress (must be idempotent once configured)")
		return

	# Summary round-trip onto a fresh controller.
	var summary: Dictionary = c.get_summary()
	var restored = ControllerScript.create()
	if not restored.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if not restored.is_objective_complete(1):
		_fail("restored: objective 1 not complete")
		return
	if not restored.is_cleared():
		_fail("restored: cleared not preserved")
		return
	# A restored controller can still complete the remaining authored step.
	if not restored.complete(2, "secondary_coupling"):
		_fail("restored: remaining repair-junction step should succeed")
		return
	if not restored.is_objective_complete(2):
		_fail("restored: objective 2 not complete after completion")
		return

	# Legacy saves authored before junction step counts were materialized can
	# contain required_steps=1. Reconfiguration must migrate that record to the
	# current authored count without losing already-completed step IDs.
	var legacy = ControllerScript.create()
	legacy.apply_summary({
		"progress": {
			2: {
				"objective_type": "restore_systems",
				"required_steps": 1,
				"completed_step_ids": ["primary_coupling"],
				"complete": true,
			},
		},
	})
	legacy.configure(specs)
	var migrated: Dictionary = legacy.get_step_progress(2)
	if int(migrated.get("required_steps", 0)) != 2 \
			or int(migrated.get("completed_steps", 0)) != 1 \
			or bool(migrated.get("complete", true)):
		_fail("legacy repair-junction summary was not reconciled to authored steps")
		return
	if not legacy.complete(2, "secondary_coupling") or not legacy.is_objective_complete(2):
		_fail("migrated repair junction did not complete on its remaining authored step")
		return

	# apply_summary rejects null/empty.
	if restored.apply_summary(null) or restored.apply_summary({}):
		_fail("apply_summary should reject null/empty")
		return

	print("DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true legacy_step_migration=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("DERELICT OBJECTIVE CONTROLLER FAIL reason=%s" % reason)
	quit(1)
