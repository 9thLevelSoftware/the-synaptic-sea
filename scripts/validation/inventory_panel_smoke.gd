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

	# atomic equip/unequip: a displaced item with no carry room aborts cleanly (no loss).
	# Direct add_item bypasses the panel, so re-open_self after seeding to refresh the
	# selection model (open_self -> _rebuild_models mirrors the live inventory).
	var inv2 = InventoryStateScript.new()
	var equip2 = EquipmentStateScript.create()
	var panel2 = InventoryPanelScript.new()
	root.add_child(panel2)
	await process_frame
	inv2.add_item("eva_backpack", 1)
	panel2.open_self(inv2, equip2)
	panel2.select_row("self", panel2.get_pane_ids("self").find("eva_backpack"), false, false)
	assert(panel2.equip_selected() == true, "equipped eva_backpack")
	inv2.add_item("eva_backpack", 999)   # saturate the carry stack to max_stack
	inv2.add_item("field_pack", 1)        # sibling back-slot item
	var full_qty: int = inv2.get_quantity("eva_backpack")
	panel2.open_self(inv2, equip2)
	panel2.select_row("self", panel2.get_pane_ids("self").find("field_pack"), false, false)
	assert(panel2.equip_selected() == false, "equip aborts when displaced has no carry room")
	assert(equip2.get_equipped("back") == "eva_backpack", "original stays worn after abort")
	assert(inv2.get_quantity("field_pack") == 1, "field_pack not consumed by aborted equip")
	assert(inv2.get_quantity("eva_backpack") == full_qty, "no eva_backpack lost")
	assert(panel2.unequip_slot("back") == false, "unequip aborts when carry stack full")
	assert(equip2.get_equipped("back") == "eva_backpack", "still worn after aborted unequip")
	panel2.queue_free()

	# Heavy-Load badge across all three bands (fresh fixture, base capacity 50)
	var inv3 = InventoryStateScript.new()
	var panel3 = InventoryPanelScript.new()
	root.add_child(panel3)
	await process_frame
	panel3.open_self(inv3, EquipmentStateScript.create())
	inv3.add_item("plating", 6)   # 6*8.0=48, ratio 0.96 -> OK
	assert(panel3.get_load_badge() == "OK", "badge OK at ratio <= 1.0")
	inv3.add_item("plating", 1)   # 56, ratio 1.12 -> HEAVY
	assert(panel3.get_load_badge() == "HEAVY", "badge HEAVY in (1.0,1.25]")
	panel3.queue_free()

	# close emits panel_closed
	var closed := [false]
	panel.panel_closed.connect(func(): closed[0] = true)
	panel.close()
	assert(panel.is_open() == false and closed[0], "close emits panel_closed")
	panel.queue_free()
