extends RefCounted
class_name PendingOutputStore

## Ship-owned authority for physical station output and recoverable refunds.
## Records remain as empty tombstones so a restored/stale producer cannot
## publish the same receipt twice.

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const SCHEMA: String = "pending-outputs-1"
const PURPOSE_OUTPUT: String = "output"
const PURPOSE_REFUND: String = "refund"
const STATE_PENDING: String = "pending"
const STATE_COLLECTED: String = "collected"
const STATE_ORPHANED: String = "orphaned"
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0
const TOP_LEVEL_KEYS: Array[String] = ["schema", "ship_id", "records"]
const RECORD_KEYS: Array[String] = [
	"receipt_id", "ship_id", "station_instance_id", "producer_kind",
	"producer_id", "purpose", "source_holder_id", "state",
	"original_lots", "remaining_lots", "collected_quantities",
]
const LOT_KEYS: Array[String] = [
	"lot_id", "item_id", "quantity", "quality_score", "quality_tier",
	"condition", "origin",
]

var ship_id: String = ""
var _records: Dictionary = {} # receipt_id -> strict record


func configure(p_ship_id: String) -> bool:
	if p_ship_id.is_empty() or (not ship_id.is_empty() and ship_id != p_ship_id):
		return false
	ship_id = p_ship_id
	return true


## Returns true only for the first publication. An identical replay returns
## false but can be distinguished from a conflict with receipt_matches().
func deposit_once(receipt_id: String, lots: Array, metadata: Dictionary = {}) -> bool:
	if receipt_id.is_empty() or ship_id.is_empty():
		return false
	var normalized: Dictionary = _normalized_deposit(receipt_id, lots, metadata)
	if normalized.is_empty() or _records.has(receipt_id):
		return false
	if _lot_ids_overlap_other_receipts(normalized.original_lots as Array):
		return false
	_records[receipt_id] = normalized
	return true


func receipt_matches(receipt_id: String, lots: Array, metadata: Dictionary = {}) -> bool:
	var existing: Variant = _records.get(receipt_id, null)
	if not existing is Dictionary:
		return false
	var normalized: Dictionary = _normalized_deposit(receipt_id, lots, metadata)
	if normalized.is_empty():
		return false
	var record: Dictionary = existing
	return _immutable_projection(record) == _immutable_projection(normalized)


func has_receipt(receipt_id: String) -> bool:
	return _records.has(receipt_id)


func get_record(receipt_id: String) -> Dictionary:
	var record: Variant = _records.get(receipt_id, null)
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


func list_records_for_station(station_instance_id: String, include_empty: bool = false) -> Array:
	var out: Array = []
	var receipt_ids: Array = _records.keys()
	receipt_ids.sort()
	for receipt_variant in receipt_ids:
		var record: Dictionary = _records[receipt_variant]
		if str(record.station_instance_id) != station_instance_id:
			continue
		if not include_empty and (record.remaining_lots as Array).is_empty():
			continue
		out.append(record.duplicate(true))
	return out


func get_pending_mass_for_station(station_instance_id: String, definitions: RefCounted) -> float:
	if definitions == null or not definitions.has_method("get_weight_each"):
		return 0.0
	var total: float = 0.0
	for record_variant in list_records_for_station(station_instance_id):
		for lot_variant in (record_variant as Dictionary).remaining_lots:
			var lot: Dictionary = lot_variant
			total += float(definitions.call("get_weight_each", str(lot.item_id))) * float(lot.quantity)
	return total


## Moves every quantity the destination can currently accept. Exact whole lots
## keep their IDs; partial moves receive a deterministic receipt-derived split ID.
func collect_receipt(receipt_id: String, destination: RefCounted) -> Dictionary:
	if destination == null or not destination.has_method("add_lot"):
		return {"ok": false, "reason": "missing_destination", "transferred": 0, "lots": []}
	var existing: Variant = _records.get(receipt_id, null)
	if not existing is Dictionary:
		return {"ok": false, "reason": "unknown_receipt", "transferred": 0, "lots": []}
	var record: Dictionary = (existing as Dictionary).duplicate(true)
	var remaining: Array = record.remaining_lots as Array
	var kept: Array = []
	var transferred_lots: Array = []
	var transferred: int = 0
	var collected: Dictionary = (record.collected_quantities as Dictionary).duplicate(true)
	for lot_variant in remaining:
		var lot: Dictionary = (lot_variant as Dictionary).duplicate(true)
		var quantity: int = int(lot.quantity)
		var accepted: int = _acceptable_quantity(destination, str(lot.item_id), quantity)
		if accepted <= 0:
			kept.append(lot)
			continue
		var outgoing: Dictionary = lot.duplicate(true)
		outgoing.quantity = accepted
		if accepted < quantity:
			var offset: int = int(collected.get(str(lot.lot_id), 0))
			outgoing.lot_id = "%s/collect:%s:%06d" % [receipt_id, str(lot.lot_id), offset]
		if int(destination.call("add_lot", outgoing)) != accepted:
			kept.append(lot)
			continue
		transferred += accepted
		transferred_lots.append(outgoing.duplicate(true))
		collected[str(lot.lot_id)] = int(collected.get(str(lot.lot_id), 0)) + accepted
		if accepted < quantity:
			lot.quantity = quantity - accepted
			kept.append(lot)
	record.remaining_lots = kept
	record.collected_quantities = collected
	if kept.is_empty():
		record.state = STATE_COLLECTED
	_records[receipt_id] = record
	return {
		"ok": true,
		"reason": "" if transferred > 0 else "destination_full",
		"transferred": transferred,
		"lots": transferred_lots,
		"remaining_lots": kept.duplicate(true),
	}


func peek_remaining_lots(receipt_id: String) -> Array:
	var record: Variant = _records.get(receipt_id, null)
	return ((record as Dictionary).remaining_lots as Array).duplicate(true) \
		if record is Dictionary else []


## Called only after every exact lot has been durably registered in a floor
## holder descriptor. The expected payload prevents acknowledging stale data.
func acknowledge_orphaned(receipt_id: String, expected_lots: Array) -> bool:
	var existing: Variant = _records.get(receipt_id, null)
	if not existing is Dictionary:
		return false
	var record: Dictionary = (existing as Dictionary).duplicate(true)
	if record.remaining_lots != expected_lots or expected_lots.is_empty():
		return false
	var collected: Dictionary = record.collected_quantities as Dictionary
	for lot_variant in expected_lots:
		var lot: Dictionary = lot_variant
		collected[str(lot.lot_id)] = int(collected.get(str(lot.lot_id), 0)) + int(lot.quantity)
	record.collected_quantities = collected
	record.remaining_lots = []
	record.state = STATE_ORPHANED
	_records[receipt_id] = record
	return true


func get_summary() -> Dictionary:
	var records: Array = []
	var receipt_ids: Array = _records.keys()
	receipt_ids.sort()
	for receipt_id in receipt_ids:
		records.append((_records[receipt_id] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "ship_id": ship_id, "records": records}


## Strict atomic current restore. Missing payload is handled by ShipInstance as
## a legacy empty store; malformed present data is rejected here.
func apply_summary(summary: Dictionary) -> bool:
	var payload: Variant = summary.get("pending_outputs_v1", summary)
	if not payload is Dictionary:
		return false
	var data: Dictionary = payload
	if not _has_exact_keys(data, TOP_LEVEL_KEYS) \
			or typeof(data.get("schema", null)) != TYPE_STRING \
			or str(data.get("schema", "")) != SCHEMA \
			or typeof(data.get("ship_id", null)) != TYPE_STRING \
			or str(data.ship_id).is_empty() \
			or not data.get("records", null) is Array:
		return false
	if not ship_id.is_empty() and ship_id != str(data.ship_id):
		return false
	var candidate = get_script().new()
	if not candidate.configure(str(data.ship_id)):
		return false
	for record_variant in data.records:
		if not record_variant is Dictionary:
			return false
		var record: Dictionary = record_variant
		if not _has_exact_keys(record, RECORD_KEYS) \
				or typeof(record.get("receipt_id", null)) != TYPE_STRING \
				or typeof(record.get("ship_id", null)) != TYPE_STRING \
				or str(record.get("ship_id", "")) != str(data.ship_id):
			return false
		var receipt_id: String = str(record.receipt_id)
		var original_v: Variant = record.get("original_lots", null)
		var remaining_v: Variant = record.get("remaining_lots", null)
		if not original_v is Array or not remaining_v is Array:
			return false
		var metadata: Dictionary = {
			"station_instance_id": record.get("station_instance_id", null),
			"producer_kind": record.get("producer_kind", null),
			"producer_id": record.get("producer_id", null),
			"purpose": record.get("purpose", null),
			"source_holder_id": record.get("source_holder_id", null),
		}
		if not candidate.deposit_once(receipt_id, original_v as Array, metadata):
			return false
		var restored: Dictionary = candidate._records[receipt_id]
		var normalized_remaining: Array = candidate._validated_lots(remaining_v as Array)
		if normalized_remaining.size() != (remaining_v as Array).size() \
				or not _remaining_is_subset(normalized_remaining, restored.original_lots as Array):
			return false
		if typeof(record.get("state", null)) != TYPE_STRING:
			return false
		var state: String = str(record.state)
		if not state in [STATE_PENDING, STATE_COLLECTED, STATE_ORPHANED]:
			return false
		if state == STATE_PENDING and normalized_remaining.is_empty():
			return false
		if state != STATE_PENDING and not normalized_remaining.is_empty():
			return false
		var collected_v: Variant = record.get("collected_quantities", null)
		if not collected_v is Dictionary \
				or not _collected_matches(restored.original_lots as Array, normalized_remaining, collected_v as Dictionary):
			return false
		var normalized_collected: Dictionary = {}
		for lot_id_variant in (collected_v as Dictionary):
			normalized_collected[str(lot_id_variant)] = _positive_integer(
				(collected_v as Dictionary)[lot_id_variant])
		restored.remaining_lots = normalized_remaining
		restored.collected_quantities = normalized_collected
		restored.state = state
		candidate._records[receipt_id] = restored
	ship_id = candidate.ship_id
	_records = candidate._records
	return true


func _normalized_deposit(receipt_id: String, lots: Array, metadata: Dictionary) -> Dictionary:
	for key in ["station_instance_id", "producer_kind", "producer_id", "purpose"]:
		if typeof(metadata.get(key, null)) != TYPE_STRING or str(metadata.get(key, "")).is_empty():
			return {}
	var purpose: String = str(metadata.purpose)
	if not purpose in [PURPOSE_OUTPUT, PURPOSE_REFUND]:
		return {}
	var source_holder: Variant = metadata.get("source_holder_id", "")
	if typeof(source_holder) != TYPE_STRING:
		return {}
	var normalized_lots: Array = _validated_lots(lots)
	if normalized_lots.size() != lots.size() or normalized_lots.is_empty():
		return {}
	return {
		"receipt_id": receipt_id,
		"ship_id": ship_id,
		"station_instance_id": str(metadata.station_instance_id),
		"producer_kind": str(metadata.producer_kind),
		"producer_id": str(metadata.producer_id),
		"purpose": purpose,
		"source_holder_id": str(source_holder),
		"state": STATE_PENDING,
		"original_lots": normalized_lots.duplicate(true),
		"remaining_lots": normalized_lots.duplicate(true),
		"collected_quantities": {},
	}


func _validated_lots(lots: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for lot_variant in lots:
		if not lot_variant is Dictionary:
			return []
		var lot: Dictionary = lot_variant
		if not _has_exact_keys(lot, LOT_KEYS) \
				or typeof(lot.get("lot_id", null)) != TYPE_STRING \
				or typeof(lot.get("item_id", null)) != TYPE_STRING \
				or typeof(lot.get("quality_tier", null)) != TYPE_STRING:
			return []
		var lot_id: String = str(lot.get("lot_id", ""))
		var item_id: String = str(lot.get("item_id", ""))
		var quantity: int = _positive_integer(lot.get("quantity", null))
		var tier: String = str(lot.get("quality_tier", ""))
		var origin: Variant = lot.get("origin", null)
		if lot_id.is_empty() or item_id.is_empty() or quantity <= 0 or seen.has(lot_id) \
				or not _is_unit_number(lot.get("quality_score", null)) \
				or not _is_unit_number(lot.get("condition", null)) \
				or not origin is Dictionary \
				or not QualityTierResolverScript.TIER_ORDER.has(tier) \
				or QualityTierResolverScript.tier_for_score(float(lot.quality_score)) != tier:
			return []
		seen[lot_id] = true
		out.append({
			"lot_id": lot_id, "item_id": item_id, "quantity": quantity,
			"quality_score": float(lot.quality_score), "quality_tier": tier,
			"condition": float(lot.condition), "origin": (origin as Dictionary).duplicate(true),
		})
	return out


func _lot_ids_overlap_other_receipts(lots: Array) -> bool:
	var incoming: Dictionary = {}
	for lot in lots:
		incoming[str((lot as Dictionary).lot_id)] = true
	for record_variant in _records.values():
		for lot_variant in (record_variant as Dictionary).original_lots:
			if incoming.has(str((lot_variant as Dictionary).lot_id)):
				return true
	return false


static func _immutable_projection(record: Dictionary) -> Dictionary:
	return {
		"receipt_id": record.receipt_id, "ship_id": record.ship_id,
		"station_instance_id": record.station_instance_id,
		"producer_kind": record.producer_kind, "producer_id": record.producer_id,
		"purpose": record.purpose, "source_holder_id": record.source_holder_id,
		"original_lots": record.original_lots,
	}


static func _remaining_is_subset(remaining: Array, original: Array) -> bool:
	var original_by_id: Dictionary = {}
	for lot_variant in original:
		original_by_id[str((lot_variant as Dictionary).lot_id)] = lot_variant
	for lot_variant in remaining:
		var lot: Dictionary = lot_variant
		var original_lot: Variant = original_by_id.get(str(lot.lot_id), null)
		if not original_lot is Dictionary or int(lot.quantity) > int((original_lot as Dictionary).quantity):
			return false
		var comparable: Dictionary = lot.duplicate(true)
		comparable.quantity = int((original_lot as Dictionary).quantity)
		if comparable != original_lot:
			return false
	return true


static func _collected_matches(original: Array, remaining: Array, collected: Dictionary) -> bool:
	var remaining_by_id: Dictionary = {}
	for lot_variant in remaining:
		remaining_by_id[str((lot_variant as Dictionary).lot_id)] = int((lot_variant as Dictionary).quantity)
	var expected_by_id: Dictionary = {}
	for lot_variant in original:
		var lot: Dictionary = lot_variant
		var lot_id: String = str(lot.lot_id)
		var expected: int = int(lot.quantity) - int(remaining_by_id.get(lot_id, 0))
		if expected > 0:
			expected_by_id[lot_id] = expected
	if collected.size() != expected_by_id.size():
		return false
	for key_variant in collected:
		if typeof(key_variant) != TYPE_STRING:
			return false
		var lot_id: String = str(key_variant)
		if not expected_by_id.has(lot_id) \
				or _positive_integer(collected.get(lot_id, null)) != int(expected_by_id[lot_id]):
			return false
	return true


static func _acceptable_quantity(destination: RefCounted, item_id: String, requested: int) -> int:
	if requested <= 0:
		return 0
	if destination.has_method("get_acceptable_quantity"):
		return clampi(int(destination.call("get_acceptable_quantity", item_id, requested)), 0, requested)
	if not destination.has_method("can_accept"):
		return requested
	var low: int = 0
	var high: int = requested
	while low < high:
		var mid: int = (low + high + 1) / 2
		if bool(destination.call("can_accept", item_id, mid)):
			low = mid
		else:
			high = mid - 1
	return low


static func _positive_integer(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var numeric: float = float(value)
	if not is_finite(numeric) or numeric <= 0.0 \
			or numeric > MAX_SAFE_JSON_INTEGER or numeric != floorf(numeric):
		return 0
	return int(numeric)


static func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _is_unit_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0
