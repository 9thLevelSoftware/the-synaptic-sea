extends SceneTree

## Pure selection-math + context-action smoke for the inventory UI's model layer.

const ModelScript := preload("res://scripts/systems/inventory_selection_model.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

func _init() -> void:
	var m: ModelScript = ModelScript.new()
	m.set_ids(["a", "b", "c", "d", "e"])

	# single replaces + sets anchor
	m.select_single(1)
	assert(m.get_selected_ids() == ["b"], "single selects b")

	# shift range from anchor (1) to 3 -> b,c,d
	m.select_range_to(3)
	assert(m.get_selected_ids() == ["b", "c", "d"], "range b..d")

	# ctrl toggle removes one
	m.toggle(2)
	assert(m.get_selected_ids() == ["b", "d"], "toggle off c")

	# reverse range: anchor below the click still selects the contiguous block
	m.select_single(3)
	m.select_range_to(1)
	assert(m.get_selected_ids() == ["b", "c", "d"], "reverse range b..d")

	# new single clears the rest
	m.select_single(4)
	assert(m.get_selected_ids() == ["e"], "single clears prior")

	# set_ids drops out-of-range selection
	m.select_single(4)
	m.set_ids(["x", "y"])
	assert(m.get_selected_ids().is_empty(), "shrunk id list cleared stale selection")

	# --- context_actions ---
	var defs: Dictionary = ItemDefsScript.load_definitions()
	# a normal part in transfer mode: transfer / transfer_all / split
	var part_actions: PackedStringArray = ModelScript.context_actions("scrap_metal", defs, true, true, false)
	assert(Array(part_actions) == ["transfer", "transfer_all", "split"], "part transfer actions")
	# an equippable suit in SELF mode: equip
	var suit_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, false, false, false)
	assert(Array(suit_actions) == ["equip"], "suit equip action in self mode")
	# an equippable in TRANSFER mode: equip is offered for a SELF row (row_is_container=false)...
	var self_row_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, true, false, false)
	assert("equip" in Array(self_row_actions), "self-pane equippable offers equip in transfer mode")
	# ...but suppressed for a CONTAINER row — equip_selected reads the SELF pane only, so offering
	# it there would no-op or equip the wrong item (PR #21 Codex P2).
	var container_row_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, true, true, false)
	assert(not ("equip" in Array(container_row_actions)), "container-pane equippable does NOT offer equip")
	# an occupied equipment slot: unequip
	var slot_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, false, false, true)
	assert(Array(slot_actions) == ["unequip"], "occupied slot unequips")
	# a tool in transfer mode: transferable (transfer present)
	var tool_actions: PackedStringArray = ModelScript.context_actions("portable_oxygen_pump", defs, true, true, false)
	assert("transfer" in Array(tool_actions), "tools are transferable")

	print("INVENTORY SELECTION MODEL SMOKE PASS ids=%d" % m.ids.size())
	quit()
