extends SceneTree

const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	# Damaged part with one required part, one tool, min skill 2.
	var sub := SubScript.new("reactor_core", ["power_cell"], ["welder"], 2, 10.0, 0.5)
	sub.health = 0.2

	if sub.is_functional():
		push_error("SHIP SUBCOMPONENT FAIL damaged part reports functional")
		quit(1)
		return

	# Missing the required part.
	var r1: Dictionary = sub.repair([], ["welder"], 5)
	if r1.get("success", true) or str(r1.get("reason", "")) != "missing_parts":
		push_error("SHIP SUBCOMPONENT FAIL expected missing_parts, got %s" % str(r1))
		quit(1)
		return

	# Missing the required tool.
	var r2: Dictionary = sub.repair(["power_cell"], [], 5)
	if r2.get("success", true) or str(r2.get("reason", "")) != "missing_tools":
		push_error("SHIP SUBCOMPONENT FAIL expected missing_tools, got %s" % str(r2))
		quit(1)
		return

	# Under-skill.
	var r3: Dictionary = sub.repair(["power_cell"], ["welder"], 1)
	if r3.get("success", true) or str(r3.get("reason", "")) != "insufficient_skill":
		push_error("SHIP SUBCOMPONENT FAIL expected insufficient_skill, got %s" % str(r3))
		quit(1)
		return

	# Full requirements met -> success, health restored, faster with higher skill.
	var r4: Dictionary = sub.repair(["power_cell"], ["welder"], 4)
	if not r4.get("success", false) or str(r4.get("reason", "")) != "ok":
		push_error("SHIP SUBCOMPONENT FAIL expected ok success, got %s" % str(r4))
		quit(1)
		return
	if absf(sub.health - 1.0) > 0.0001:
		push_error("SHIP SUBCOMPONENT FAIL health not restored: %f" % sub.health)
		quit(1)
		return
	if float(r4.get("seconds", 99.0)) >= 10.0:
		push_error("SHIP SUBCOMPONENT FAIL skill 4 should be faster than base 10s, got %f" % float(r4.get("seconds", 99.0)))
		quit(1)
		return

	# Repairing an already-functional part is a no-op rejection.
	var r5: Dictionary = sub.repair(["power_cell"], ["welder"], 4)
	if r5.get("success", true) or str(r5.get("reason", "")) != "already_functional":
		push_error("SHIP SUBCOMPONENT FAIL expected already_functional, got %s" % str(r5))
		quit(1)
		return

	# Summary round-trip.
	var damaged := SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5)
	damaged.health = 0.3
	var summary: Dictionary = damaged.get_summary()
	var restored := SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5)
	if not restored.apply_summary(summary):
		push_error("SHIP SUBCOMPONENT FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(restored.health - 0.3) > 0.0001:
		push_error("SHIP SUBCOMPONENT FAIL round-trip health mismatch: %f" % restored.health)
		quit(1)
		return
	if restored.apply_summary({}):
		push_error("SHIP SUBCOMPONENT FAIL empty summary should be rejected")
		quit(1)
		return

	print("SHIP SUBCOMPONENT PASS repair_reasons=ok skill_scaling=ok round_trip=ok")
	quit(0)
