extends SceneTree

## Pure-model smoke: gated repair consumes the right parts, respects a dependency
## cascade, and rejects on missing parts/tools/skill. No scene tree.

const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _initialize() -> void:
	var repaired: bool = _test_repair_and_consume()
	var cascade: bool = _test_cascade()
	var rejects: bool = _test_rejects()
	if repaired and cascade and rejects:
		print("REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true")
	else:
		push_error("REPAIR CONSUME FAIL repaired=%s cascade=%s rejects=%s" % [
			str(repaired), str(cascade), str(rejects)])
	quit(0 if (repaired and cascade and rejects) else 1)

func _fresh_manager() -> Variant:
	var mgr = ShipSystemsManagerScript.new()
	# condition WRECKED (2), fixed seed → deterministic damage incl. broken subs.
	mgr.configure(mgr.load_definitions(), 2, 99)
	return mgr

func _test_repair_and_consume() -> bool:
	var mgr = _fresh_manager()
	# Force a clean scenario: break exactly battery_cells (power), everything else healthy,
	# so the repair target is deterministic and its deps are satisfied.
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	mgr.get_system("power").get_subcomponent("battery_cells").health = 0.1  # needs power_cell, skill 1, no tool
	var inv = InventoryStateScript.new()
	inv.add_item("power_cell", 2)
	var result: Dictionary = mgr.repair_with_inventory("power", "battery_cells", inv, 3)
	if not bool(result.get("success", false)):
		return false
	if not mgr.get_system("power").get_subcomponent("battery_cells").is_functional():
		return false
	# Exactly one power_cell consumed.
	if inv.get_quantity("power_cell") != 1:
		return false
	return true

func _test_cascade() -> bool:
	# propulsion depends on power+navigation. With those operational and propulsion's
	# subcomponents healthy except nav_linkage, repairing nav_linkage flips propulsion operational.
	var mgr = _fresh_manager()
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	mgr.get_system("propulsion").get_subcomponent("nav_linkage").health = 0.1  # circuit_board, skill 2, no tool
	if mgr.is_operational("propulsion"):
		return false  # broken before repair
	var inv = InventoryStateScript.new()
	inv.add_item("circuit_board", 1)
	var result: Dictionary = mgr.repair_with_inventory("propulsion", "nav_linkage", inv, 2)
	if not bool(result.get("success", false)):
		return false
	return mgr.is_operational("propulsion")  # operational after, via cascade resolve

func _test_rejects() -> bool:
	var mgr = _fresh_manager()
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	# thruster_array: needs thruster_nozzle + plasma_cutter + skill 4.
	mgr.get_system("propulsion").get_subcomponent("thruster_array").health = 0.1
	var empty = InventoryStateScript.new()
	# Missing parts:
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", empty, 5).get("success", true)):
		return false
	# Has part but missing tool:
	var inv = InventoryStateScript.new()
	inv.add_item("thruster_nozzle", 1)
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", inv, 5).get("success", true)):
		return false
	# Has part + tool but insufficient skill (min_skill 4, skill 1):
	inv.add_item("plasma_cutter", 1)
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", inv, 1).get("success", true)):
		return false
	# Nothing consumed on failure:
	if inv.get_quantity("thruster_nozzle") != 1:
		return false
	# Unknown ids:
	if str(mgr.repair_with_inventory("nope", "nope", inv, 9).get("reason", "")) != "unknown_system":
		return false
	return true
