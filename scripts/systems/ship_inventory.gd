extends RefCounted
class_name ShipInventory

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const MAX_WEIGHT_DEFAULT: float = 500.0

var max_weight: float = MAX_WEIGHT_DEFAULT
var _defs: Dictionary = {}
var _lot_ledger
var _holder_namespace_established: bool = false
var _craft_reservation_authority: WeakRef = null
var _reservation_credit_job_id: String = ""
var items: Dictionary:
	get: return _lot_ledger.get_quantities() if _lot_ledger != null else {}

func _init() -> void:
	_defs = ItemDefsScript.load_definitions()
	_lot_ledger = ItemLotLedgerScript.new(_defs)

static func create(p_max_weight: float = MAX_WEIGHT_DEFAULT, holder_namespace: String = "") -> ShipInventory:
	var inst = (load("res://scripts/systems/ship_inventory.gd") as GDScript).new()
	if not holder_namespace.is_empty():
		inst.bind_holder_namespace(holder_namespace)
	inst.max_weight = p_max_weight
	return inst

func get_max_weight() -> float: return max_weight
func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items: total += ItemDefsScript.weight_each(_defs, item_id) * float(items[item_id])
	for lot_variant in _reserved_craft_lots(_reservation_credit_job_id):
		var lot: Dictionary = lot_variant
		total += ItemDefsScript.weight_each(_defs, str(lot.get("item_id", ""))) * float(lot.get("quantity", 0))
	return total

func bind_craft_reservation_authority(authority: RefCounted) -> bool:
	if authority == null or not authority.has_method("get_reserved_lots_for_holder") \
			or not authority.has_method("get_reservation_lots"): return false
	_craft_reservation_authority = weakref(authority)
	return true
func get_reserved_craft_lots() -> Array: return _reserved_craft_lots("")
func can_restore_craft_reservation(job_id: String, lots: Array, authority: RefCounted) -> bool:
	if not _reservation_matches(job_id, lots, authority): return false
	var totals: Dictionary = items.duplicate(true)
	var existing_ids: Dictionary = {}
	for existing_variant in get_lot_summary().get("lots", []) as Array:
		existing_ids[str((existing_variant as Dictionary).get("lot_id", ""))] = true
	var returning_weight: float = 0.0
	for lot_variant in lots:
		if not lot_variant is Dictionary: return false
		var lot: Dictionary = lot_variant
		var item_id: String = str(lot.get("item_id", ""))
		var quantity: int = int(lot.get("quantity", 0))
		if item_id.is_empty() or quantity <= 0 or existing_ids.has(str(lot.get("lot_id", ""))): return false
		totals[item_id] = int(totals.get(item_id, 0)) + quantity
		if int(totals[item_id]) > ItemDefsScript.max_stack(_defs, item_id): return false
		returning_weight += ItemDefsScript.weight_each(_defs, item_id) * float(quantity)
	return get_total_weight() - _reservation_weight(job_id) + returning_weight <= max_weight + 0.0001
func restore_craft_reservation(job_id: String, lots: Array, authority: RefCounted) -> bool:
	if not can_restore_craft_reservation(job_id, lots, authority): return false
	var before: Dictionary = get_summary()
	_reservation_credit_job_id = job_id
	for lot_variant in lots:
		var lot: Dictionary = lot_variant
		if add_lot(lot) != int(lot.get("quantity", 0)):
			_reservation_credit_job_id = ""
			apply_summary(before)
			return false
	_reservation_credit_job_id = ""
	return true
func _reserved_craft_lots(excluding_job_id: String) -> Array:
	if _craft_reservation_authority == null: return []
	var authority: Variant = _craft_reservation_authority.get_ref()
	if not authority is RefCounted: return []
	return (authority as RefCounted).call("get_reserved_lots_for_holder", get_holder_namespace(), excluding_job_id) as Array
func _reservation_weight(job_id: String) -> float:
	var total: float = 0.0
	if _craft_reservation_authority == null: return total
	var authority: Variant = _craft_reservation_authority.get_ref()
	if not authority is RefCounted: return total
	for lot_variant in (authority as RefCounted).call("get_reservation_lots", job_id, get_holder_namespace()) as Array:
		var lot: Dictionary = lot_variant
		total += ItemDefsScript.weight_each(_defs, str(lot.get("item_id", ""))) * float(lot.get("quantity", 0))
	return total
func _reservation_matches(job_id: String, lots: Array, authority: RefCounted) -> bool:
	return authority != null and _craft_reservation_authority != null \
		and _craft_reservation_authority.get_ref() == authority \
		and authority.call("get_reservation_lots", job_id, get_holder_namespace()) == lots
func get_quantity(item_id: String) -> int: return _lot_ledger.get_quantity(item_id)
func get_acceptable_quantity(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0: return 0
	var accepted: int = mini(qty, maxi(0, ItemDefsScript.max_stack(_defs, item_id) - get_quantity(item_id)))
	var weight_each: float = ItemDefsScript.weight_each(_defs, item_id)
	if weight_each > 0.0:
		accepted = mini(accepted, maxi(0, int(floor((max_weight - get_total_weight()) / weight_each + 0.0001))))
	return maxi(0, accepted)
func can_accept(item_id: String, qty: int) -> bool: return get_acceptable_quantity(item_id, qty) >= qty
func add_item(item_id: String, qty: int) -> int:
	var accepted: int = get_acceptable_quantity(item_id, qty)
	var added: int = _lot_ledger.add_standard(item_id, accepted) if accepted > 0 else 0
	if added > 0: _holder_namespace_established = true
	return added
func add_lot(lot: Dictionary) -> int:
	if lot.is_empty(): return 0
	var accepted: int = get_acceptable_quantity(str(lot.get("item_id", "")), int(lot.get("quantity", 0)))
	# A metadata lot is atomic. CargoTransfer first splits at the source, so a
	# rejected suffix remains there with its stable identity and can be retried.
	if accepted != int(lot.get("quantity", 0)): return 0
	var added: int = _lot_ledger.add_lot(lot)
	if added > 0: _holder_namespace_established = true
	return added
func take_lots(item_id: String, qty: int, preferred_ids: PackedStringArray = PackedStringArray()) -> Array:
	return _lot_ledger.take_lots(item_id, qty, preferred_ids)
func get_lot_summary() -> Dictionary: return _lot_ledger.get_summary()
func bind_holder_namespace(holder_namespace: String) -> bool:
	var bound: bool = _lot_ledger.bind_holder_namespace(holder_namespace)
	if bound: _holder_namespace_established = true
	return bound
func get_holder_namespace() -> String: return _lot_ledger.get_holder_namespace()
func remove_item(item_id: String, qty: int) -> int:
	var removed: int = mini(qty, get_quantity(item_id))
	return removed if removed > 0 and not _lot_ledger.take_lots(item_id, removed).is_empty() else 0
func get_items_by_category(category: String) -> Array:
	var out: Array = []
	var ids: Array = items.keys(); ids.sort()
	for item_id in ids:
		if ItemDefsScript.category(_defs, item_id) == category:
			out.append({"id": item_id, "quantity": get_quantity(item_id), "weight_each": ItemDefsScript.weight_each(_defs, item_id)})
	return out
func reset() -> void: _lot_ledger.clear()
func get_summary() -> Dictionary:
	return {"items": items.duplicate(true), "item_lots_v1": _lot_ledger.get_summary(), "max_weight": max_weight}
func apply_summary(summary) -> bool:
	if not (summary is Dictionary) or (summary as Dictionary).is_empty(): return false
	var d: Dictionary = summary as Dictionary
	# An established holder must never adopt a namespace from serialized data. A
	# pristine anonymous inventory may adopt one during its first restore.
	var current_lots: Dictionary = _lot_ledger.get_summary()
	var namespace_established: bool = _holder_namespace_established \
			or int(current_lots.get("sequence", 0)) > 0 \
			or not (current_lots.get("lots", []) as Array).is_empty()
	var candidate = ItemLotLedgerScript.new(_defs, get_holder_namespace()) \
			if namespace_established else ItemLotLedgerScript.new(_defs)
	if not candidate.apply_summary(d, get_holder_namespace()): return false
	var aggregate: Variant = d.get("items", null)
	if aggregate is Dictionary:
		var normalized_aggregate: Dictionary = {}
		for raw_item_id in (aggregate as Dictionary):
			var raw_quantity: Variant = (aggregate as Dictionary)[raw_item_id]
			if typeof(raw_quantity) != TYPE_INT and (typeof(raw_quantity) != TYPE_FLOAT or float(raw_quantity) != floorf(float(raw_quantity))):
				return false
			var quantity: int = int(raw_quantity)
			if quantity <= 0:
				return false
			normalized_aggregate[str(raw_item_id)] = quantity
		if normalized_aggregate != candidate.get_quantities(): return false
	var raw_weight: Variant = d.get("max_weight", max_weight)
	if (typeof(raw_weight) != TYPE_INT and typeof(raw_weight) != TYPE_FLOAT) \
			or not is_finite(float(raw_weight)):
		return false
	var restored_weight: float = float(raw_weight)
	if restored_weight < 0.0: return false
	var total: float = 0.0
	for item_id in candidate.get_quantities(): total += ItemDefsScript.weight_each(_defs, str(item_id)) * float(candidate.get_quantity(str(item_id)))
	if total > restored_weight + 0.0001: return false
	_lot_ledger = candidate; max_weight = restored_weight; _holder_namespace_established = true
	return true
