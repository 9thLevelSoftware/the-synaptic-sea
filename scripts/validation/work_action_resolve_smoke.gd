extends SceneTree

## PKG-B2.2b: WorkAction completion resolves into module damage + yields + noise/XP.
## Marker: WORK ACTION RESOLVE PASS cut=true weld=true yields=true noise=true

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionResolverScript := preload("res://scripts/systems/work_action_resolver.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")


func _initialize() -> void:
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("catalog load")
		return
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_a", "wall_straight_1x1", {}, "eng")

	# Cut destroys wall
	var cut = WorkActionStateScript.new()
	cut.configure_action("cut_wall", cat.get_action("cut_wall"))
	var ctx: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	}
	if not cut.start("eng/wall_a", ctx):
		_fail("cut start")
		return
	cut.tick(10.0, {})
	var res: Dictionary = WorkActionResolverScript.resolve_completion(cut, map, "eng/wall_a")
	if not bool(res.get("ok", false)):
		_fail("cut resolve failed: %s" % str(res.get("reason", "")))
		return
	if map.get_state("eng/wall_a") != ModuleIntegrityStateScript.STATE_DESTROYED:
		_fail("cut should destroy wall, got %s" % map.get_state("eng/wall_a"))
		return
	if not bool(res.get("nav_gap", false)) or not bool(res.get("atmosphere_link", false)):
		_fail("destroyed wall should open nav + atmosphere")
		return
	if float(res.get("noise", 0.0)) < 0.5:
		_fail("cut should be noisy")
		return
	if str(res.get("xp_event", "")).is_empty():
		_fail("xp_event required")
		return
	var inv: Dictionary = {}
	WorkActionResolverScript.apply_yields_to_inventory(inv, res.get("yields", {}))
	if int(inv.get("scrap_metal", 0)) < 1:
		_fail("cut should yield scrap into inventory")
		return

	# Weld repairs a damaged wall (needs plate)
	map.ensure_module("eng/wall_b", "wall_straight_1x1", {}, "eng")
	map.apply_damage("eng/wall_b", 0.4, "wall_straight_1x1")
	var before: String = map.get_state("eng/wall_b")
	var weld = WorkActionStateScript.new()
	weld.configure_action("weld_patch", cat.get_action("weld_patch"))
	var inv2: Dictionary = {"hull_plate": 1}
	var ctx2: Dictionary = {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 0,
		"inventory": inv2,
	}
	if not weld.start("eng/wall_b", ctx2):
		_fail("weld start")
		return
	if not WorkActionResolverScript.consume_from_inventory(inv2, weld.materials_consumed()):
		_fail("consume plate")
		return
	weld.tick(10.0, {})
	var res2: Dictionary = WorkActionResolverScript.resolve_completion(weld, map, "eng/wall_b")
	if not bool(res2.get("ok", false)):
		_fail("weld resolve")
		return
	# After repair integrity should improve (state may stay damaged or go intact)
	var after_m = map.get_module("eng/wall_b")
	if after_m == null:
		_fail("wall_b missing")
		return
	if float(after_m.get("integrity")) <= 0.6:
		_fail("weld should restore integrity above damaged threshold residual")
		return

	print("WORK ACTION RESOLVE PASS cut=true weld=true yields=true noise=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WORK ACTION RESOLVE FAIL: %s" % msg)
	quit(1)
