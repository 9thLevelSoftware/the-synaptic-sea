extends SceneTree

## Unit smoke for ShipInstance: construction, summary round-trip, Phase-5 stubs.

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _initialize() -> void:
	var bp = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, 4242)
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), bp.condition, bp.seed_value)

	var inst = ShipInstanceScript.create("ship_test", "3:1:2", bp, mgr, null)
	if inst == null:
		_fail("create returned null")
		return

	# Phase-5 stub fields exist and default empty/null.
	if inst.parent_ship != null:
		_fail("parent_ship should default null")
		return
	if not (inst.docked_ships is Array and inst.docked_ships.is_empty()):
		_fail("docked_ships should default empty array")
		return
	if not (inst.docking_ports is Array and inst.docking_ports.is_empty()):
		_fail("docking_ports should default empty array")
		return

	# Summary round-trip.
	var summary: Dictionary = inst.get_summary()
	if String(summary.get("ship_id", "")) != "ship_test":
		_fail("summary ship_id wrong")
		return
	if String(summary.get("marker_id", "")) != "3:1:2":
		_fail("summary marker_id wrong")
		return

	var rebuilt = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), ShipSystemsManagerScript.new(), null)
	if not rebuilt.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if rebuilt.ship_id != "ship_test" or rebuilt.marker_id != "3:1:2":
		_fail("apply_summary did not restore ids")
		return
	if int(rebuilt.blueprint.size) != int(ShipBlueprintScript.Size.SMALL):
		_fail("apply_summary did not restore blueprint size")
		return
	if int(rebuilt.blueprint.condition) != int(ShipBlueprintScript.Condition.DAMAGED):
		_fail("apply_summary did not restore blueprint condition")
		return
	if int(rebuilt.blueprint.seed_value) != 4242:
		_fail("apply_summary did not restore blueprint seed")
		return

	# apply_summary rejects non-dict / empty.
	if rebuilt.apply_summary(null) or rebuilt.apply_summary({}):
		_fail("apply_summary should reject null/empty")
		return

	print("SHIP INSTANCE PASS round_trip=true stubs_present=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP INSTANCE FAIL reason=%s" % reason)
	quit(1)
