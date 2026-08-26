extends RefCounted
class_name ProcgenMutationDelta

const SCHEMA := "procgen-mutation-delta-1"
const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const MAX_OPERATIONS := 128
const MAX_PAYLOAD_BYTES := 4096
const MAX_DOCUMENT_BYTES := 16384
const MAX_DEPTH := 8
const MAX_VALUES := 2048
const MAX_TARGETS := 4096
const MAX_TARGET_BYTES := 524288
const OPS := {"door_lock":"door", "door_open":"door", "container_inventory":"container", "entity_remove":"entity", "objective":"objective", "hazard":"hazard", "system_state":"system"}
const TARGET_KINDS := {"door": true, "container": true, "entity": true, "objective": true, "hazard": true, "system": true}
var base_site_id: String = ""
var base_semantic_hash: String = ""
var operations: Array[Dictionary] = []

func configure(site_id: Variant, semantic: Variant, values: Variant) -> bool:
	if not Site.valid_id(site_id) or not Site.valid_hash(semantic) or typeof(values) != TYPE_ARRAY or values.size() > MAX_OPERATIONS: return false
	var seen := {}
	var parsed: Array[Dictionary] = []
	for raw in values:
		var operation: Variant = _validated_operation(raw, seen)
		if operation == null: return false
		parsed.append(operation)
	if _bounded(parsed, 0) > MAX_VALUES: return false
	var candidate := {"schema_version": SCHEMA, "base_site_id": site_id, "base_semantic_hash": semantic, "operations": parsed}
	if JSON.stringify(candidate).to_utf8_buffer().size() > MAX_DOCUMENT_BYTES: return false
	base_site_id = site_id; base_semantic_hash = semantic; operations = parsed
	return true

func _bounded(value: Variant, depth: int) -> int:
	if depth > MAX_DEPTH: return MAX_VALUES + 1
	var total := 1
	if typeof(value) == TYPE_DICTIONARY:
		for key in value.keys(): total += _bounded(key, depth + 1); total += _bounded(value[key], depth + 1)
	elif typeof(value) == TYPE_ARRAY:
		for item in value: total += _bounded(item, depth + 1)
	return total

func _validated_operation(raw: Variant, seen: Dictionary) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY: return null
	var op: Dictionary = raw
	if _bounded(op, 0) > MAX_VALUES: return null
	if op.size() != 4 or not op.has_all(["operation", "target_kind", "target_id", "payload"]): return null
	if typeof(op.operation) != TYPE_STRING or typeof(op.target_kind) != TYPE_STRING or typeof(op.target_id) != TYPE_STRING or typeof(op.payload) != TYPE_DICTIONARY: return null
	if not OPS.has(op.operation) or OPS[op.operation] != op.target_kind or not Site.valid_id(op.target_id): return null
	var identity: String = op.operation + ":" + op.target_kind + ":" + op.target_id
	if seen.has(identity): return null
	var payload: Dictionary = op.payload
	var valid := false
	match op.operation:
		"door_lock": valid = payload.size() == 1 and payload.has("locked") and typeof(payload.locked) == TYPE_BOOL
		"door_open": valid = payload.size() == 1 and payload.has("open") and typeof(payload.open) == TYPE_BOOL
		"container_inventory": valid = _valid_items(payload)
		"entity_remove": valid = payload.size() == 1 and payload.has("removed") and payload.removed == true and typeof(payload.removed) == TYPE_BOOL
		"objective": valid = payload.size() == 1 and payload.has("completed") and typeof(payload.completed) == TYPE_BOOL
		"hazard": valid = payload.size() == 1 and payload.has("active") and typeof(payload.active) == TYPE_BOOL
		"system_state": valid = payload.size() == 1 and payload.has("state") and Site.valid_id(payload.state)
	if not valid: return null
	seen[identity] = true
	return op.duplicate(true)

func _valid_items(payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.has("items") or typeof(payload.items) != TYPE_ARRAY or payload.items.size() > 64: return false
	var seen := {}
	for raw in payload.items:
		if typeof(raw) != TYPE_DICTIONARY or raw.size() != 2 or not raw.has_all(["item_id", "quantity"]): return false
		if not Site.valid_id(raw.item_id) or seen.has(raw.item_id) or typeof(raw.quantity) != TYPE_INT or raw.quantity < 0 or raw.quantity > 65535: return false
		seen[raw.item_id] = true
	return true

func validate_targets(targets: Variant) -> bool:
	if typeof(targets) != TYPE_ARRAY or targets.size() > MAX_TARGETS: return false
	var seen := {}
	for target in targets:
		if typeof(target) != TYPE_DICTIONARY or target.size() != 2 or not target.has_all(["target_kind", "target_id"]): return false
		if typeof(target.target_kind) != TYPE_STRING or typeof(target.target_id) != TYPE_STRING or not TARGET_KINDS.has(target.target_kind) or not Site.valid_id(target.target_id): return false
		var identity: String = target.target_kind + ":" + target.target_id
		if seen.has(identity): return false
		seen[identity] = true
	if JSON.stringify(seen).to_utf8_buffer().size() > MAX_TARGET_BYTES: return false
	for operation in operations:
		if not seen.has(operation.target_kind + ":" + operation.target_id): return false
	return true

func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA, "base_site_id": base_site_id, "base_semantic_hash": base_semantic_hash, "operations": operations.duplicate(true)}

static func from_dict(value: Variant):
	if typeof(value) != TYPE_DICTIONARY: return null
	var data: Dictionary = value
	if data.size() != 4 or not data.has_all(["schema_version", "base_site_id", "base_semantic_hash", "operations"]) or data.schema_version != SCHEMA: return null
	var result = load("res://scripts/systems/procgen_mutation_delta.gd").new()
	return result if result.configure(data.base_site_id, data.base_semantic_hash, data.operations) else null
