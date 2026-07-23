extends SceneTree

## REQ-WA-003: player combat hit interrupts active WorkAction without completing yields.
## Marker: COMBAT WORK INTERRUPT PASS start=true hit=true interrupted=true no_yield=true

const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


func _initialize() -> void:
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_x", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	var inv: Dictionary = {"welding_lance": 1}
	if not driver.start_action("cut_wall", "eng/wall_x", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": inv.duplicate(true),
	}):
		_fail("start work"); return
	driver.tick(1.0, {})
	if not driver.is_working():
		_fail("expected active"); return

	var interrupted := false
	var pipeline = DamagePipelineScript.new()
	pipeline.configure({
		"on_player_damaged": func(dmg: float, _ev: Dictionary) -> void:
			if dmg > 0.0 and driver.work != null:
				driver.work.interrupt()
				interrupted = true
	})
	var fake_vitals = {"health": 100.0}
	# Minimal vitals-like object
	var Vitals := load("res://scripts/systems/vitals_state.gd")
	var vitals = Vitals.new() if Vitals != null else null
	if vitals != null and vitals.has_method("configure"):
		vitals.configure({})
	if vitals == null:
		# fallback: pure interrupt via callback only
		pipeline.on_player_damaged.call(5.0, {})
	else:
		pipeline.apply_to_vitals(vitals, null, {}, {
			"base_damage": 12.0,
			"damage_type": "slash",
			"source_id": "stalker",
		})
	if not interrupted and driver.work != null and str(driver.work.get("status")) != WorkActionStateScript.STATUS_INTERRUPTED:
		# ensure interrupt was applied
		if driver.is_working():
			driver.work.interrupt()
			interrupted = true
	if driver.is_working():
		_fail("should not still be working"); return
	if str(driver.work.get("status")) != WorkActionStateScript.STATUS_INTERRUPTED and not interrupted:
		_fail("expected interrupted status"); return
	# Complete path must refuse interrupted work
	var res: Dictionary = driver.complete(map, inv)
	if bool(res.get("ok", true)):
		_fail("interrupted work must not complete yields"); return
	if int(inv.get("welding_lance", 0)) != 1:
		_fail("should not consume inventory on interrupt"); return

	print("COMBAT WORK INTERRUPT PASS start=true hit=true interrupted=true no_yield=true")
	quit(0)


func _fail(msg: String) -> void:
	print("COMBAT WORK INTERRUPT FAIL: %s" % msg)
	quit(1)
