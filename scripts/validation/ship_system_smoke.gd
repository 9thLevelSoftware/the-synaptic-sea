extends SceneTree

const SystemScript := preload("res://scripts/systems/ship_system.gd")
const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	var deps: Array[String] = ["power"]
	var system = SystemScript.new("life_support", deps)
	system.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	system.add_subcomponent(SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5))

	# All healthy -> self functional, health 1.0.
	if not system.is_self_functional():
		push_error("SHIP SYSTEM FAIL healthy system not self_functional")
		quit(1)
		return
	if absf(system.health() - 1.0) > 0.0001:
		push_error("SHIP SYSTEM FAIL healthy health != 1.0: %f" % system.health())
		quit(1)
		return

	# Break one subcomponent -> not self functional, health is the weakest link.
	system.get_subcomponent("co2_scrubber").health = 0.1
	if system.is_self_functional():
		push_error("SHIP SYSTEM FAIL broken subcomponent still self_functional")
		quit(1)
		return
	if absf(system.health() - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL health not weakest link: %f" % system.health())
		quit(1)
		return

	# get_subcomponent returns null for unknown id.
	if system.get_subcomponent("nope") != null:
		push_error("SHIP SYSTEM FAIL unknown subcomponent should be null")
		quit(1)
		return

	# dependency ids preserved.
	if system.dependency_ids != ["power"]:
		push_error("SHIP SYSTEM FAIL dependency_ids mismatch: %s" % str(system.dependency_ids))
		quit(1)
		return

	# base advance is a no-op (does not raise, does not change health).
	system.advance(1.0, false)
	if absf(system.health() - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL base advance changed health")
		quit(1)
		return

	# Round-trip: damaged healths survive get_summary -> apply_summary.
	var summary: Dictionary = system.get_summary()
	var restored = SystemScript.new("life_support", deps)
	restored.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	restored.add_subcomponent(SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5))
	if not restored.apply_summary(summary):
		push_error("SHIP SYSTEM FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(restored.get_subcomponent("co2_scrubber").health - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL round-trip subcomponent health mismatch")
		quit(1)
		return

	print("SHIP SYSTEM PASS health=weakest_link self_functional=ok advance_noop=ok round_trip=ok")
	quit(0)
