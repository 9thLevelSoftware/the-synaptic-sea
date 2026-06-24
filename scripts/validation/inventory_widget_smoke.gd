extends SceneTree

## InventoryPanel interactive-widget smoke. Section A (this task): the coordinator
## callbacks the row/zone widgets call, driven DIRECTLY (no widgets needed yet).
## Section B (Task 2) extends this with real widgets driven by synthetic input.

const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

func _init() -> void:
	await _run_section_a()
	await _run_section_b()
	print("INVENTORY WIDGET SMOKE PASS section_a=true section_b=true")
	quit()

func _run_section_a() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)
	inv.add_item("ration_pack", 3)
	inv.add_item("eva_backpack", 1)        # equippable: back
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("plating", 4)
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)

	# row_clicked -> selection
	var you := panel.get_pane_ids("self")
	panel.row_clicked("self", you.find("scrap_metal"), false, false)
	assert(panel.get_selected_ids("self") == ["scrap_metal"], "row_clicked selected scrap")

	# row_drag_payload selects if needed + returns payload
	var drag = panel.row_drag_payload("self", you.find("ration_pack"))
	assert(drag != null and drag["from_pane"] == "self", "drag payload built")
	assert("ration_pack" in (drag["ids"] as Array), "payload carries the row id")

	# zone_can_accept / zone_drop across panes (transfer)
	panel.row_clicked("self", panel.get_pane_ids("self").find("scrap_metal"), false, false)
	var pay := {"from_pane": "self", "ids": ["scrap_metal"]}
	assert(panel.zone_can_accept("container", pay) == true, "container accepts a YOU drop")
	assert(panel.zone_can_accept("self", pay) == false, "same-pane drop refused")
	panel.zone_drop("container", pay)
	assert(hold.get_quantity("scrap_metal") == 6, "zone_drop moved the stack into the hold")

	# transfer_all_from moves every id (incl tools) from a pane
	inv.add_tool("portable_oxygen_pump")
	var moved_all := panel.transfer_all_from("self")
	assert(moved_all == 5 and hold.get_quantity("portable_oxygen_pump") == 1, "transfer_all moved everything incl tool (got %d)" % moved_all)
	assert(panel.get_pane_ids("self").is_empty(), "YOU emptied by transfer_all")

	# equipment-slot drop equips (from the self pane only)
	inv.add_item("eva_backpack", 1)  # back in the player inventory again
	panel._rebuild_models()   # smoke mutated inv directly (bypassing the panel) -> resync the selection models
	var slot_pay := {"from_pane": "self", "ids": ["eva_backpack"]}
	assert(panel.zone_can_accept("slot:back", slot_pay) == true, "back slot accepts the backpack")
	assert(panel.zone_can_accept("slot:suit", slot_pay) == false, "suit slot rejects a back item")
	panel.zone_drop("slot:back", slot_pay)
	assert(equip.get_equipped("back") == "eva_backpack", "slot drop equipped the backpack")

	# context menu: built (not popped) with the expected action set; dispatch works
	hold.add_item("plating", 4)  # ensure container has a row
	var cmenu = panel._build_context_menu("container", panel.get_pane_ids("container").find("plating"))
	var labels: Array = []
	for i in range(cmenu.item_count):
		labels.append(cmenu.get_item_text(i))
	assert("Transfer" in labels and "Transfer all" in labels and "Split…" in labels, "menu has transfer/all/split")
	cmenu.free()
	# dispatch Transfer all from the container -> everything back to the player
	panel._on_context_id(panel._ACT_TRANSFER_ALL, "container", 0, null)
	assert(inv.get_quantity("plating") >= 4, "context Transfer all pulled plating to player")

	panel.queue_free()

func _run_section_b() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)
	inv.add_item("eva_backpack", 1)
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("plating", 4)
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)
	await process_frame   # let the row Controls' _ready run

	# a real row exists and a synthetic left-click selects it
	var ids := panel.get_pane_ids("self")
	var ri := ids.find("scrap_metal")
	var row := panel.row_at("self", ri)
	assert(row != null, "row Control was built for scrap_metal")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	row._gui_input(click)
	assert(panel.get_selected_ids("self") == ["scrap_metal"], "synthetic click selected the row")

	# the row yields a non-empty drag payload; dropping on the container zone transfers
	var payload = row._get_drag_data(Vector2.ZERO)
	assert(payload != null and (payload as Dictionary)["from_pane"] == "self", "row drag payload built")
	var czone := panel.zone_for("container")
	assert(czone != null, "container drop zone exists")
	assert(czone._can_drop_data(Vector2.ZERO, payload) == true, "container zone accepts the drop")
	czone._drop_data(Vector2.ZERO, payload)
	assert(hold.get_quantity("scrap_metal") == 6, "drag->drop moved the stack into the hold")

	# dropping the backpack on the back equipment slot equips it
	var bp_row := panel.row_at("self", panel.get_pane_ids("self").find("eva_backpack"))
	var bp_payload = bp_row._get_drag_data(Vector2.ZERO)
	var back_zone := panel.zone_for("slot:back")
	assert(back_zone != null and back_zone._can_drop_data(Vector2.ZERO, bp_payload) == true, "back slot accepts the backpack")
	back_zone._drop_data(Vector2.ZERO, bp_payload)
	assert(equip.get_equipped("back") == "eva_backpack", "slot drop equipped via the widget")

	panel.queue_free()
