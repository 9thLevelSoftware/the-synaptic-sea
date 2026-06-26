extends SceneTree

## CargoTransfer per-item move + ItemDefs.icon smoke. Asserts move_item honors each
## destination's own cap (player soft-cap = full accept; hold hard-cap = partial fill),
## conservation (no dup/loss), multi-item move, split (partial qty), tool transfer
## (tools ARE manually transferable), and the icon reader's empty default.

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const PART := "scrap_metal"          # part, weight 5.0, max_stack 20
const SUPPLY := "ration_pack"        # supply, weight 0.5, max_stack 20
const TOOL := "portable_oxygen_pump" # tool

func _init() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()

	# icon reader: absent field -> "" (swatch fallback)
	assert(ItemDefsScript.icon(defs, PART) == "", "icon default is empty")

	# --- player soft-cap destination: full accept ---
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item(PART, 10)
	var player = InventoryStateScript.new()
	var moved_in: int = CargoTransferScript.move_item(hold, player, PART, 4)
	assert(moved_in == 4, "moved 4 to player (got %d)" % moved_in)
	assert(player.get_quantity(PART) == 4 and hold.get_quantity(PART) == 6, "split left 6 in hold")

	# --- hold hard-cap destination: partial fill ---
	# scrap_metal weighs 5.0; a 12-weight hold accepts only floor(12/5)=2.
	var tiny = ShipInventoryScript.create(12.0)
	var src = InventoryStateScript.new()
	src.add_item(PART, 5)
	var moved_cap: int = CargoTransferScript.move_item(src, tiny, PART, 5)
	assert(moved_cap == 2, "hold weight cap took only 2 (got %d)" % moved_cap)
	assert(src.get_quantity(PART) == 3, "exactly the accepted 2 left the source")
	assert(src.get_quantity(PART) + tiny.get_quantity(PART) == 5, "conservation across capped move")

	# --- tools transferable + multi-item move ---
	var p2 = InventoryStateScript.new()
	p2.add_tool(TOOL)
	p2.add_item(SUPPLY, 3)
	var hold2 = ShipInventoryScript.create(1000.0)
	var moved_multi: int = CargoTransferScript.move_items(p2, hold2, {TOOL: 1, SUPPLY: 3})
	assert(moved_multi == 4, "moved tool + 3 supply (got %d)" % moved_multi)
	assert(hold2.get_quantity(TOOL) == 1, "tool is now in the hold (tools transferable)")
	assert(p2.get_quantity(TOOL) == 0, "tool left the player")

	# --- no-ops ---
	assert(CargoTransferScript.move_item(p2, hold2, PART, 0) == 0, "qty 0 moves nothing")
	assert(CargoTransferScript.move_item(p2, hold2, "nonexistent_id", 5) == 0, "unknown id moves nothing")

	print("CARGO MOVE ITEM SMOKE PASS soft=%d capped=%d multi=%d" % [moved_in, moved_cap, moved_multi])
	quit()
