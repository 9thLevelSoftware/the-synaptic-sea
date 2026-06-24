extends SceneTree

## InventoryPanel logical-API smoke. Section A (this task): SELF mode — render lists,
## select a row, equip/unequip round-trip, Heavy-Load badge. Section B (Task 4) extends
## this file with TRANSFER mode + drag-data plumbing. Drives the same logical API the
## mouse overrides call, so no synthetic pixel input is needed.

const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _init() -> void:
	await _run_section_a()
	print("INVENTORY PANEL SMOKE PASS section_a=true")
	quit()

func _run_section_a() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)        # part
	inv.add_item("eva_backpack", 1)       # equippable: back, +40 capacity
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_self(inv, equip)
	assert(panel.is_open() and panel.get_mode() == "self", "panel open in self mode")

	# carrying list contains both ids
	var ids: Array = panel.get_pane_ids("self")
	assert("scrap_metal" in ids and "eva_backpack" in ids, "self list shows carried items")

	# select the backpack row and equip it
	var bp_index: int = ids.find("eva_backpack")
	panel.select_row("self", bp_index, false, false)
	assert(panel.equip_selected() == true, "equipped the backpack")
	assert(equip.get_equipped("back") == "eva_backpack", "backpack now worn")
	assert(inv.get_quantity("eva_backpack") == 0, "worn item left the carry list")

	# unequip puts it back in the carry list
	assert(panel.unequip_slot("back") == true, "unequipped back")
	assert(inv.get_quantity("eva_backpack") == 1, "item returned to inventory")
	assert(equip.get_equipped("back") == "", "back slot empty")

	# Heavy-Load badge: stuff the player far over capacity (no bag bonus now)
	inv.add_item("plating", 10)   # 8.0 each -> 80; base cap 50 -> overloaded
	assert(panel.get_load_badge() == "OVERLOADED", "badge flips overloaded (got %s)" % panel.get_load_badge())

	# close emits panel_closed
	var closed := [false]
	panel.panel_closed.connect(func(): closed[0] = true)
	panel.close()
	assert(panel.is_open() == false and closed[0], "close emits panel_closed")
	panel.queue_free()
