extends RefCounted
class_name CargoTransfer

## Transfer authority for player, cargo, and carts. It preserves a lot's exact
## metadata and preflights a hard-capped destination before source removal.

const HAULABLE_CATEGORIES: Array = ["part", "supply"]

static func _acceptable(dst, item_id: String, qty: int) -> int:
	if dst != null and dst.has_method("get_acceptable_quantity"):
		return mini(qty, maxi(0, int(dst.get_acceptable_quantity(item_id, qty))))
	if dst != null and dst.has_method("get_definition") and dst.has_method("get_quantity"):
		var definition: Dictionary = dst.get_definition(item_id)
		return mini(qty, maxi(0, int(definition.get("max_stack", 99)) - int(dst.get_quantity(item_id))))
	if dst != null and dst.has_method("can_accept") and dst.can_accept(item_id, qty):
		return qty # player carry mass remains deliberately soft
	return 0

static func _restore(src, lots: Array) -> bool:
	for lot_v in lots:
		var lot: Dictionary = lot_v as Dictionary
		if not src.has_method("add_lot") or int(src.add_lot(lot)) != int(lot.get("quantity", 0)):
			return false
	return true

## preferred_ids is an additive selected-lot constraint for UI callers. Empty
## preserves legacy standard-first scalar selection from ItemLotLedger.
static func move_item(src, dst, item_id: String, qty: int, preferred_ids: PackedStringArray = PackedStringArray()) -> int:
	if src == null or dst == null or item_id.is_empty() or qty <= 0 or not src.has_method("take_lots") or not dst.has_method("add_lot"):
		return 0
	var accepted: int = _acceptable(dst, item_id, mini(qty, int(src.get_quantity(item_id))))
	if accepted <= 0: return 0
	var outgoing: Array = src.take_lots(item_id, accepted, preferred_ids)
	if outgoing.is_empty(): return 0
	var deposited: Array = []
	for lot_v in outgoing:
		var lot: Dictionary = lot_v as Dictionary
		if int(dst.add_lot(lot)) != int(lot.get("quantity", 0)):
			for put_v in deposited:
				var put: Dictionary = put_v as Dictionary
				dst.take_lots(str(put.item_id), int(put.quantity), PackedStringArray([str(put.lot_id)]))
			_restore(src, outgoing)
			return 0
		deposited.append(lot)
	var total: int = 0
	for lot_v in outgoing: total += int((lot_v as Dictionary).get("quantity", 0))
	return total

static func move_items(src, dst, id_to_qty: Dictionary) -> int:
	var total: int = 0
	var ids: Array = id_to_qty.keys(); ids.sort()
	for id_v in ids: total += move_item(src, dst, str(id_v), int(id_to_qty[id_v]))
	return total

static func deposit_all(player, hold) -> Dictionary:
	var moved: Dictionary = {}; var total: int = 0
	if player == null or hold == null: return {"moved": moved, "total_moved": total}
	var ids: Array = player.items.keys(); ids.sort()
	for id_v in ids:
		var item_id: String = str(id_v)
		if player.get_category(item_id) in HAULABLE_CATEGORIES:
			var amount: int = move_item(player, hold, item_id, player.get_quantity(item_id))
			if amount > 0: moved[item_id] = amount; total += amount
	return {"moved": moved, "total_moved": total}

static func withdraw_category(hold, player, category: String) -> Dictionary:
	var moved: Dictionary = {}; var total: int = 0
	if hold == null or player == null or category.is_empty(): return {"moved": moved, "total_moved": total}
	for entry_v in hold.get_items_by_category(category):
		var entry: Dictionary = entry_v as Dictionary
		var item_id: String = str(entry.get("id", ""))
		var amount: int = move_item(hold, player, item_id, int(entry.get("quantity", 0)))
		if amount > 0: moved[item_id] = amount; total += amount
	return {"moved": moved, "total_moved": total}
