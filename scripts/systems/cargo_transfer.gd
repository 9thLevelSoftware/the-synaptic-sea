extends RefCounted
class_name CargoTransfer

## Pure-static cargo transfer between the player InventoryState and a ship
## ShipInventory. Conservation is the contract: every move removes from the source
## EXACTLY what the destination's add_item reported accepting, so partial fills
## (hold full mid-deposit, player weight-capped mid-withdraw) never duplicate or
## lose items. Iterates over a snapshot of source ids so removals during iteration
## are safe.

# Salvage categories moved by deposit-all. Tools are intentionally excluded —
# survival gear stays on the player and is never auto-dumped into a hold.
const HAULABLE_CATEGORIES: Array = ["part", "supply"]

## Moves all part+supply stacks from player -> hold, capped by the hold's weight
## room. Returns { "moved": {id:qty}, "total_moved": int }.
static func deposit_all(player, hold) -> Dictionary:
	var moved: Dictionary = {}
	var total: int = 0
	if player == null or hold == null:
		return {"moved": moved, "total_moved": 0}
	var ids: Array = (player.items as Dictionary).keys()
	ids.sort()
	for id_v in ids:
		var item_id: String = String(id_v)
		if not (player.get_category(item_id) in HAULABLE_CATEGORIES):
			continue
		var have: int = player.get_quantity(item_id)
		if have <= 0:
			continue
		var accepted: int = hold.add_item(item_id, have)
		if accepted <= 0:
			continue
		var pulled: int = player.remove_item(item_id, accepted)
		# pulled == accepted by construction; guard anyway.
		if pulled > 0:
			moved[item_id] = int(moved.get(item_id, 0)) + pulled
			total += pulled
	return {"moved": moved, "total_moved": total}

## Moves as much of `category` from hold -> player as the player's carry room
## accepts. Returns { "moved": {id:qty}, "total_moved": int }.
static func withdraw_category(hold, player, category: String) -> Dictionary:
	var moved: Dictionary = {}
	var total: int = 0
	if player == null or hold == null or category.is_empty():
		return {"moved": moved, "total_moved": 0}
	var entries: Array = hold.get_items_by_category(category)   # [{id, quantity, weight_each}]
	for entry_v in entries:
		var entry: Dictionary = entry_v
		var item_id: String = String(entry.get("id", ""))
		var have: int = int(entry.get("quantity", 0))
		if item_id.is_empty() or have <= 0:
			continue
		var accepted: int = player.add_item(item_id, have)
		if accepted <= 0:
			continue
		var pulled: int = hold.remove_item(item_id, accepted)
		if pulled > 0:
			moved[item_id] = int(moved.get(item_id, 0)) + pulled
			total += pulled
	return {"moved": moved, "total_moved": total}

## Moves up to `qty` of one item_id from src -> dst. The destination enforces its own
## cap inside add_item (player InventoryState = soft-cap/full accept; ShipInventory =
## hard weight-cap/partial fill), and src loses EXACTLY what dst accepted, so the
## per-id total across src+dst is invariant. Returns the count actually moved.
static func move_item(src, dst, item_id: String, qty: int) -> int:
	if src == null or dst == null or item_id.is_empty() or qty <= 0:
		return 0
	var have: int = int(src.get_quantity(item_id))
	var want: int = min(qty, have)
	if want <= 0:
		return 0
	var accepted: int = int(dst.add_item(item_id, want))
	if accepted <= 0:
		return 0
	return int(src.remove_item(item_id, accepted))

## Applies move_item per entry (ids sorted for determinism). Returns total moved.
## Used by multi-selection drags and "transfer all".
static func move_items(src, dst, id_to_qty: Dictionary) -> int:
	var total: int = 0
	var ids: Array = id_to_qty.keys()
	ids.sort()
	for id_v in ids:
		total += move_item(src, dst, String(id_v), int(id_to_qty[id_v]))
	return total
