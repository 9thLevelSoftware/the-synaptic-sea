extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _count_damaged(mgr) -> int:
	var n: int = 0
	for sid in mgr.system_order:
		for sub in mgr.get_system(sid).subcomponents:
			if sub.health < sub.operational_threshold:
				n += 1
	return n

func _initialize() -> void:
	var defs: Dictionary = ManagerScript.new().load_definitions()
	if defs.is_empty():
		push_error("SHIP SYSTEMS MANAGER FAIL could not load definitions")
		quit(1)
		return

	# --- Determinism + condition severity ---
	var pristine = ManagerScript.new()
	pristine.configure(defs, 0, 4242)
	if _count_damaged(pristine) != 0:
		push_error("SHIP SYSTEMS MANAGER FAIL pristine has damage: %d" % _count_damaged(pristine))
		quit(1)
		return

	var damaged_a = ManagerScript.new()
	damaged_a.configure(defs, 1, 4242)
	var damaged_b = ManagerScript.new()
	damaged_b.configure(defs, 1, 4242)
	if damaged_a.get_summary_health_list() != damaged_b.get_summary_health_list():
		push_error("SHIP SYSTEMS MANAGER FAIL same seed/condition not deterministic")
		quit(1)
		return
	var damaged_count: int = _count_damaged(damaged_a)
	if damaged_count < 1:
		push_error("SHIP SYSTEMS MANAGER FAIL damaged condition produced no damage")
		quit(1)
		return

	var wrecked = ManagerScript.new()
	wrecked.configure(defs, 2, 4242)
	if _count_damaged(wrecked) < damaged_count:
		push_error("SHIP SYSTEMS MANAGER FAIL wrecked(%d) not >= damaged(%d)" % [_count_damaged(wrecked), damaged_count])
		quit(1)
		return

	# --- Dependency cascade ---
	var mgr = ManagerScript.new()
	mgr.configure(defs, 0, 1)  # pristine: everything operational
	for sid in ["power", "life_support", "gravity", "navigation", "propulsion", "scanners"]:
		if not mgr.is_operational(sid):
			push_error("SHIP SYSTEMS MANAGER FAIL pristine %s not operational" % sid)
			quit(1)
			return

	# Break Power -> all dependents cascade offline.
	mgr.get_system("power").get_subcomponent("reactor_core").health = 0.0
	if mgr.is_operational("power"):
		push_error("SHIP SYSTEMS MANAGER FAIL power still operational after break")
		quit(1)
		return
	for sid in ["life_support", "gravity", "navigation", "propulsion", "scanners"]:
		if mgr.is_operational(sid):
			push_error("SHIP SYSTEMS MANAGER FAIL %s operational while power down" % sid)
			quit(1)
			return

	# Repair Power back -> dependents that are themselves healthy come back.
	mgr.get_system("power").get_subcomponent("reactor_core").health = 1.0
	if not mgr.is_operational("life_support"):
		push_error("SHIP SYSTEMS MANAGER FAIL life_support did not recover after power restored")
		quit(1)
		return

	# Break navigation -> scanners + propulsion go offline (need navigation), but gravity stays up.
	mgr.get_system("navigation").get_subcomponent("nav_computer").health = 0.0
	if mgr.is_operational("scanners") or mgr.is_operational("propulsion"):
		push_error("SHIP SYSTEMS MANAGER FAIL scanners/propulsion up while navigation down")
		quit(1)
		return
	if not mgr.is_operational("gravity"):
		push_error("SHIP SYSTEMS MANAGER FAIL gravity wrongly offline (only deps on power)")
		quit(1)
		return

	print("SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok")
	quit(0)
