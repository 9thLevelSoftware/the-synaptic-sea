extends RefCounted
class_name ItemLotLedger

## Pure authority for item quantities and their quality/condition/provenance lots.
## Callers may read aggregate quantities, but every mutation passes through this
## model so unlike metadata is never collapsed into a quantity-only stack.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const SCHEMA: String = "item-lots-1"
const DEFAULT_QUALITY_SCORE: float = 0.5
const DEFAULT_QUALITY_TIER: String = "standard"
const DEFAULT_CONDITION: float = 1.0

var _definitions: Dictionary = {}
var _lots_by_id: Dictionary = {}
var _lot_order: Array[String] = []
var _holder_namespace: String = ""
var _namespace_locked: bool = false
var _sequence: int = 0

func _init(definitions: Dictionary = {}, holder_namespace: String = "") -> void:
	_definitions = definitions.duplicate(true) if not definitions.is_empty() \
		else ItemDefsScript.load_definitions()
	if holder_namespace.is_empty():
		_holder_namespace = _generate_anonymous_namespace()
	else:
		_holder_namespace = holder_namespace
		_namespace_locked = true

## Binds a newly-created anonymous ledger to its persistent holder identity.
## Rebinding after an ID has been issued would permit collisions and is rejected.
func bind_holder_namespace(holder_namespace: String) -> bool:
	if holder_namespace.is_empty():
		return false
	if holder_namespace == _holder_namespace:
		_namespace_locked = true
		return true
	if _namespace_locked or not _lots_by_id.is_empty() or _sequence > 0:
		return false
	_holder_namespace = holder_namespace
	_namespace_locked = true
	return true

func get_holder_namespace() -> String:
	return _holder_namespace

## Adds one complete valid lot when the item's aggregate stack ceiling permits.
## Supplied metadata is deep-copied. Duplicate, invalid, and partial admission is
## rejected so a remainder can never be stranded under the same stable identity.
func add_lot(lot: Dictionary) -> int:
	var normalized: Dictionary = _validated_lot(lot)
	if normalized.is_empty():
		return 0
	var lot_id: String = str(normalized.lot_id)
	if _lots_by_id.has(lot_id):
		return 0
	var item_id: String = str(normalized.item_id)
	var room: int = maxi(0, _max_stack(item_id) - get_quantity(item_id))
	var quantity: int = int(normalized.quantity)
	if quantity > room:
		return 0
	_store_lot(normalized)
	return quantity

## Quantity-only compatibility deposit. It creates a standard/full-condition lot
## with a stable generated identity rather than mutating an aggregate dictionary.
func add_standard(item_id: String, quantity: int) -> int:
	if item_id.is_empty() or quantity <= 0:
		return 0
	var room: int = maxi(0, _max_stack(item_id) - get_quantity(item_id))
	var accepted: int = mini(quantity, room)
	if accepted <= 0:
		return 0
	return add_lot({
		"lot_id": _next_generated_id("lot"),
		"item_id": item_id,
		"quantity": accepted,
		"quality_score": DEFAULT_QUALITY_SCORE,
		"quality_tier": DEFAULT_QUALITY_TIER,
		"condition": DEFAULT_CONDITION,
		"origin": {},
	})

## Removes exactly quantity or nothing. With preferred_ids, only those identities
## may satisfy the request. Without them, compatibility callers consume standard
## quality first and then all remaining lots in stable lot-ID order.
func take_lots(item_id: String, quantity: int, preferred_ids: PackedStringArray = PackedStringArray()) -> Array:
	if item_id.is_empty() or quantity <= 0:
		return []
	var candidates: Array[String] = []
	if not preferred_ids.is_empty():
		var selected: Dictionary = {}
		for preferred_id: String in preferred_ids:
			if selected.has(preferred_id):
				continue
			selected[preferred_id] = true
			var preferred: Variant = _lots_by_id.get(preferred_id, null)
			if preferred is Dictionary and str((preferred as Dictionary).item_id) == item_id:
				candidates.append(preferred_id)
	else:
		for lot_id: String in _lot_order:
			var lot: Dictionary = _lots_by_id[lot_id]
			if str(lot.item_id) == item_id:
				candidates.append(lot_id)
		candidates.sort_custom(func(a: String, b: String) -> bool:
			var a_standard: bool = str((_lots_by_id[a] as Dictionary).quality_tier) == DEFAULT_QUALITY_TIER
			var b_standard: bool = str((_lots_by_id[b] as Dictionary).quality_tier) == DEFAULT_QUALITY_TIER
			if a_standard != b_standard:
				return a_standard
			return a < b
		)
	var available: int = 0
	for lot_id: String in candidates:
		available += int((_lots_by_id[lot_id] as Dictionary).quantity)
	if available < quantity:
		return []

	var result: Array = []
	var remaining: int = quantity
	for lot_id: String in candidates:
		if remaining <= 0:
			break
		var stored: Dictionary = _lots_by_id[lot_id]
		var stored_quantity: int = int(stored.quantity)
		var amount: int = mini(stored_quantity, remaining)
		var outgoing: Dictionary = stored.duplicate(true)
		outgoing.quantity = amount
		if amount == stored_quantity:
			_erase_lot(lot_id)
		else:
			stored.quantity = stored_quantity - amount
			_lots_by_id[lot_id] = stored
			outgoing.lot_id = _next_split_id(lot_id)
		result.append(outgoing)
		remaining -= amount
	return result

func get_quantity(item_id: String) -> int:
	var total: int = 0
	for lot_id: String in _lot_order:
		var lot: Dictionary = _lots_by_id[lot_id]
		if str(lot.item_id) == item_id:
			total += int(lot.quantity)
	return total

func get_quantities() -> Dictionary:
	var result: Dictionary = {}
	for lot_id: String in _lot_order:
		var lot: Dictionary = _lots_by_id[lot_id]
		var item_id: String = str(lot.item_id)
		result[item_id] = int(result.get(item_id, 0)) + int(lot.quantity)
	return result

func get_summary() -> Dictionary:
	var lots: Array = []
	for lot_id: String in _lot_order:
		lots.append((_lots_by_id[lot_id] as Dictionary).duplicate(true))
	return {
		"schema": SCHEMA,
		"holder_namespace": _holder_namespace,
		"sequence": _sequence,
		"lots": lots,
	}

## Restores either a strict current lot payload (direct or under item_lots_v1) or
## an aggregate legacy inventory. Legacy cleanup is used only when no current
## payload field/envelope is present. Duplicate valid IDs are renamed
## deterministically without stealing a literal suffix used elsewhere.
func apply_summary(summary: Dictionary, legacy_holder_namespace: String = "") -> bool:
	if summary == null or summary.is_empty():
		return false
	if summary.has("item_lots_v1"):
		var wrapped: Variant = summary.get("item_lots_v1")
		if not (wrapped is Dictionary):
			return false
		return _apply_lot_payload(wrapped as Dictionary)
	if summary.has("schema") or summary.has("sequence") or summary.has("lots"):
		return _apply_lot_payload(summary)
	if summary.get("items", null) is Dictionary:
		return _apply_legacy_summary(summary, legacy_holder_namespace)
	return false

func clear() -> void:
	_lots_by_id.clear()
	_lot_order.clear()

func _apply_lot_payload(payload: Dictionary) -> bool:
	if not payload.has("schema") or str(payload.get("schema")) != SCHEMA \
			or not payload.has("holder_namespace") or str(payload.get("holder_namespace")).is_empty() \
			or not payload.has("sequence") or not _is_nonnegative_integer(payload.get("sequence")) \
			or not payload.has("lots") or not (payload.get("lots") is Array):
		return false
	var raw_lots: Array = payload.get("lots", []) as Array
	var restored_namespace: String = str(payload.get("holder_namespace"))
	if restored_namespace != _holder_namespace \
			and (_namespace_locked or not _lots_by_id.is_empty() or _sequence > 0):
		return false
	var reserved_ids: Dictionary = {}
	for raw: Variant in raw_lots:
		if raw is Dictionary:
			var raw_id: String = str((raw as Dictionary).get("lot_id", ""))
			if not raw_id.is_empty():
				reserved_ids[raw_id] = true
	var next_lots: Dictionary = {}
	var next_order: Array[String] = []
	var seen_original: Dictionary = {}
	var totals: Dictionary = {}
	for raw: Variant in raw_lots:
		if not (raw is Dictionary):
			return false
		var lot: Dictionary = _validated_lot(raw as Dictionary)
		if lot.is_empty():
			return false
		var original_id: String = str(lot.lot_id)
		if seen_original.has(original_id):
			lot.lot_id = _next_duplicate_id(original_id, reserved_ids, next_lots)
		else:
			seen_original[original_id] = true
		var item_id: String = str(lot.item_id)
		var new_total: int = int(totals.get(item_id, 0)) + int(lot.quantity)
		if new_total > _max_stack(item_id):
			return false
		totals[item_id] = new_total
		var assigned_id: String = str(lot.lot_id)
		next_lots[assigned_id] = lot
		next_order.append(assigned_id)
	_lots_by_id = next_lots
	_lot_order = next_order
	_holder_namespace = restored_namespace
	_namespace_locked = true
	_sequence = int(payload.get("sequence"))
	return true

func _apply_legacy_summary(summary: Dictionary, legacy_holder_namespace: String) -> bool:
	var restored_namespace: String = _holder_namespace
	if not legacy_holder_namespace.is_empty():
		if legacy_holder_namespace != _holder_namespace \
				and (_namespace_locked or not _lots_by_id.is_empty() or _sequence > 0):
			return false
		restored_namespace = legacy_holder_namespace
	var raw_items: Dictionary = summary.get("items", {}) as Dictionary
	var raw_quality: Variant = summary.get("material_quality", {})
	if summary.get("material_summary", null) is Dictionary:
		raw_quality = (summary.get("material_summary") as Dictionary).get("material_quality", raw_quality)
	var qualities: Dictionary = raw_quality as Dictionary if raw_quality is Dictionary else {}
	var next_lots: Dictionary = {}
	var next_order: Array[String] = []
	var ids: Array = raw_items.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for raw_item_id: Variant in ids:
		var item_id: String = str(raw_item_id)
		var quantity: int = _positive_integer_or_zero(raw_items[raw_item_id])
		if item_id.is_empty() or quantity <= 0:
			continue
		if quantity > _max_stack(item_id):
			return false
		var score: float = DEFAULT_QUALITY_SCORE
		var tier: String = DEFAULT_QUALITY_TIER
		if qualities.has(item_id) and _is_unit_number(qualities[item_id]):
			score = float(qualities[item_id])
			tier = QualityTierResolverScript.tier_for_score(score)
		var lot_id: String = "%s/legacy:%s" % [restored_namespace, item_id]
		var lot: Dictionary = {
			"lot_id": lot_id,
			"item_id": item_id,
			"quantity": quantity,
			"quality_score": score,
			"quality_tier": tier,
			"condition": DEFAULT_CONDITION,
			"origin": {},
		}
		next_lots[lot_id] = lot
		next_order.append(lot_id)
	_lots_by_id = next_lots
	_lot_order = next_order
	_holder_namespace = restored_namespace
	_namespace_locked = true
	return true

func _validated_lot(raw: Dictionary) -> Dictionary:
	var lot_id: String = str(raw.get("lot_id", ""))
	var item_id: String = str(raw.get("item_id", ""))
	var quantity: int = _positive_integer_or_zero(raw.get("quantity", null))
	var tier: String = str(raw.get("quality_tier", ""))
	var origin: Variant = raw.get("origin", null)
	if lot_id.is_empty() or item_id.is_empty() or quantity <= 0 or tier.is_empty():
		return {}
	if not _is_unit_number(raw.get("quality_score", null)) \
			or not _is_unit_number(raw.get("condition", null)) \
			or not (origin is Dictionary):
		return {}
	var score: float = float(raw.quality_score)
	if not QualityTierResolverScript.TIER_ORDER.has(tier) \
			or QualityTierResolverScript.tier_for_score(score) != tier:
		return {}
	return {
		"lot_id": lot_id,
		"item_id": item_id,
		"quantity": quantity,
		"quality_score": score,
		"quality_tier": tier,
		"condition": float(raw.condition),
		"origin": (origin as Dictionary).duplicate(true),
	}

func _store_lot(lot: Dictionary) -> void:
	var lot_id: String = str(lot.lot_id)
	_lots_by_id[lot_id] = lot.duplicate(true)
	_lot_order.append(lot_id)
	_namespace_locked = true

func _erase_lot(lot_id: String) -> void:
	_lots_by_id.erase(lot_id)
	_lot_order.erase(lot_id)

func _max_stack(item_id: String) -> int:
	return maxi(1, ItemDefsScript.max_stack(_definitions, item_id))

func _next_generated_id(prefix: String) -> String:
	while true:
		_sequence += 1
		_namespace_locked = true
		var candidate: String = "%s/%s-%06d" % [_holder_namespace, prefix, _sequence]
		if not _lots_by_id.has(candidate):
			return candidate
	return ""

func _next_split_id(_parent_id: String) -> String:
	while true:
		_sequence += 1
		_namespace_locked = true
		var candidate: String = "%s/split-%06d" % [_holder_namespace, _sequence]
		if not _lots_by_id.has(candidate):
			return candidate
	return ""

static func _next_duplicate_id(base_id: String, reserved_ids: Dictionary, assigned: Dictionary) -> String:
	var suffix: int = 2
	while true:
		var candidate: String = "%s#%d" % [base_id, suffix]
		if not reserved_ids.has(candidate) and not assigned.has(candidate):
			return candidate
		suffix += 1
	return ""

static func _positive_integer_or_zero(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return maxi(0, int(value))
	if typeof(value) == TYPE_FLOAT:
		var numeric: float = float(value)
		if is_finite(numeric) and numeric == floorf(numeric):
			return maxi(0, int(numeric))
	return 0

static func _is_nonnegative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	if typeof(value) == TYPE_FLOAT:
		var numeric: float = float(value)
		return is_finite(numeric) and numeric >= 0.0 and numeric == floorf(numeric)
	return false

static func _is_unit_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric >= 0.0 and numeric <= 1.0

static func _generate_anonymous_namespace() -> String:
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	return "anonymous:%s" % random_bytes.hex_encode()
