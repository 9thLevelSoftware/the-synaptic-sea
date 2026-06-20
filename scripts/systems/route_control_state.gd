extends RefCounted
class_name RouteControlState

## Runtime model for route access on the main playable slice.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## StaticBody3D gate nodes and applies scene consequences from this summary.

var gate_records: Dictionary = {}
var extraction_unlocked: bool = false

func configure_from_blocked_routes(route_gate_ids: Array) -> void:
	gate_records.clear()
	extraction_unlocked = false
	for gate_id_variant in route_gate_ids:
		var gate_id: String = str(gate_id_variant)
		if gate_id.is_empty():
			continue
		gate_records[gate_id] = {
			"id": gate_id,
			"open": false,
			"required_system": "main_power_restored",
		}

func apply_ship_systems_summary(summary: Dictionary) -> bool:
	var changed: bool = false
	var should_open_powered_gates: bool = bool(summary.get("main_power_restored", false)) and bool(summary.get("blocked_routes_cleared", false))
	if should_open_powered_gates:
		for gate_id in gate_records.keys():
			var record: Dictionary = gate_records[gate_id]
			if not bool(record.get("open", false)):
				record["open"] = true
				gate_records[gate_id] = record
				changed = true
	if bool(summary.get("extraction_unlocked", false)) and not extraction_unlocked:
		extraction_unlocked = true
		changed = true
	return changed

func get_summary() -> Dictionary:
	var gate_ids: Array = gate_records.keys()
	gate_ids.sort()
	# REQ-012: emit the per-gate open state as a nested dictionary so
	# save/load can round-trip the route gate topology exactly. This is
	# additive — existing consumers that only read the scalar summary
	# fields (route_gate_count, opened_gate_count, etc.) are unaffected.
	var gate_records_snapshot: Dictionary = {}
	for gate_id in gate_ids:
		var record: Dictionary = gate_records[gate_id]
		gate_records_snapshot[str(gate_id)] = {
			"id": str(record.get("id", gate_id)),
			"open": bool(record.get("open", false)),
			"required_system": str(record.get("required_system", "main_power_restored")),
		}
	return {
		"route_gate_count": gate_records.size(),
		"active_blocker_count": _active_blocker_count(),
		"opened_gate_count": _opened_gate_count(),
		"powered_gates_open": gate_records.size() > 0 and _opened_gate_count() == gate_records.size(),
		"extraction_unlocked": extraction_unlocked,
		"gate_ids": gate_ids,
		"gate_records": gate_records_snapshot,
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Routes: POWERED OPEN" if _active_blocker_count() == 0 and gate_records.size() > 0 else "Routes: BLOCKED")
	lines.append("Extraction: UNLOCKED" if extraction_unlocked else "Extraction: LOCKED")
	return lines

func is_gate_open(gate_id: String) -> bool:
	if not gate_records.has(gate_id):
		return false
	var record: Dictionary = gate_records[gate_id]
	return bool(record.get("open", false))

func is_extraction_unlocked() -> bool:
	return extraction_unlocked

## REQ-012: restore this model from a summary dictionary matching
## get_summary()'s shape. Unknown keys are ignored for forward
## compatibility. The gate_records dictionary is rebuilt by parsing the
## gate_records block of the summary (which is the source-of-truth shape
## the live model exposes), so we can faithfully round-trip the open
## state of every gate. If only the legacy gate_ids / per-gate open
## fields are present, the model re-derives open state from those
## instead. Returns true if any field changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_extraction: bool = bool(summary.get("extraction_unlocked", extraction_unlocked))
	if new_extraction != extraction_unlocked:
		extraction_unlocked = new_extraction
		changed = true
	var records_variant: Variant = summary.get("gate_records", null)
	if typeof(records_variant) == TYPE_DICTIONARY:
		var records: Dictionary = records_variant as Dictionary
		for gate_id in records.keys():
			var gate_id_str: String = str(gate_id)
			var record_variant: Variant = records[gate_id]
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant as Dictionary
			if not gate_records.has(gate_id_str):
				# Adopt the new gate id so the saved slice structure is
				# preserved. New fields like required_system are picked
				# up here too.
				gate_records[gate_id_str] = {
					"id": gate_id_str,
					"open": false,
					"required_system": "main_power_restored",
				}
			var existing: Dictionary = gate_records[gate_id_str]
			var new_open: bool = bool(record.get("open", existing.get("open", false)))
			if new_open != bool(existing.get("open", false)):
				existing["open"] = new_open
				gate_records[gate_id_str] = existing
				changed = true
	return changed

func _active_blocker_count() -> int:
	var count: int = 0
	for gate_id in gate_records.keys():
		var record: Dictionary = gate_records[gate_id]
		if not bool(record.get("open", false)):
			count += 1
	return count

func _opened_gate_count() -> int:
	var count: int = 0
	for gate_id in gate_records.keys():
		var record: Dictionary = gate_records[gate_id]
		if bool(record.get("open", false)):
			count += 1
	return count