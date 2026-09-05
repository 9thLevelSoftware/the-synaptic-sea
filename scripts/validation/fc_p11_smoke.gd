extends SceneTree

## FC-13: exact generated slot contracts and placement-owned component installs.
## Exact runner marker: FC P11 PASS

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ShipModificationPanelScript := preload("res://scripts/ui/ship_modification_panel.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")


func _initialize() -> void:
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("catalog load")
		return
	if not _verify_generated_contracts(catalog):
		return
	var layout: Dictionary = _authored_layout()
	var placement = ComponentPlacementStateScript.new()
	placement.populate(layout, catalog, 42)
	var slots: Array = placement.get_physical_slot_descriptors("derelict-a")
	if slots.size() != 3:
		_fail("expected three exact physical slots, got %d" % slots.size())
		return
	if not _missing_contracts_fail_closed(catalog):
		return
	_dismount_all(placement)

	var state = ShipModificationStateScript.new()
	state.configure({"power_supply": 100.0, "power_demand_baseline": 0.0})
	if not state.bind_physical_slots("derelict-a", placement.get_physical_slot_descriptors("derelict-a"), catalog, placement):
		_fail("placement owner bind")
		return
	var inventory: Dictionary = {
		"purified_water": 1,
		"unknown_part": 1,
		"reactor_console": 1,
		"pump_assembly": 1,
		"wall_locker": 1,
	}
	var baseline: Dictionary = inventory.duplicate(true)
	var power_before: float = state.total_power_draw()
	_expect_denied(state.install("eng_wall_0", "purified_water", "purified_water", inventory), "unknown_component", "water")
	_expect_unchanged(state, placement, inventory, baseline, power_before, "water")
	_expect_denied(state.install("eng_wall_0", "unknown_part", "unknown_part", inventory), "unknown_component", "unknown")
	_expect_unchanged(state, placement, inventory, baseline, power_before, "unknown")
	_expect_denied(state.install("eng_wall_0", "pump_assembly", "pump_assembly", inventory), "incompatible_slot", "wrong slot")
	_expect_unchanged(state, placement, inventory, baseline, power_before, "wrong slot")
	_expect_denied(state.install("eng_wall_0", "reactor_console", "reactor_console", inventory, 0.0, 0.0, "", false, "other-ship"), "wrong_ship", "wrong ship")
	_expect_unchanged(state, placement, inventory, baseline, power_before, "wrong ship")

	var wall_install: Dictionary = state.install("eng_wall_0", "reactor_console", "reactor_console", inventory)
	if not bool(wall_install.get("ok", false)) or not placement.is_mounted("eng_wall_0"):
		_fail("singular wall socket install did not mount physical placement: %s" % str(wall_install))
		return
	var wall_remove: Dictionary = state.uninstall("eng_wall_0", inventory)
	if not bool(wall_remove.get("ok", false)) or placement.is_mounted("eng_wall_0"):
		_fail("physical wall uninstall")
		return
	var deck_install: Dictionary = state.install("eng_center_0", "pump_assembly", "pump_assembly", inventory)
	if not bool(deck_install.get("ok", false)) or not placement.is_mounted("eng_center_0"):
		_fail("singular deck socket install did not mount physical placement: %s" % str(deck_install))
		return

	if not await _verify_panel_catalog_search(catalog):
		return
	if not _verify_current_policy_overrides_saved(catalog, layout):
		return
	print("FC P11 PASS")
	quit(0)


func _verify_generated_contracts(catalog) -> bool:
	var deck_console_fit: Dictionary = catalog.validate_component_fit("console_generic", {
		"slot_kind": "center",
		"component_slot_profile_id": "deck_console_mount_v1",
	})
	if not bool(deck_console_fit.get("ok", false)):
		_fail("authored deck console contract has no valid component")
		return false
	var fallback = ShipLayoutGeneratorScript.new()
	var fallback_layout: Dictionary = fallback.generate(ShipBlueprintScript.new(1, 1, 42), {})
	if not _all_slots_have_profile(fallback_layout, catalog):
		_fail("fallback generator emitted an uncontracted slot")
		return false
	if not ClassDB.class_exists("DerelictGenerator"):
		_fail("native DerelictGenerator unavailable")
		return false
	var native = ClassDB.instantiate("DerelictGenerator")
	var parsed: Variant = JSON.parse_string(str(native.export_layout_json(42, {
		"archetype_id": "corvette",
		"intactness_override": 6000,
	}, "ship_structural_v0")))
	if not (parsed is Dictionary):
		_fail("native layout export")
		return false
	var native_layout: Dictionary = (parsed as Dictionary).duplicate(true)
	if not ShipGeneratorScript.stamp_native_component_slot_contracts(native_layout):
		_fail("native component slot projection")
		return false
	if not _all_slots_have_profile(native_layout, catalog):
		_fail("native generator emitted an uncontracted slot")
		return false
	return true


func _all_slots_have_profile(layout: Dictionary, catalog) -> bool:
	var found: int = 0
	var rooms_v: Variant = layout.get("rooms", [])
	if not (rooms_v is Array):
		return false
	for room_v in rooms_v as Array:
		if not (room_v is Dictionary):
			continue
		var interior_v: Variant = (room_v as Dictionary).get("interior_zones", {})
		if not (interior_v is Dictionary):
			continue
		for key in ["wall_slots", "center_slots"]:
			var slots_v: Variant = (interior_v as Dictionary).get(key, [])
			if not (slots_v is Array):
				continue
			for slot_v in slots_v as Array:
				found += 1
				if not (slot_v is Dictionary):
					return false
				var profile_id: String = str((slot_v as Dictionary).get("component_slot_profile_id", ""))
				if profile_id.is_empty() or catalog.get_slot_profile(profile_id).is_empty():
					return false
	return found > 0


func _authored_layout() -> Dictionary:
	return {"rooms": [{
		"id": "eng",
		"room_role": "engineering",
		"interior_zones": {
			"wall_slots": [
				{"cell": [0, 0], "against_wall": true, "component_slot_profile_id": "wall_console_mount_v1"},
				{"cell": [0, 1], "against_wall": true, "component_slot_profile_id": "wall_utility_mount_v1"},
			],
			"center_slots": [
				{"cell": [1, 0], "against_wall": false, "component_slot_profile_id": "deck_machinery_mount_v1"},
			],
			"reserved_cells": [],
		},
	}]}


func _missing_contracts_fail_closed(catalog) -> bool:
	for profile_id in ["", "does_not_exist"]:
		var placement = ComponentPlacementStateScript.new()
		placement.populate({"rooms": [{
			"id": "bad",
			"room_role": "engineering",
			"wall_slots": [{"cell": [0, 0], "component_slot_profile_id": profile_id}],
			"center_slots": [],
		}]}, catalog, 1)
		if not placement.get_physical_slot_descriptors("bad-ship").is_empty():
			_fail("missing/unknown profile granted a physical slot")
			return false
	return true


func _dismount_all(placement) -> void:
	for entry_v in placement.placed.duplicate(true):
		if entry_v is Dictionary and bool((entry_v as Dictionary).get("mounted", true)):
			placement.dismount(str((entry_v as Dictionary).get("component_instance_id", "")))


func _verify_panel_catalog_search(catalog) -> bool:
	var placement = ComponentPlacementStateScript.new()
	placement.populate(_authored_layout(), catalog, 42)
	_dismount_all(placement)
	var state = ShipModificationStateScript.new()
	state.configure({"power_supply": 100.0, "power_demand_baseline": 0.0})
	state.bind_physical_slots("panel-ship", placement.get_physical_slot_descriptors("panel-ship"), catalog, placement)
	var panel = ShipModificationPanelScript.new()
	get_root().add_child(panel)
	await process_frame
	panel.bind(state, {"reactor_console": 1}, catalog, state.get_physical_slots(), "panel-ship", placement)
	panel.move_selection(1)
	if not panel.install_from_inventory(catalog) or not placement.is_mounted("eng_wall_0"):
		_fail("panel stopped on incompatible same-kind utility slot")
		return false
	var returned_inventory: Dictionary = panel.get_inventory_bag()
	state.uninstall("eng_wall_0", returned_inventory)
	panel.bind(state, {"wall_locker": 1}, catalog, placement.get_physical_slot_descriptors("panel-ship"), "panel-ship", placement)
	if not panel.install_from_inventory(catalog) or not placement.is_mounted("eng_wall_1"):
		_fail("panel omitted valid wall_locker catalog form")
		return false
	panel.queue_free()
	return true


func _verify_current_policy_overrides_saved(catalog, layout: Dictionary) -> bool:
	var original = ComponentPlacementStateScript.new()
	original.populate(layout, catalog, 42)
	var stale: Dictionary = original.get_summary()
	var saved_placed: Array = stale.get("placed", []) as Array
	for index in range(saved_placed.size()):
		var row: Dictionary = saved_placed[index] as Dictionary
		if str(row.get("component_instance_id", "")) == "eng_wall_0":
			row["component_id"] = "pump_assembly"
			row["item_form"] = "pump_assembly"
			row["mounted"] = true
			row["socket_type"] = "deck_mount"
			row["allowed_component_types"] = ["machinery"]
			saved_placed[index] = row
	stale["placed"] = saved_placed
	stale["physical_slots"] = [{
		"slot_id": "eng_wall_0",
		"socket_type": "deck_mount",
		"allowed_component_types": ["machinery"],
		"footprint_cells": [1, 1],
	}]
	var restored = ComponentPlacementStateScript.new()
	if not restored.restore_from_layout(layout, catalog, 42, stale):
		_fail("current-layout restore")
		return false
	var slot: Dictionary = restored.get_physical_slot("eng_wall_0")
	if str(slot.get("socket_type", "")) != "wall_mount" or str(slot.get("component_slot_profile_id", "")) != "wall_console_mount_v1":
		_fail("saved fit policy overrode current authored contract")
		return false
	if restored.is_mounted("eng_wall_0") or restored.rejected_saved_components.size() != 1:
		_fail("incompatible stale mounted content was not quarantined")
		return false
	var recovery_snapshot: Dictionary = restored.get_summary()
	var restored_again = ComponentPlacementStateScript.new()
	if not restored_again.restore_from_layout(layout, catalog, 42, recovery_snapshot) \
			or restored_again.rejected_saved_components.size() != 1:
		_fail("quarantined stale content did not remain recoverable across save")
		return false
	var rejected: Dictionary = restored_again.rejected_saved_components[0] as Dictionary
	var rejected_entry: Dictionary = rejected.get("saved_entry", {}) as Dictionary
	if str(rejected_entry.get("component_id", "")) != "pump_assembly":
		_fail("quarantined stale content was not preserved")
		return false
	var removed_slot_summary: Dictionary = {
		"placed": [{
			"component_instance_id": "removed_wall_0",
			"component_id": "reactor_console",
			"mounted": true,
		}],
	}
	var removed_slot_restore = ComponentPlacementStateScript.new()
	removed_slot_restore.restore_from_layout(layout, catalog, 42, removed_slot_summary)
	if removed_slot_restore.rejected_saved_components.size() != 1 \
			or str((removed_slot_restore.rejected_saved_components[0] as Dictionary).get("reason", "")) != "slot_removed":
		_fail("removed authored slot content was not preserved for recovery")
		return false
	return true


func _expect_denied(result: Dictionary, reason: String, label: String) -> void:
	if bool(result.get("ok", false)) or str(result.get("reason", "")) != reason:
		_fail("%s expected %s, got %s" % [label, reason, str(result)])


func _expect_unchanged(state, placement, inventory: Dictionary, baseline: Dictionary, power_before: float, label: String) -> void:
	if state.installed_count() != 0 or placement.mounted_count() != 0 or inventory != baseline or absf(state.total_power_draw() - power_before) > 0.001:
		_fail("%s mutated before acceptance" % label)


func _fail(message: String) -> void:
	push_error("FC P11 FAIL: %s" % message)
	quit(1)
