extends SceneTree

## PKG-B2.2a: WorkAction catalog + pure progress/interrupt/gates.
## Marker: WORK ACTION STATE PASS catalog=true gates=true progress=true interrupt=true yield=true

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


func _initialize() -> void:
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("catalog load_default failed")
		return
	if cat.action_count() < 6:
		_fail("expected >=6 actions, got %d" % cat.action_count())
		return
	for needed in ["cut_wall", "unbolt_component", "weld_patch", "patch_breach", "pry_panel", "splice_conduit"]:
		if not cat.has_action(needed):
			_fail("missing action %s" % needed)
			return

	var cut_def: Dictionary = cat.get_action("cut_wall")
	var work = WorkActionStateScript.new()
	work.configure_action("cut_wall", cut_def)

	# Gate: wrong tool
	if work.can_start({"tool_class": "wrench", "skill_id": "salvage", "skill_level": 5, "inventory": {}}):
		_fail("cut should require welding_lance")
		return
	if work.block_reason != "tool":
		_fail("expected tool block")
		return

	# Gate: materials for weld_patch
	var weld = WorkActionStateScript.new()
	weld.configure_action("weld_patch", cat.get_action("weld_patch"))
	if weld.can_start({"tool_class": "welding_lance", "skill_id": "repair", "skill_level": 0, "inventory": {}}):
		_fail("weld_patch needs hull_plate")
		return

	var ctx_ok: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	}
	if not work.start("wall_01", ctx_ok):
		_fail("cut should start")
		return
	if work.status != WorkActionStateScript.STATUS_ACTIVE:
		_fail("status active")
		return

	# Progress half
	work.tick(2.0, {})
	if work.progress_ratio() < 0.4 or work.progress_ratio() > 0.6:
		_fail("expected ~0.5 progress, got %s" % str(work.progress_ratio()))
		return

	# Interrupt on damage
	var st: String = work.tick(0.1, {"damaged": true})
	if st != WorkActionStateScript.STATUS_INTERRUPTED:
		_fail("expected interrupt on damage")
		return

	# Complete without interrupt
	var work2 = WorkActionStateScript.new()
	work2.configure_action("cut_wall", cut_def)
	work2.start("wall_02", ctx_ok)
	work2.tick(10.0, {"work_speed_mult": 1.0})
	if work2.status != WorkActionStateScript.STATUS_COMPLETED:
		_fail("expected complete")
		return
	if work2.noise() < 0.5:
		_fail("cut should be noisy")
		return
	var yielded: Dictionary = work2.materials_yielded()
	if int(yielded.get("scrap_metal", 0)) < 1:
		_fail("cut should yield scrap")
		return
	if work2.xp_event().is_empty():
		_fail("xp_event required")
		return

	# Snapshot round-trip mid-work
	var work3 = WorkActionStateScript.new()
	work3.configure_action("pry_panel", cat.get_action("pry_panel"))
	work3.start("panel_a", {
		"tool_class": "prybar", "skill_id": "salvage", "skill_level": 0, "inventory": {}
	})
	work3.tick(1.0, {})
	var snap: Dictionary = work3.get_summary()
	var work4 = WorkActionStateScript.new()
	work4.apply_summary(snap)
	if absf(work4.progress - work3.progress) > 0.001 or work4.status != work3.status:
		_fail("summary round-trip")
		return

	print("WORK ACTION STATE PASS catalog=true gates=true progress=true interrupt=true yield=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK ACTION STATE FAIL: %s" % msg)
	quit(1)
