extends SceneTree

## PKG-D2.6: ship component install + power budget + plating bonus.
## Marker: SHIP MODIFICATION PASS install=true power=true uninstall=true plating=true

const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")


func _initialize() -> void:
	var mod = ShipModificationStateScript.new()
	mod.configure({})
	if mod.power_supply < 50.0:
		_fail("budget load should set supply"); return
	if mod.power_demand_baseline <= 0.0:
		_fail("baseline demand from budget tables"); return
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("catalog load"); return
	var layout: Dictionary = {"rooms": [{"id": "eng", "room_role": "engineering", "wall_slots": [
		{"cell": [0, 0], "component_slot_profile_id": "wall_console_mount_v1"},
		{"cell": [0, 1], "component_slot_profile_id": "wall_utility_mount_v1"},
		{"cell": [0, 2], "component_slot_profile_id": "wall_utility_mount_v1"},
	], "center_slots": [{"cell": [1, 0], "component_slot_profile_id": "deck_machinery_mount_v1"}]}]}
	var placement = ComponentPlacementStateScript.new()
	placement.populate(layout, catalog, 42)
	for entry_v in placement.placed.duplicate(true):
		placement.dismount(str((entry_v as Dictionary).get("component_instance_id", "")))
	var slots: Array = placement.get_physical_slot_descriptors("test-ship")
	if not mod.bind_physical_slots("test-ship", slots, catalog, placement):
		_fail("physical slot bind"); return

	var inv: Dictionary = {"reactor_console": 2, "machinery_block": 1, "plating_plate": 1}
	# Install within budget
	var r1: Dictionary = mod.install("eng_wall_0", "reactor_console", "reactor_console", inv, 8.0, 15.0, "test-ship")
	if not bool(r1.get("ok", false)):
		_fail("install 1: %s" % str(r1.get("reason", ""))); return
	if mod.installed_count() != 1:
		_fail("count"); return
	if int(inv.get("reactor_console", 0)) != 1:
		_fail("inventory consume"); return

	# Over-budget install fails
	mod.power_supply = 95.0
	var huge: Dictionary = mod.install("eng_center_0", "machinery_block", "machinery_block", inv, 9999.0, 25.0)
	if bool(huge.get("ok", false)):
		_fail("should reject over budget"); return
	if str(huge.get("reason", "")) != "power_budget":
		_fail("expected power_budget reason"); return

	# Second install OK
	mod.power_supply = 120.0
	var r2: Dictionary = mod.install("eng_center_0", "machinery_block", "machinery_block", inv, 10.0, 25.0, "test-ship")
	if not bool(r2.get("ok", false)):
		_fail("install 2"); return
	if not mod.is_power_budget_ok():
		_fail("power should still be ok"); return

	# Plating
	var plate: Dictionary = mod.install("eng_wall_1", "hull_plating", "plating_plate", inv, 0.0, 5.0, "test-ship", true)
	if not bool(plate.get("ok", false)):
		_fail("plating install"); return
	if mod.hull_plating_bonus < 0.05:
		_fail("plating bonus"); return

	# Uninstall returns item
	var u: Dictionary = mod.uninstall("eng_wall_0", inv)
	if not bool(u.get("ok", false)):
		_fail("uninstall"); return
	if int(inv.get("reactor_console", 0)) < 1:
		_fail("item returned"); return
	if mod.installed_count() != 2:
		_fail("count after uninstall"); return

	# Round-trip
	var snap: Dictionary = mod.get_summary()
	var placement_snap: Dictionary = placement.get_summary()
	var placement2 = ComponentPlacementStateScript.new()
	placement2.restore_from_layout(layout, catalog, 42, placement_snap)
	var mod2 = ShipModificationStateScript.new()
	mod2.apply_summary(snap)
	mod2.bind_physical_slots("test-ship", placement2.get_physical_slot_descriptors("test-ship"), catalog, placement2)
	if mod2.installed_count() != mod.installed_count():
		_fail("round-trip count"); return
	if absf(mod2.total_power_draw() - mod.total_power_draw()) > 0.01:
		_fail("round-trip power"); return

	print("SHIP MODIFICATION PASS install=true power=true uninstall=true plating=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MODIFICATION FAIL: %s" % msg)
	quit(1)
