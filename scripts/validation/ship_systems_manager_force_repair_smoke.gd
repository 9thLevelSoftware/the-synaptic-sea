extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _initialize() -> void:
	var mgr = ManagerScript.new()
	mgr.configure(mgr.load_definitions(), 2, 17)  # WRECKED, seed 17 -> guarantees breakage

	# Break a known subcomponent, then force_repair it.
	var sub = mgr.get_system("power").get_subcomponent("battery_cells")
	sub.health = 0.0
	if sub.is_functional():
		_fail("setup: battery_cells should be non-functional at health 0.0")
		return

	if not mgr.force_repair("power", "battery_cells"):
		_fail("force_repair(power, battery_cells) returned false")
		return
	if not mgr.get_system("power").get_subcomponent("battery_cells").is_functional():
		_fail("battery_cells not functional after force_repair")
		return
	if absf(mgr.get_system("power").get_subcomponent("battery_cells").health - 1.0) > 0.0001:
		_fail("battery_cells health != 1.0 after force_repair")
		return

	# Unknown ids must return false, not crash.
	if mgr.force_repair("nope", "battery_cells"):
		_fail("force_repair(unknown system) should return false")
		return
	if mgr.force_repair("power", "nope"):
		_fail("force_repair(unknown subcomponent) should return false")
		return

	print("SHIP SYSTEMS MANAGER FORCE REPAIR PASS health=1.0 unknown_rejected=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS MANAGER FORCE REPAIR FAIL reason=%s" % reason)
	quit(1)
