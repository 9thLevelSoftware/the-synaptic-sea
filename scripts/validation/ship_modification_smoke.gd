extends SceneTree

## PKG-D2.6: ship component install + power budget + plating bonus.
## Marker: SHIP MODIFICATION PASS install=true power=true uninstall=true plating=true

const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")


func _initialize() -> void:
	var mod = ShipModificationStateScript.new()
	mod.configure({})
	if mod.power_supply < 50.0:
		_fail("budget load should set supply"); return
	if mod.power_demand_baseline <= 0.0:
		_fail("baseline demand from budget tables"); return

	var inv: Dictionary = {"reactor_console": 2, "machinery_block": 1, "hull_plate_kit": 1}
	# Install within budget
	var r1: Dictionary = mod.install("hub_wall_0", "reactor_console", "reactor_console", inv, 8.0, 15.0, "derelict_a")
	if not bool(r1.get("ok", false)):
		_fail("install 1: %s" % str(r1.get("reason", ""))); return
	if mod.installed_count() != 1:
		_fail("count"); return
	if int(inv.get("reactor_console", 0)) != 1:
		_fail("inventory consume"); return

	# Over-budget install fails
	var huge: Dictionary = mod.install("hub_wall_1", "machinery_block", "machinery_block", inv, 9999.0, 25.0)
	if bool(huge.get("ok", false)):
		_fail("should reject over budget"); return
	if str(huge.get("reason", "")) != "power_budget":
		_fail("expected power_budget reason"); return

	# Second install OK
	var r2: Dictionary = mod.install("hub_center_0", "machinery_block", "machinery_block", inv, 10.0, 25.0, "captured")
	if not bool(r2.get("ok", false)):
		_fail("install 2"); return
	if not mod.is_power_budget_ok():
		_fail("power should still be ok"); return

	# Plating
	var plate: Dictionary = mod.install("hull_plate_0", "hull_plating", "hull_plate_kit", inv, 0.0, 5.0, "salvage", true)
	if not bool(plate.get("ok", false)):
		_fail("plating install"); return
	if mod.hull_plating_bonus < 0.05:
		_fail("plating bonus"); return

	# Uninstall returns item
	var u: Dictionary = mod.uninstall("hub_wall_0", inv)
	if not bool(u.get("ok", false)):
		_fail("uninstall"); return
	if int(inv.get("reactor_console", 0)) < 1:
		_fail("item returned"); return
	if mod.installed_count() != 2:
		_fail("count after uninstall"); return

	# Round-trip
	var snap: Dictionary = mod.get_summary()
	var mod2 = ShipModificationStateScript.new()
	mod2.apply_summary(snap)
	if mod2.installed_count() != mod.installed_count():
		_fail("round-trip count"); return
	if absf(mod2.total_power_draw() - mod.total_power_draw()) > 0.01:
		_fail("round-trip power"); return

	print("SHIP MODIFICATION PASS install=true power=true uninstall=true plating=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MODIFICATION FAIL: %s" % msg)
	quit(1)
