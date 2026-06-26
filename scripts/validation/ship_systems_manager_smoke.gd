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

	# Repair Power back -> all five dependents that are themselves healthy come back.
	mgr.get_system("power").get_subcomponent("reactor_core").health = 1.0
	for sid in ["life_support", "gravity", "navigation", "propulsion", "scanners"]:
		if not mgr.is_operational(sid):
			push_error("SHIP SYSTEMS MANAGER FAIL %s did not recover after power restored" % sid)
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

	# --- advance(): life support drains oxygen only when offline ---
	var ship = ManagerScript.new()
	ship.configure(defs, 0, 1)  # pristine, all operational
	var ls = ship.get_system("life_support")
	var oxy_start: float = ls.get_oxygen_state().oxygen
	ship.advance(1.0)  # all operational -> no drain
	if ls.get_oxygen_state().oxygen < oxy_start:
		push_error("SHIP SYSTEMS MANAGER FAIL operational life support drained oxygen")
		quit(1)
		return
	# Knock out power so life support cascades offline, then advance.
	ship.get_system("power").get_subcomponent("reactor_core").health = 0.0
	var oxy_before: float = ls.get_oxygen_state().oxygen
	ship.advance(1.0)
	if ls.get_oxygen_state().oxygen >= oxy_before:
		push_error("SHIP SYSTEMS MANAGER FAIL offline life support did not drain oxygen")
		quit(1)
		return

	# --- repair() routes to the subcomponent and reports reasons ---
	var unknown_sys: Dictionary = ship.repair("warp", "x", [], [], 9)
	if str(unknown_sys.get("reason", "")) != "unknown_system":
		push_error("SHIP SYSTEMS MANAGER FAIL expected unknown_system, got %s" % str(unknown_sys))
		quit(1)
		return
	var unknown_sub: Dictionary = ship.repair("power", "nope", [], [], 9)
	if str(unknown_sub.get("reason", "")) != "unknown_subcomponent":
		push_error("SHIP SYSTEMS MANAGER FAIL expected unknown_subcomponent, got %s" % str(unknown_sub))
		quit(1)
		return
	# reactor_core needs reactor_core part + plasma_cutter tool + skill 4.
	var bad: Dictionary = ship.repair("power", "reactor_core", [], [], 9)
	if bad.get("success", true):
		push_error("SHIP SYSTEMS MANAGER FAIL repair succeeded without parts/tools")
		quit(1)
		return
	var ok: Dictionary = ship.repair("power", "reactor_core", ["reactor_core"], ["plasma_cutter"], 4)
	if not ok.get("success", false):
		push_error("SHIP SYSTEMS MANAGER FAIL valid repair failed: %s" % str(ok))
		quit(1)
		return
	if not ship.is_operational("power"):
		push_error("SHIP SYSTEMS MANAGER FAIL power not operational after repair")
		quit(1)
		return

	# --- status summary shape ---
	var status: Dictionary = ship.get_status_summary()
	if typeof(status.get("power", null)) != TYPE_DICTIONARY or not status["power"].has("operational"):
		push_error("SHIP SYSTEMS MANAGER FAIL status summary malformed")
		quit(1)
		return

	# --- full manager round-trip ---
	var src = ManagerScript.new()
	src.configure(defs, 1, 777)  # some damage
	var snap: Dictionary = src.get_summary()
	var dst = ManagerScript.new()
	dst.configure(defs, 0, 777)  # pristine, different state
	if not dst.apply_summary(snap):
		push_error("SHIP SYSTEMS MANAGER FAIL apply_summary reported no change")
		quit(1)
		return
	if dst.get_summary_health_list() != src.get_summary_health_list():
		push_error("SHIP SYSTEMS MANAGER FAIL round-trip health list mismatch")
		quit(1)
		return
	if dst.apply_summary({}):
		push_error("SHIP SYSTEMS MANAGER FAIL empty summary should be rejected")
		quit(1)
		return

	# Malformed/corrupt snapshot: a known system id mapping to a non-Dictionary
	# value must be rejected gracefully (no runtime type crash, no change).
	if dst.apply_summary({"systems": {"power": []}}):
		push_error("SHIP SYSTEMS MANAGER FAIL malformed nested system summary should be rejected")
		quit(1)
		return

	print("SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok advance=ok repair=ok round_trip=ok malformed_rejected=ok")
	quit(0)
