extends SceneTree

## Unit smoke for DerelictObjectiveController: configure from generated specs,
## complete salvage + reach_goal, cleared semantics, summary round-trip.

const ControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")

func _initialize() -> void:
	var specs: Array = [
		{"id": "obj_salvage_cargo_01", "sequence": 1, "type": "salvage", "kind": "single", "room_id": "cargo_01"},
		{"id": "obj_salvage_eng_01", "sequence": 2, "type": "salvage", "kind": "single", "room_id": "eng_01"},
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
	# A restored controller can still complete a remaining objective.
	if not restored.complete(2):
		_fail("restored: complete(2) should succeed")
		return
	if not restored.is_objective_complete(2):
		_fail("restored: objective 2 not complete after completion")
		return

	# apply_summary rejects null/empty.
	if restored.apply_summary(null) or restored.apply_summary({}):
		_fail("apply_summary should reject null/empty")
		return

	print("DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("DERELICT OBJECTIVE CONTROLLER FAIL reason=%s" % reason)
	quit(1)
