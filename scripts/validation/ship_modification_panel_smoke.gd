extends SceneTree

## PKG-D9b: ShipModificationPanel install/uninstall + power display.
## Marker: SHIP MOD PANEL PASS bind=true install=true uninstall=true power=true

const ShipModificationPanelScript := preload("res://scripts/ui/ship_modification_panel.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")


func _initialize() -> void:
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 50.0, "power_demand_baseline": 10.0})
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("catalog load"); return
	var layout: Dictionary = {"rooms": [{"id": "eng", "room_role": "engineering", "wall_slots": [
		{"cell": [0, 0], "component_slot_profile_id": "wall_console_mount_v1"},
		{"cell": [0, 1], "component_slot_profile_id": "wall_utility_mount_v1"},
	], "center_slots": [{"cell": [1, 0], "component_slot_profile_id": "deck_machinery_mount_v1"}]}]}
	var placement = ComponentPlacementStateScript.new()
	placement.populate(layout, catalog, 42)
	for entry_v in placement.placed.duplicate(true):
		placement.dismount(str((entry_v as Dictionary).get("component_instance_id", "")))
	var physical_slots: Array = placement.get_physical_slot_descriptors("panel-ship")
	var panel = ShipModificationPanelScript.new()
	get_root().add_child(panel)
	await process_frame

	var inv: Dictionary = {"console_unit": 2, "plating_plate": 1}
	panel.bind(mod, inv, catalog, physical_slots, "panel-ship", placement)
	panel.open()
	if not panel.is_open():
		_fail("panel should open"); return
	var lines: PackedStringArray = panel.get_status_lines()
	var joined: String = "\n".join(lines)
	if joined.find("power") < 0 and joined.find("Ship Mod") < 0:
		_fail("power/status header missing"); return
	if panel.get_selected_slot_id().is_empty():
		_fail("should select a slot"); return

	if not panel.install_into_selected("console_generic", "console_unit", 5.0, 12.0, false):
		_fail("install: %s" % "\n".join(panel.get_status_lines())); return
	if mod.installed_count() != 1:
		_fail("expected 1 install"); return
	if int(panel.get_inventory_bag().get("console_unit", 0)) != 1:
		_fail("inventory should consume 1 console"); return

	# Occupied installs are listed first; selection stays at 0 after install.
	panel.refresh()
	if panel.get_selected_slot_id().is_empty():
		_fail("no slot selected for uninstall"); return
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if mod.installed_count() != 0:
		_fail("should be empty after uninstall"); return
	if int(panel.get_inventory_bag().get("console_unit", 0)) != 2:
		_fail("console returned to bag"); return

	# Power gate
	mod.power_supply = 12.0
	mod.power_demand_baseline = 10.0
	panel.bind(mod, {"machinery_block": 1}, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	if panel.install_into_selected("machinery_block", "machinery_block", 20.0, 50.0, false):
		_fail("over-budget install should fail"); return
	var st_lines: String = "\n".join(panel.get_status_lines())
	if st_lines.find("power_budget") < 0 and st_lines.find("install failed") < 0:
		_fail("expected power fail status"); return

	# Plating install path
	mod.power_supply = 100.0
	mod.power_demand_baseline = 0.0
	panel.bind(mod, {"plating_plate": 1}, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	if not panel.install_into_selected("hull_plating", "plating_plate", 1.0, 8.0, true):
		_fail("plating install"); return
	if mod.hull_plating_bonus < 0.04:
		_fail("plating bonus"); return

	panel.close()
	if panel.is_open():
		_fail("close"); return

	print("SHIP MOD PANEL PASS bind=true install=true uninstall=true power=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MOD PANEL FAIL: %s" % msg)
	quit(1)
