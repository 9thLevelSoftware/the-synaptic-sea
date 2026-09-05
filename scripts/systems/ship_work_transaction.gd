extends RefCounted
class_name ShipWorkTransaction

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

## FC-14 transaction authority for attended physical ship work. Inventory lots
## move into exact escrow before timed work begins. Only commit() may invoke the
## supplied physical mutation, and a committed work_id always returns its stored
## receipt without invoking staging, mutation, noise, or XP a second time.

const SCHEMA: String = "ship-work-transactions-1"
const STATE_PREPARED: String = "prepared"
const STATE_ACTIVE: String = "active"
const STATE_PAUSED: String = "paused"
const STATE_READY: String = "ready"
const STATE_COMMITTED: String = "committed"
const STATE_CANCELLED: String = "cancelled"
const STATE_REFUND_BLOCKED: String = "refund_blocked"

var ship_id: String = ""
var sequence: int = 0
var _records: Dictionary = {}
var _order: Array[String] = []
## Process-local commit latch. This is deliberately absent from get_summary():
## restore can only represent stable transaction states, never a callback frame.
var _commit_in_flight: Dictionary = {}


func configure(owner_ship_id: String) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var requested_owner: String = owner_ship_id.strip_edges()
	if requested_owner.is_empty():
		return false
	if ship_id.is_empty():
		ship_id = requested_owner
		return true
	return ship_id == requested_owner


func create_work_id(prefix: String = "work") -> String:
	if not _commit_in_flight.is_empty():
		return ""
	sequence += 1
	var safe_prefix: String = prefix if not prefix.is_empty() else "work"
	return "%s/%s:%d" % [ship_id, safe_prefix, sequence]


## Reserve the request's concrete lot IDs atomically. requirements are actual
## inventory item IDs and quantities; aliases must already be resolved by the
## coordinator so escrow never invents which material was paid.
func prepare(request: Dictionary, source_inventory, requirements: Dictionary = {}) -> Dictionary:
	if not _commit_in_flight.is_empty():
		return {"ok": false, "reason": "commit_in_flight", "work_id": str(request.get("work_id", ""))}
	var checked: Dictionary = _validate_request(request, source_inventory, requirements)
	if not bool(checked.get("ok", false)):
		return checked
	var work_id: String = str(request.get("work_id", ""))
	if _records.has(work_id):
		return {"ok": false, "reason": "duplicate_work_id", "work_id": work_id}
	var selected_ids: PackedStringArray = checked.get("selected_lot_ids", PackedStringArray())
	var escrow: Array = []
	var item_ids: Array = requirements.keys()
	item_ids.sort()
	for item_v in item_ids:
		var item_id: String = str(item_v)
		var quantity: int = int(requirements[item_v])
		var taken: Array = source_inventory.take_lots(item_id, quantity, selected_ids)
		if taken.is_empty():
			_refund_detached_lots(source_inventory, escrow)
			return {"ok": false, "reason": "reserve_failed", "work_id": work_id}
		escrow.append_array(taken)
	var record: Dictionary = request.duplicate(true)
	record["state"] = STATE_PREPARED
	record["escrow"] = escrow.duplicate(true)
	record["requirements"] = requirements.duplicate(true)
	record["progress"] = 0.0
	record["commit_receipt_id"] = ""
	record["receipt"] = {}
	record["last_reason"] = ""
	_records[work_id] = record
	_order.append(work_id)
	return {"ok": true, "reason": "prepared", "work_id": work_id, "escrow": escrow.duplicate(true)}


## Start the catalog WorkAction after reservation. A failed tool/skill/material
## gate refunds the complete escrow immediately, leaving no staged transaction.
func start(work_id: String, driver, context: Dictionary, source_inventory = null) -> Dictionary:
	if not _commit_in_flight.is_empty():
		return {"ok": false, "reason": "commit_in_flight", "work_id": work_id}
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) != STATE_PREPARED:
		return {"ok": false, "reason": "not_prepared", "work_id": work_id}
	if driver == null or not driver.has_method("start_action"):
		return _fail_start_and_refund(work_id, source_inventory, driver, "missing_driver")
	if not bool(driver.call("start_action", str(record.get("action_id", "")), str(record.get("target_id", "")), context)):
		var reason: String = "start_failed"
		var work = driver.get("work")
		if work != null and str(work.get("block_reason")) != "":
			reason = str(work.get("block_reason"))
		return _fail_start_and_refund(work_id, source_inventory, driver, reason)
	record["state"] = STATE_ACTIVE
	record["last_reason"] = ""
	_records[work_id] = record
	return {"ok": true, "reason": "active", "work_id": work_id}


## Scene wrappers that already own a WorkActionChannel use the same transaction
## state without creating a second driver.
func activate(work_id: String) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) != STATE_PREPARED:
		return false
	record["state"] = STATE_ACTIVE
	_records[work_id] = record
	return true


func pause(work_id: String, driver, reason: String = "paused") -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) != STATE_ACTIVE or driver == null:
		return false
	if driver.has_method("pause") and not bool(driver.call("pause")):
		return false
	record["state"] = STATE_PAUSED
	record["progress"] = float(driver.call("progress_ratio")) if driver.has_method("progress_ratio") else float(record.get("progress", 0.0))
	record["last_reason"] = reason
	_records[work_id] = record
	return true


func resume(work_id: String, driver, context: Dictionary = {}) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) != STATE_PAUSED or driver == null:
		return false
	if driver.has_method("resume") and not bool(driver.call("resume", context)):
		return false
	record["state"] = STATE_ACTIVE
	record["last_reason"] = ""
	_records[work_id] = record
	return true


func pause_channel(work_id: String, progress: float, reason: String = "paused") -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty():
		return false
	if str(record.get("state", "")) == STATE_PAUSED:
		record["last_reason"] = reason
		record["progress"] = clampf(progress, 0.0, 1.0)
		_records[work_id] = record
		return true
	if str(record.get("state", "")) != STATE_ACTIVE:
		return false
	record["state"] = STATE_PAUSED
	record["progress"] = clampf(progress, 0.0, 1.0)
	record["last_reason"] = reason
	_records[work_id] = record
	return true


func resume_channel(work_id: String) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) != STATE_PAUSED:
		return false
	record["state"] = STATE_ACTIVE
	record["last_reason"] = ""
	_records[work_id] = record
	return true


func sync_progress(work_id: String, driver) -> void:
	if not _commit_in_flight.is_empty():
		return
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or driver == null:
		return
	if driver.has_method("progress_ratio"):
		record["progress"] = float(driver.call("progress_ratio"))
	_records[work_id] = record


func mark_completed(work_id: String, driver) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) not in [STATE_ACTIVE, STATE_PAUSED]:
		return false
	if driver == null or str(driver.call("get_status")) != "completed":
		return false
	record["state"] = STATE_READY
	record["progress"] = 1.0
	_records[work_id] = record
	return true


func mark_channel_completed(work_id: String) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty() or str(record.get("state", "")) not in [STATE_ACTIVE, STATE_PAUSED]:
		return false
	record["state"] = STATE_READY
	record["progress"] = 1.0
	_records[work_id] = record
	return true


## Revalidate immutable identity and current target revision before invoking the
## scene/model coordinator. The callable is invoked once in the lifetime of the
## work ID; a duplicate call returns the stored receipt.
func commit(work_id: String, context: Dictionary) -> Dictionary:
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty():
		return {"ok": false, "reason": "unknown_work", "work_id": work_id}
	if str(record.get("state", "")) == STATE_COMMITTED:
		var prior: Dictionary = (record.get("receipt", {}) as Dictionary).duplicate(true)
		prior["ok"] = true
		prior["already_committed"] = true
		return prior
	if _commit_in_flight.has(work_id):
		return {"ok": false, "reason": "commit_in_flight", "work_id": work_id, "escrow_retained": true}
	if str(record.get("state", "")) != STATE_READY:
		return {"ok": false, "reason": "not_ready", "work_id": work_id}
	var denial: String = _commit_denial(record, context)
	if not denial.is_empty():
		record["last_reason"] = denial
		_records[work_id] = record
		return {"ok": false, "reason": denial, "work_id": work_id, "escrow_retained": true}
	_commit_in_flight[work_id] = true
	var stage_v: Variant = context.get("stage", Callable())
	if stage_v is Callable and (stage_v as Callable).is_valid():
		var stage_result: Variant = (stage_v as Callable).call(record.duplicate(true))
		if not (stage_result is Dictionary) or not bool((stage_result as Dictionary).get("ok", false)):
			var stage_reason: String = str((stage_result as Dictionary).get("reason", "staging_failed")) if stage_result is Dictionary else "staging_failed"
			var source_inventory = context.get("source_inventory", null)
			_commit_in_flight.erase(work_id)
			if source_inventory != null:
				var refunded: Dictionary = cancel(work_id, source_inventory, context.get("driver", null), stage_reason)
				if bool(refunded.get("ok", false)):
					return {
						"ok": false,
						"reason": stage_reason,
						"work_id": work_id,
						"refunded": true,
						"returned_lots": refunded.get("returned_lots", []),
					}
			record = _record_ref(work_id)
			record["last_reason"] = stage_reason
			_records[work_id] = record
			return {"ok": false, "reason": stage_reason, "work_id": work_id, "escrow_retained": true}
	var commit_v: Variant = context.get("commit", Callable())
	if not (commit_v is Callable) or not (commit_v as Callable).is_valid():
		_commit_in_flight.erase(work_id)
		return {"ok": false, "reason": "missing_commit", "work_id": work_id, "escrow_retained": true}
	var applied_v: Variant = (commit_v as Callable).call(record.duplicate(true))
	if not (applied_v is Dictionary) or not bool((applied_v as Dictionary).get("ok", false)):
		var apply_reason: String = str((applied_v as Dictionary).get("reason", "commit_failed")) if applied_v is Dictionary else "commit_failed"
		record["last_reason"] = apply_reason
		_records[work_id] = record
		_commit_in_flight.erase(work_id)
		return {"ok": false, "reason": apply_reason, "work_id": work_id, "escrow_retained": true}
	var applied: Dictionary = applied_v as Dictionary
	var receipt_id: String = "%s:commit" % work_id
	var receipt: Dictionary = {
		"ok": true,
		"reason": "committed",
		"work_id": work_id,
		"commit_receipt_id": receipt_id,
		"committed_target_revision": str(applied.get("committed_target_revision", context.get("target_revision", ""))),
		"consumed_lots": (record.get("escrow", []) as Array).duplicate(true),
		"returned_lots": (applied.get("returned_lots", []) as Array).duplicate(true) if applied.get("returned_lots", []) is Array else [],
		"awarded_event_ids": (applied.get("awarded_event_ids", []) as Array).duplicate(true) if applied.get("awarded_event_ids", []) is Array else [],
		"noise": maxf(0.0, float(applied.get("noise", 0.0))),
		"result": applied.duplicate(true),
		"already_committed": false,
	}
	record["state"] = STATE_COMMITTED
	record["commit_receipt_id"] = receipt_id
	record["receipt"] = receipt.duplicate(true)
	record["last_reason"] = ""
	_records[work_id] = record
	_commit_in_flight.erase(work_id)
	return receipt


## Explicit interruption/cancel returns the exact lot dictionaries. Committed
## work is immutable; a repeated cancellation of a cancelled ID is a no-op.
func cancel(work_id: String, source_inventory, driver = null, reason: String = "cancelled") -> Dictionary:
	var record: Dictionary = _record_ref(work_id)
	if record.is_empty():
		return {"ok": false, "reason": "unknown_work", "work_id": work_id}
	if _commit_in_flight.has(work_id):
		return {"ok": false, "reason": "commit_in_flight", "work_id": work_id, "escrow_retained": true}
	var state: String = str(record.get("state", ""))
	if state == STATE_COMMITTED:
		return {"ok": false, "reason": "already_committed", "work_id": work_id}
	if state == STATE_CANCELLED:
		return {"ok": true, "reason": "already_cancelled", "work_id": work_id, "returned_lots": []}
	if source_inventory == null or not source_inventory.has_method("add_lot") \
			or not source_inventory.has_method("get_summary") or not source_inventory.has_method("apply_summary"):
		return {"ok": false, "reason": "missing_source_holder", "work_id": work_id}
	var escrow: Array = (record.get("escrow", []) as Array).duplicate(true)
	if not _refund_lots_atomically(source_inventory, escrow):
		record["state"] = STATE_REFUND_BLOCKED
		record["last_reason"] = "refund_blocked"
		_records[work_id] = record
		return {"ok": false, "reason": "refund_blocked", "work_id": work_id, "escrow_retained": true}
	if driver != null and driver.has_method("reset"):
		driver.call("reset")
	record["state"] = STATE_CANCELLED
	record["last_reason"] = reason
	record["escrow"] = []
	_records[work_id] = record
	return {"ok": true, "reason": reason, "work_id": work_id, "returned_lots": escrow}


func get_record(work_id: String) -> Dictionary:
	return _record_ref(work_id).duplicate(true)


func get_escrow(work_id: String) -> Array:
	var record: Dictionary = _record_ref(work_id)
	return (record.get("escrow", []) as Array).duplicate(true) if record.get("escrow", []) is Array else []


func get_summary() -> Dictionary:
	# A READY snapshot taken from inside the mutation callback would falsely imply
	# that no physical effect has happened yet. P19 owns whole-save coordination;
	# P12 fails closed instead of exporting that unstable frame.
	if not _commit_in_flight.is_empty():
		return {}
	var records: Array = []
	for work_id: String in _order:
		if _records.has(work_id):
			records.append((_records[work_id] as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "ship_id": ship_id, "sequence": sequence, "transactions": records}


func apply_summary(summary: Dictionary) -> bool:
	if not _commit_in_flight.is_empty():
		return false
	if str(summary.get("schema", "")) != SCHEMA or str(summary.get("ship_id", "")).is_empty() \
			or not (summary.get("transactions", null) is Array) \
			or typeof(summary.get("sequence", null)) != TYPE_INT or int(summary.get("sequence", -1)) < 0:
		return false
	var owner_ship_id: String = str(summary.get("ship_id"))
	# Once configured, a ledger's owner is immutable. An unconfigured instance may
	# bind while restoring, but a ship-b ledger must never ingest ship-a receipts.
	if not ship_id.is_empty() and ship_id != owner_ship_id:
		return false
	var next_records: Dictionary = {}
	var next_order: Array[String] = []
	var escrow_lot_ids: Dictionary = {}
	for raw_v in summary.get("transactions", []) as Array:
		if not (raw_v is Dictionary):
			return false
		var raw: Dictionary = raw_v as Dictionary
		var work_id: String = str(raw.get("work_id", ""))
		if work_id.is_empty() or next_records.has(work_id) or not _valid_restored_record(raw, owner_ship_id):
			return false
		for lot_v in raw.get("escrow", []) as Array:
			var lot_id: String = str((lot_v as Dictionary).get("lot_id", ""))
			if escrow_lot_ids.has(lot_id):
				return false
			escrow_lot_ids[lot_id] = true
		next_records[work_id] = raw.duplicate(true)
		next_order.append(work_id)
	ship_id = owner_ship_id
	sequence = int(summary.get("sequence"))
	_records = next_records
	_order = next_order
	return true


static func _valid_restored_record(record: Dictionary, owner_ship_id: String) -> bool:
	for key in ["work_id", "ship_id", "target_id", "target_revision", "action_id", "source_holder_id", "state"]:
		if str(record.get(key, "")).is_empty():
			return false
	var work_id: String = str(record.get("work_id"))
	if str(record.get("ship_id")) != owner_ship_id or work_id.is_empty():
		return false
	var state: String = str(record.get("state"))
	if state not in [STATE_PREPARED, STATE_ACTIVE, STATE_PAUSED, STATE_READY, STATE_COMMITTED, STATE_CANCELLED, STATE_REFUND_BLOCKED]:
		return false
	var progress_v: Variant = record.get("progress", null)
	if typeof(progress_v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(progress_v)) \
			or float(progress_v) < 0.0 or float(progress_v) > 1.0:
		return false
	if not (record.get("escrow", null) is Array) or not (record.get("requirements", null) is Dictionary) \
			or not (record.get("receipt", null) is Dictionary):
		return false
	var lot_ids: Dictionary = {}
	var escrow_quantities: Dictionary = {}
	for lot_v in record.get("escrow") as Array:
		if not (lot_v is Dictionary) or not _valid_lot(lot_v as Dictionary):
			return false
		var lot_id: String = str((lot_v as Dictionary).get("lot_id"))
		if lot_ids.has(lot_id):
			return false
		lot_ids[lot_id] = true
		var lot: Dictionary = lot_v as Dictionary
		var item_id: String = str(lot.get("item_id"))
		escrow_quantities[item_id] = int(escrow_quantities.get(item_id, 0)) + int(lot.get("quantity"))
	var requirements: Dictionary = record.get("requirements") as Dictionary
	for item_v in requirements.keys():
		if str(item_v).is_empty() or typeof(requirements[item_v]) != TYPE_INT \
				or int(requirements[item_v]) <= 0:
			return false
	# Requirements name the exact paid inventory item IDs selected at prepare time.
	# For every state that still carries economic authority, they must equal escrow;
	# otherwise a restored payload could claim one material while spending another.
	if state != STATE_CANCELLED and escrow_quantities != requirements:
		return false
	var receipt: Dictionary = record.get("receipt") as Dictionary
	var receipt_id: String = str(record.get("commit_receipt_id", ""))
	if state == STATE_COMMITTED:
		if receipt_id != "%s:commit" % work_id or not _valid_receipt(receipt, work_id, receipt_id) \
				or receipt.get("consumed_lots", []) != record.get("escrow", []):
			return false
	else:
		if not receipt_id.is_empty() or not receipt.is_empty():
			return false
		if state == STATE_CANCELLED and not (record.get("escrow") as Array).is_empty():
			return false
	return true


static func _valid_receipt(receipt: Dictionary, work_id: String, receipt_id: String) -> bool:
	if not bool(receipt.get("ok", false)) or str(receipt.get("work_id", "")) != work_id \
			or str(receipt.get("commit_receipt_id", "")) != receipt_id:
		return false
	for key in ["consumed_lots", "returned_lots", "awarded_event_ids"]:
		if not (receipt.get(key, null) is Array):
			return false
	for key in ["consumed_lots", "returned_lots"]:
		for lot_v in receipt.get(key) as Array:
			if not (lot_v is Dictionary) or not _valid_lot(lot_v as Dictionary):
				return false
	return true


static func _valid_lot(lot: Dictionary) -> bool:
	if str(lot.get("lot_id", "")).is_empty() or str(lot.get("item_id", "")).is_empty() \
			or typeof(lot.get("quantity", null)) != TYPE_INT or int(lot.get("quantity")) <= 0 \
			or str(lot.get("quality_tier", "")).is_empty() or not (lot.get("origin", null) is Dictionary):
		return false
	var score_v: Variant = lot.get("quality_score", null)
	var condition_v: Variant = lot.get("condition", null)
	if typeof(score_v) not in [TYPE_INT, TYPE_FLOAT] or typeof(condition_v) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var score: float = float(score_v)
	var condition: float = float(condition_v)
	return is_finite(score) and score >= 0.0 and score <= 1.0 \
		and is_finite(condition) and condition >= 0.0 and condition <= 1.0 \
		and str(lot.get("quality_tier")) == QualityTierResolverScript.tier_for_score(score)


func _validate_request(request: Dictionary, source_inventory, requirements: Dictionary) -> Dictionary:
	for key in ["work_id", "ship_id", "target_id", "target_revision", "action_id", "source_holder_id"]:
		if str(request.get(key, "")).is_empty():
			return {"ok": false, "reason": "missing_%s" % key}
	if ship_id.is_empty() or str(request.get("ship_id")) != ship_id:
		return {"ok": false, "reason": "wrong_ship"}
	if source_inventory == null or not source_inventory.has_method("take_lots") \
			or not source_inventory.has_method("get_lot_summary") or not source_inventory.has_method("get_holder_namespace") \
			or not source_inventory.has_method("get_summary") or not source_inventory.has_method("apply_summary"):
		return {"ok": false, "reason": "missing_source_holder"}
	if str(request.get("source_holder_id")) != str(source_inventory.call("get_holder_namespace")):
		return {"ok": false, "reason": "wrong_source_holder"}
	var selected_ids: PackedStringArray = _string_array(request.get("selected_lot_ids", []))
	var selected: Dictionary = {}
	for lot_id: String in selected_ids:
		if lot_id.is_empty() or selected.has(lot_id):
			return {"ok": false, "reason": "invalid_selected_lot_ids"}
		selected[lot_id] = true
	var required_total: int = 0
	for item_v in requirements.keys():
		var item_id: String = str(item_v)
		var quantity: int = int(requirements[item_v])
		if item_id.is_empty() or quantity <= 0:
			return {"ok": false, "reason": "invalid_requirements"}
		required_total += quantity
	if required_total > 0 and selected_ids.is_empty():
		return {"ok": false, "reason": "selected_lots_required"}
	var available: Dictionary = {}
	var lots_v: Variant = source_inventory.call("get_lot_summary").get("lots", [])
	if not (lots_v is Array):
		return {"ok": false, "reason": "invalid_source_lots"}
	for lot_v in lots_v as Array:
		if not (lot_v is Dictionary):
			continue
		var lot: Dictionary = lot_v as Dictionary
		var lot_id: String = str(lot.get("lot_id", ""))
		if not selected.has(lot_id):
			continue
		var item_id: String = str(lot.get("item_id", ""))
		available[item_id] = int(available.get(item_id, 0)) + int(lot.get("quantity", 0))
	for item_v in requirements.keys():
		if int(available.get(str(item_v), 0)) < int(requirements[item_v]):
			return {"ok": false, "reason": "selected_lots_insufficient"}
	return {"ok": true, "selected_lot_ids": selected_ids}


func _commit_denial(record: Dictionary, context: Dictionary) -> String:
	if str(context.get("ship_id", "")) != str(record.get("ship_id", "")):
		return "wrong_ship"
	if str(context.get("target_id", "")) != str(record.get("target_id", "")):
		return "wrong_target"
	if not bool(context.get("target_exists", false)):
		return "target_removed"
	if str(context.get("target_revision", "")) != str(record.get("target_revision", "")):
		return "stale_target"
	if bool(context.get("damaged", false)):
		return "damaged"
	if not bool(context.get("in_range", false)):
		return "out_of_range"
	if not bool(context.get("has_required_tool", false)):
		return "missing_tool"
	return ""


func _fail_start_and_refund(work_id: String, source_inventory, driver, reason: String) -> Dictionary:
	if source_inventory != null:
		var refunded: Dictionary = cancel(work_id, source_inventory, driver, reason)
		if not bool(refunded.get("ok", false)):
			return refunded
	return {"ok": false, "reason": reason, "work_id": work_id, "refunded": source_inventory != null}


func _record_ref(work_id: String) -> Dictionary:
	var value: Variant = _records.get(work_id, {})
	return value as Dictionary if value is Dictionary else {}


func _can_refund(source_inventory, lots: Array) -> bool:
	var quantities: Dictionary = {}
	var occupied_lot_ids: Dictionary = {}
	if source_inventory.has_method("get_lot_summary"):
		for existing_v in source_inventory.call("get_lot_summary").get("lots", []) as Array:
			if existing_v is Dictionary:
				occupied_lot_ids[str((existing_v as Dictionary).get("lot_id", ""))] = true
	for lot_v in lots:
		if not (lot_v is Dictionary):
			return false
		var lot: Dictionary = lot_v as Dictionary
		var lot_id: String = str(lot.get("lot_id", ""))
		if lot_id.is_empty() or occupied_lot_ids.has(lot_id):
			return false
		occupied_lot_ids[lot_id] = true
		var item_id: String = str(lot.get("item_id", ""))
		quantities[item_id] = int(quantities.get(item_id, 0)) + int(lot.get("quantity", 0))
	for item_id_v in quantities.keys():
		if source_inventory.has_method("can_accept") and not bool(source_inventory.call("can_accept", str(item_id_v), int(quantities[item_id_v]))):
			return false
	return true


func _refund_detached_lots(source_inventory, lots: Array) -> bool:
	return _refund_lots_atomically(source_inventory, lots)


func _refund_lots_atomically(source_inventory, lots: Array) -> bool:
	if source_inventory == null or not source_inventory.has_method("add_lot") \
			or not source_inventory.has_method("get_summary") or not source_inventory.has_method("apply_summary") \
			or not _can_refund(source_inventory, lots):
		return false
	var before_v: Variant = source_inventory.call("get_summary")
	if not (before_v is Dictionary):
		return false
	var before: Dictionary = (before_v as Dictionary).duplicate(true)
	for lot_v in lots:
		if int(source_inventory.call("add_lot", lot_v as Dictionary)) != int((lot_v as Dictionary).get("quantity", 0)):
			source_inventory.call("apply_summary", before)
			return false
	return true


static func _string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is PackedStringArray:
		for entry: String in value as PackedStringArray:
			result.append(entry)
	elif value is Array:
		for entry_v in value as Array:
			result.append(str(entry_v))
	return result
