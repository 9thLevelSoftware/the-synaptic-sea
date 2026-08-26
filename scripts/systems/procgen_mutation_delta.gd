extends RefCounted
class_name ProcgenMutationDelta

const SCHEMA := "procgen-mutation-delta-1"
const MAX_ID := 128
const MAX_OPS := 128
const MAX_ITEMS := 128
const MAX_BYTES := 16384
const KINDS := ["door", "container", "entity", "objective", "hazard", "system"]
const OPS := ["door_lock", "door_open", "container_inventory", "entity_remove", "objective", "hazard", "system_state"]

var base_site_id := ""
var base_semantic_hash := ""
var operations: Array[Dictionary] = []

func configure(site_id: String, semantic_hash: String, values: Array) -> bool:
	if site_id.is_empty() or site_id.length() > MAX_ID or semantic_hash.is_empty() or values.size() > MAX_OPS:
		return false
	base_site_id = site_id; base_semantic_hash = semantic_hash; operations.clear()
	for raw in values:
		if not _valid_operation(raw):
			operations.clear(); return false
		operations.append((raw as Dictionary).duplicate(true))
	return JSON.stringify(to_dict()).to_utf8_buffer().size() <= MAX_BYTES

func _valid_operation(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var op: Dictionary = raw
	if op.size() != 4 or not OPS.has(str(op.get("operation", ""))) or not KINDS.has(str(op.get("target_kind", ""))):
		return false
	var id := str(op.get("target_id", ""))
	if id.is_empty() or id.length() > MAX_ID or typeof(op.get("payload")) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = op["payload"]
	if payload.size() > MAX_ITEMS or JSON.stringify(payload).to_utf8_buffer().size() > MAX_BYTES:
		return false
	return true

func validate_targets(targets: Array) -> bool:
	var seen := {}
	for op in operations:
		var key := str(op["target_kind"]) + ":" + str(op["target_id"])
		if seen.has(key) or not targets.has(key):
			return false
		seen[key] = true
	return true

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "base_site_id": base_site_id, "base_semantic_hash": base_semantic_hash, "operations": operations.duplicate(true)}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = value
	if str(d.get("schema", "")) != SCHEMA or d.size() != 4 or typeof(d.get("operations")) != TYPE_ARRAY:
		return null
	var result = load("res://scripts/systems/procgen_mutation_delta.gd").new()
	if not result.configure(str(d.get("base_site_id", "")), str(d.get("base_semantic_hash", "")), d["operations"]):
		return null
	return result
