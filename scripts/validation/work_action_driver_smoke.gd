extends SceneTree

## PKG-B2.2b: WorkActionDriver hold-to-work chain — yields, noise, XP, cart overload, interrupt.
## Marker: WORK ACTION DRIVER PASS cut=true noise=true yield=true interrupt=true overload=true

const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


func _initialize() -> void:
	var driver = WorkActionDriverScript.new()
	driver.configure({"cart_capacity": 100.0, "cart_mass": 0.0})

	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_a", "wall_straight_1x1", {}, "eng")

	# --- Cut sealed wall ---
	var inv: Dictionary = {}
	if not driver.start_action("cut_wall", "eng/wall_a", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": inv,
	}):
		_fail("cut start"); return
	if not driver.is_working():
		_fail("should be working"); return
	# Interrupt mid-work
	driver.tick(0.5, {})
	if driver.progress_ratio() <= 0.0:
		_fail("progress"); return
	driver.tick(0.1, {"damaged": true})
	if driver.get_status() != WorkActionStateScript.STATUS_INTERRUPTED:
		_fail("expected interrupt on damage"); return
	var bad = driver.complete(map, inv)
	if bool(bad.get("ok", false)):
		_fail("interrupted should not complete"); return

	# Full cut
	driver.reset()
	if not driver.start_action("cut_wall", "eng/wall_a", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	}):
		_fail("cut restart"); return
	driver.tick(20.0, {"work_speed_mult": 1.0})
	if driver.get_status() != WorkActionStateScript.STATUS_COMPLETED:
		_fail("expected complete"); return
	var res: Dictionary = driver.complete(map, inv)
	if not bool(res.get("ok", false)):
		_fail("resolve cut: %s" % str(res.get("reason", ""))); return
	if map.get_state("eng/wall_a") != ModuleIntegrityStateScript.STATE_DESTROYED:
		_fail("cut should destroy wall"); return
	if int(inv.get("scrap_metal", 0)) < 1:
		_fail("cut should yield scrap"); return
	if driver.last_noise_pulse < 0.5:
		_fail("cut should be noisy"); return

	# Noise into detection
	var det = DetectionStateScript.new()
	det.configure({"noise_level": 0.1})
	driver.apply_noise_to_detection(det)
	if det.noise_level < 0.5:
		_fail("noise should raise detection noise_level"); return

	# XP event present
	if driver.last_xp_event.is_empty():
		_fail("xp_event required"); return

	# Cart overload blocks further strip starts
	driver.cart_mass = 200.0
	driver.overloaded = true
	if driver.start_action("cut_wall", "eng/wall_b", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	}):
		_fail("overloaded cart should block cut start"); return

	# Weld still allowed when overloaded
	map.ensure_module("eng/wall_b", "wall_straight_1x1", {}, "eng")
	map.apply_damage("eng/wall_b", 0.4, "wall_straight_1x1")
	if not driver.start_action("weld_patch", "eng/wall_b", {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 0,
		"inventory": {"hull_plate": 1},
	}):
		_fail("weld should start even if cart overloaded"); return
	driver.tick(20.0, {})
	var inv2: Dictionary = {"hull_plate": 1}
	var res2: Dictionary = driver.complete(map, inv2)
	if not bool(res2.get("ok", false)):
		_fail("weld complete"); return

	# Persistence mid-work
	driver.reset()
	driver.configure({})
	driver.start_action("pry_panel", "panel_1", {
		"tool_class": "prybar", "skill_id": "salvage", "skill_level": 0, "inventory": {},
	})
	driver.tick(1.0, {})
	var snap: Dictionary = driver.get_persistence_summary()
	var d2 = WorkActionDriverScript.new()
	d2.configure({})
	d2.apply_persistence_summary(snap)
	if d2.get_status() != WorkActionStateScript.STATUS_ACTIVE:
		_fail("persist mid-work"); return

	print("WORK ACTION DRIVER PASS cut=true noise=true yield=true interrupt=true overload=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK ACTION DRIVER FAIL: %s" % msg)
	quit(1)
