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
	var install_requests: Array = []
	var uninstall_requests: Array = []
	panel.install_requested.connect(func(slot_id: String, component_id: String, item_form: String) -> void:
		install_requests.append({"slot_id": slot_id, "component_id": component_id, "item_form": item_form})
	)
	panel.uninstall_requested.connect(func(slot_id: String, component_id: String, item_form: String) -> void:
		uninstall_requests.append({"slot_id": slot_id, "component_id": component_id, "item_form": item_form})
	)

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
	if install_requests.size() != 1 or mod.installed_count() != 0:
		_fail("install must only emit a request"); return
	if int(panel.get_inventory_bag().get("console_unit", 0)) != 2:
		_fail("panel request mutated inventory"); return

	# Simulate the coordinator's later authoritative commit so the panel can issue
	# a request against a real occupied slot. The panel still must not mutate it.
	var requested_slot: String = str((install_requests[0] as Dictionary).get("slot_id", ""))
	var physical_inventory: Dictionary = {"console_unit": 1}
	var mounted: Dictionary = placement.mount_by_slot_id(requested_slot, "console_unit", physical_inventory, catalog)
	if not bool(mounted.get("ok", false)):
		_fail("authoritative fixture mount"); return
	mod.sync_from_placement()
	panel.bind(mod, inv, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	if not panel.select_slot_id(requested_slot):
		_fail("no occupied slot selected for uninstall"); return
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	if uninstall_requests.size() != 1 or mod.installed_count() != 1 or not placement.is_mounted(requested_slot):
		_fail("uninstall must only emit a request"); return
	if int(panel.get_inventory_bag().get("console_unit", 0)) != 2:
		_fail("uninstall request mutated inventory"); return
	placement.dismount(requested_slot)
	mod.sync_from_placement()

	# Power gate
	mod.power_supply = 12.0
	mod.power_demand_baseline = 10.0
	var machinery_inventory: Dictionary = {"machinery_block": 1}
	panel.bind(mod, machinery_inventory, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	var machinery_slot: String = _compatible_slot(catalog, placement, "machinery_block")
	if machinery_slot.is_empty() or not panel.select_slot_id(machinery_slot):
		_fail("machinery fit fixture"); return
	if str(mod.preflight_install(machinery_slot, "machinery_block", "machinery_block", machinery_inventory).get("reason", "")) != "power_budget":
		_fail("expected power budget denial"); return
	var request_count_before_power: int = install_requests.size()
	if panel.install_into_selected("machinery_block", "machinery_block", 20.0, 50.0, false):
		_fail("over-budget install should fail"); return
	if install_requests.size() != request_count_before_power or mod.installed_count() != 0:
		_fail("power denial emitted or mutated"); return

	# Plating path emits a request and leaves both bonus and bag unchanged.
	mod.power_supply = 100.0
	mod.power_demand_baseline = 0.0
	var plating_inventory: Dictionary = {"plating_plate": 1}
	panel.bind(mod, plating_inventory, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	var plating_slot: String = _compatible_slot(catalog, placement, "hull_plating")
	if plating_slot.is_empty() or not panel.select_slot_id(plating_slot):
		_fail("plating fit fixture"); return
	if not panel.install_into_selected("hull_plating", "plating_plate", 1.0, 8.0, true):
		_fail("plating install"); return
	if install_requests.size() != request_count_before_power + 1 or mod.hull_plating_bonus != 0.0 \
			or int(panel.get_inventory_bag().get("plating_plate", 0)) != 1:
		_fail("plating request mutated state"); return

	panel.close()
	if panel.is_open():
		_fail("close"); return

	print("SHIP MOD PANEL PASS bind=true install=true uninstall=true power=true")
	quit(0)


func _compatible_slot(
		catalog,
		placement,
		component_id: String) -> String:
	for descriptor_v in placement.get_physical_slot_descriptors("panel-ship"):
		if not (descriptor_v is Dictionary) or bool((descriptor_v as Dictionary).get("occupied", false)):
			continue
		var slot_id: String = str((descriptor_v as Dictionary).get("slot_id", ""))
		if bool(catalog.validate_component_fit(component_id, descriptor_v as Dictionary).get("ok", false)):
			return slot_id
	return ""


func _fail(msg: String) -> void:
	print("SHIP MOD PANEL FAIL: %s" % msg)
	quit(1)
