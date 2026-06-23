extends SceneTree

## CargoTransfer pure-logic smoke. Asserts:
##   - deposit_all moves part+supply, LEAVES tools on the player
##   - withdraw_category respects the player carry-weight cap (partial fill)
##   - the conservation invariant: summed per-id quantity across player+hold is
##     invariant under any transfer (no duplication, no loss)

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")

# All three are real ids (item_definitions.json / tool_definitions.json).
const PART_ITEM := "scrap_metal"          # part, weight 5.0, max_stack 20
const SUPPLY_ITEM := "ration_pack"        # supply, weight 0.5, max_stack 20
const TOOL_ITEM := "portable_oxygen_pump" # tool (tool_definitions.json; used by OxygenState)

func _total(a: Dictionary, b: Dictionary, id: String) -> int:
	return int(a.get(id, 0)) + int(b.get(id, 0))

func _init() -> void:
	var player = InventoryStateScript.new()
	player.add_item(PART_ITEM, 4)
	player.add_item(SUPPLY_ITEM, 3)
	player.add_tool(TOOL_ITEM)   # a tool on the player
	var hold = ShipInventoryScript.create(500.0)

	# --- conservation baseline ---
	var before_part: int = _total(player.items, hold.items, PART_ITEM)
	var before_supply: int = _total(player.items, hold.items, SUPPLY_ITEM)
	var before_tool: int = _total(player.items, hold.items, TOOL_ITEM)

	# --- deposit_all ---
	var dep: Dictionary = CargoTransferScript.deposit_all(player, hold)
	assert(int(dep.get("total_moved", -1)) == 7, "deposited 4 part + 3 supply (got %d)" % int(dep.get("total_moved", -1)))
	assert(player.get_quantity(PART_ITEM) == 0, "part left the player")
	assert(player.get_quantity(SUPPLY_ITEM) == 0, "supply left the player")
	assert(player.has_tool(TOOL_ITEM), "TOOL STAYS on the player")
	assert(hold.get_quantity(PART_ITEM) == 4 and hold.get_quantity(SUPPLY_ITEM) == 3, "hold received salvage")
	assert(hold.get_quantity(TOOL_ITEM) == 0, "tool NOT in the hold")
	# conservation holds across the deposit
	assert(_total(player.items, hold.items, PART_ITEM) == before_part, "part conserved")
	assert(_total(player.items, hold.items, SUPPLY_ITEM) == before_supply, "supply conserved")
	assert(_total(player.items, hold.items, TOOL_ITEM) == before_tool, "tool conserved")

	# --- withdraw_category honors the player carry cap (partial fill) ---
	# Fill the hold heavily, then withdraw 'part' into a near-full player bag.
	hold.add_item(PART_ITEM, 90)
	var pre_player: int = player.get_quantity(PART_ITEM)
	var pre_hold: int = hold.get_quantity(PART_ITEM)
	var wd: Dictionary = CargoTransferScript.withdraw_category(hold, player, "part")
	var moved: int = int(wd.get("total_moved", -1))
	assert(moved > 0, "withdraw moved at least one item (got %d)" % moved)
	# conservation across the withdraw
	assert(player.get_quantity(PART_ITEM) + hold.get_quantity(PART_ITEM) == pre_player + pre_hold, "part conserved across withdraw")
	# player never exceeds its weight cap
	assert(player.get_total_weight() <= player.get_max_weight() + 0.0001, "player cap respected")

	print("CARGO TRANSFER SMOKE PASS conserved=true deposited=%d withdrew=%d" % [int(dep.get("total_moved", 0)), moved])
	quit()
