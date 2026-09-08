extends RefCounted
class_name ModuleIntegrityMap

## PKG-B2.1a: ship-level sparse map of ModuleIntegrityState (ADR-0051).
## Only non-pristine (or explicitly registered) modules are stored for persistence.

const ModuleIntegrityStateScript: GDScript = preload("res://scripts/systems/module_integrity_state.gd")
const StructuralRebuildStateScript: GDScript = preload("res://scripts/systems/structural_rebuild_state.gd")
const StructuralRebuildCatalogScript: GDScript = preload("res://scripts/systems/structural_rebuild_catalog.gd")

const CURRENT_SCHEMA: String = "module_integrity_map_v1"
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0
const MAX_CONTIGUOUS_FLOAT_INTEGER: int = 9007199254740992
const MAX_JSON_NESTING: int = 64
const CURRENT_SUMMARY_KEYS: Array[String] = ["schema", "deltas", "registered"]
const CURRENT_DELTA_KEYS: Array[String] = [
	"module_id", "kind", "room_id", "integrity", "base_integrity", "state",
	"material_composition", "mounted_components", "tool_class",
]

## module_id -> ModuleIntegrityState
var _modules: Dictionary = {}
var _structural_rebuild_state: RefCounted
var _structural_rebuild_catalog: RefCounted
## Current strict restores remember every explicit row, including an intact row
## within the historical epsilon. This makes immediate recapture exact without
## changing sparse behavior for maps populated through historical APIs.
var _current_explicit_delta_ids: Dictionary = {}
var _current_explicit_delta_order: PackedStringArray = PackedStringArray()
var _current_summary_initialized: bool = false
var _current_registered_as_float: bool = false


func _init() -> void:
	_structural_rebuild_state = StructuralRebuildStateScript.new()
	_structural_rebuild_catalog = StructuralRebuildCatalogScript.new()
	if not bool(_structural_rebuild_state.call("bind_integrity_owner", self)):
		return
	if not bool(_structural_rebuild_catalog.call("load_canonical")):
		return
	_structural_rebuild_state.call("bind_catalog_authority", _structural_rebuild_catalog)


func clear() -> void:
	_modules.clear()
	_current_explicit_delta_ids.clear()
	_current_explicit_delta_order.clear()
	_current_summary_initialized = false
	_current_registered_as_float = false
	_structural_rebuild_state.call("clear")


func size() -> int:
	return _modules.size()


func has_module(module_id: String) -> bool:
	return _modules.has(module_id)


func get_module(module_id: String) -> RefCounted:
	if not _modules.has(module_id):
		return null
	return _modules[module_id] as RefCounted


func ensure_module(module_id: String, kind: String = "", composition: Dictionary = {}, room_id: String = "") -> RefCounted:
	if _modules.has(module_id):
		var existing: RefCounted = _modules[module_id] as RefCounted
		if existing != null and not room_id.is_empty():
			existing.set("room_id", room_id)
		return existing
	var m = ModuleIntegrityStateScript.new()
	m.configure({
		"module_id": module_id,
		"kind": kind,
		"material_composition": composition,
		"room_id": room_id,
	})
	_modules[module_id] = m
	return m


func apply_damage(module_id: String, amount: float, kind: String = "") -> String:
	var m: RefCounted = ensure_module(module_id, kind)
	return str(m.call("apply_damage", amount))


## Bind immutable loader-authored data to the integrity identity without placing
## descriptor payloads inside sparse damage persistence.
func register_original_descriptor(descriptor: Dictionary) -> bool:
	if not bool(_structural_rebuild_state.call("register_original", descriptor)):
		return false
	return _seed_module_from_descriptor(descriptor) != null


func apply_authored_state(module_id: String, authored_state: String, kind: String = "") -> bool:
	var module: RefCounted = ensure_module(module_id, kind)
	if not module.has_method("apply_authored_state") \
			or not bool(module.call("apply_authored_state", authored_state)):
		return false
	return true


func get_structural_rebuild_state() -> RefCounted:
	return _structural_rebuild_state


func inspect_rebuild_target(module_id: String) -> Dictionary:
	var result: Dictionary = _structural_rebuild_state.call("inspect_target", module_id)
	if not bool(result.get("ok", false)):
		return result
	var live_state: String = get_state(module_id)
	result["state"] = live_state
	result["replaceable"] = live_state == ModuleIntegrityStateScript.STATE_DESTROYED
	return result


func get_state(module_id: String) -> String:
	var m: RefCounted = get_module(module_id)
	if m == null:
		return ModuleIntegrityStateScript.STATE_INTACT
	return str(m.get("state"))


## Sparse deltas: only modules that are not pristine.
func to_sparse_deltas() -> Array:
	var out: Array = []
	var emitted: Dictionary = {}
	for explicit_id in _current_explicit_delta_order:
		if not _current_explicit_delta_ids.has(explicit_id):
			continue
		var explicit_module: RefCounted = _modules.get(explicit_id, null) as RefCounted
		if explicit_module == null:
			continue
		if explicit_module.has_method("get_summary"):
			out.append(explicit_module.call("get_summary"))
			emitted[explicit_id] = true
	for mid in _modules.keys():
		if emitted.has(str(mid)):
			continue
		var m: RefCounted = _modules[mid] as RefCounted
		if m == null:
			continue
		if _current_summary_initialized:
			if _is_exactly_pristine(m):
				continue
		elif m.has_method("is_pristine") and bool(m.call("is_pristine")):
			continue
		if m.has_method("get_summary"):
			out.append(m.call("get_summary"))
	return out


func apply_sparse_deltas(deltas: Array) -> void:
	for entry in deltas:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var mid: String = str(row.get("module_id", ""))
		if mid.is_empty():
			continue
		var m: RefCounted = ensure_module(mid, str(row.get("kind", "")))
		if m.has_method("apply_summary"):
			m.call("apply_summary", row)


func get_summary() -> Dictionary:
	return {
		"schema": "module_integrity_map_v1",
		"deltas": to_sparse_deltas(),
		"registered": float(_modules.size()) if _current_summary_initialized \
			and _current_registered_as_float else _modules.size(),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	var deltas: Variant = summary.get("deltas", [])
	if typeof(deltas) != TYPE_ARRAY:
		return false
	# The loader's authored descriptors outlive sparse integrity reloads. Rebuild
	# the pristine module baseline before applying deltas so omitted modules keep
	# their structural kind and exact authored room ownership.
	_modules.clear()
	_current_explicit_delta_ids.clear()
	_current_explicit_delta_order.clear()
	_current_summary_initialized = false
	_current_registered_as_float = false
	for descriptor_variant in _structural_rebuild_state.call("get_original_descriptors"):
		if descriptor_variant is Dictionary:
			_seed_module_from_descriptor(descriptor_variant as Dictionary)
	apply_sparse_deltas(deltas as Array)
	return true


## Pure detached syntax admission for current run-7/world-7 summaries. An empty
## dictionary is the historical uninitialized sentinel. A nonempty accepted
## dictionary is explicitly initialized, including deltas == []. Geometry and
## descriptor identity are deliberately outside this function.
static func validate_current_summary(summary: Variant) -> Dictionary:
	if not summary is Dictionary:
		return _current_denial("integrity_summary_not_dictionary")
	var source: Dictionary = summary as Dictionary
	if source.is_empty():
		return {"ok": true, "reason": "", "initialized": false, "summary": {}}
	if not _has_exact_string_keys(source, CURRENT_SUMMARY_KEYS):
		return _current_denial("integrity_summary_invalid_shape")
	if typeof(source.schema) != TYPE_STRING or source.schema != CURRENT_SCHEMA:
		return _current_denial("integrity_summary_invalid_schema")
	if not source.deltas is Array:
		return _current_denial("integrity_summary_invalid_deltas")
	if not _is_nonnegative_safe_integer(source.registered):
		return _current_denial("integrity_summary_invalid_registered")
	var seen_ids: Dictionary = {}
	for row_v in source.deltas as Array:
		if not row_v is Dictionary:
			return _current_denial("integrity_delta_not_dictionary")
		var row: Dictionary = row_v as Dictionary
		if not _has_exact_string_keys(row, CURRENT_DELTA_KEYS):
			return _current_denial("integrity_delta_invalid_shape")
		if typeof(row.module_id) != TYPE_STRING or (row.module_id as String).is_empty():
			return _current_denial("integrity_delta_invalid_module_id")
		if seen_ids.has(row.module_id):
			return _current_denial("integrity_delta_duplicate_module_id")
		seen_ids[row.module_id] = true
		for key in ["kind", "room_id", "state", "tool_class"]:
			if typeof(row[key]) != TYPE_STRING:
				return _current_denial("integrity_delta_invalid_string")
		var integrity_value: Variant = row.integrity
		var base_value: Variant = row.base_integrity
		if not _is_exact_float_backed_number(integrity_value) \
				or not _is_exact_float_backed_number(base_value):
			return _current_denial("integrity_delta_invalid_health")
		var integrity_number: float = float(integrity_value)
		var base_number: float = float(base_value)
		if base_number <= 0.0 or integrity_number < 0.0 or integrity_number > base_number:
			return _current_denial("integrity_delta_invalid_health")
		if row.state != ModuleIntegrityStateScript.state_for_health(
				integrity_number, base_number):
			return _current_denial("integrity_delta_state_mismatch")
		if not row.material_composition is Dictionary:
			return _current_denial("integrity_delta_invalid_composition")
		if not row.mounted_components is Array:
			return _current_denial("integrity_delta_invalid_mounted")
		if not _is_persistable_json(row.material_composition) \
				or not _is_persistable_json(row.mounted_components):
			return _current_denial("integrity_delta_invalid_json")
	return {
		"ok": true,
		"reason": "",
		"initialized": true,
		"summary": source.duplicate(true),
	}


## Descriptor-authenticated current application. All syntax and descriptor checks
## complete before the live module dictionary changes. Empty/uninitialized input is
## accepted as a no-op; it cannot claim geometry closure.
func apply_current_summary(summary: Variant) -> Dictionary:
	var admission: Dictionary = validate_current_summary(summary)
	if not bool(admission.get("ok", false)):
		return admission
	if not bool(admission.get("initialized", false)):
		return admission
	var admitted: Dictionary = admission.summary as Dictionary
	var descriptors_v: Variant = _structural_rebuild_state.call("get_original_descriptors")
	if not descriptors_v is Array or (descriptors_v as Array).is_empty():
		return _current_denial("integrity_descriptor_authority_missing")
	var descriptors: Array = descriptors_v as Array
	if int(admitted.registered) != descriptors.size():
		return _current_denial("integrity_registered_count_mismatch")
	var descriptor_by_id: Dictionary = {}
	for descriptor_v in descriptors:
		if not descriptor_v is Dictionary:
			return _current_denial("integrity_descriptor_authority_invalid")
		var descriptor: Dictionary = descriptor_v as Dictionary
		var descriptor_id: String = str(descriptor.get("module_id", ""))
		if descriptor_id.is_empty() or descriptor_by_id.has(descriptor_id) \
				or typeof(descriptor.get("structural_module_id", null)) != TYPE_STRING \
				or not descriptor.get("room_bindings", null) is Array:
			return _current_denial("integrity_descriptor_authority_invalid")
		descriptor_by_id[descriptor_id] = descriptor
	for row_v in admitted.deltas as Array:
		var row: Dictionary = row_v as Dictionary
		var row_id: String = row.module_id as String
		if not descriptor_by_id.has(row_id):
			return _current_denial("integrity_delta_unknown_module")
		var descriptor: Dictionary = descriptor_by_id[row_id] as Dictionary
		if row.kind != descriptor.structural_module_id:
			return _current_denial("integrity_delta_kind_mismatch")
		if row.room_id != _descriptor_primary_room(descriptor):
			return _current_denial("integrity_delta_room_mismatch")

	var next_modules: Dictionary = {}
	for descriptor_v in descriptors:
		var descriptor: Dictionary = descriptor_v as Dictionary
		var module: RefCounted = _module_from_descriptor(descriptor)
		if module == null:
			return _current_denial("integrity_descriptor_authority_invalid")
		next_modules[str(descriptor.module_id)] = module
	var next_explicit_ids: Dictionary = {}
	var next_explicit_order: PackedStringArray = PackedStringArray()
	for row_v in admitted.deltas as Array:
		var row: Dictionary = row_v as Dictionary
		var row_id: String = row.module_id as String
		var module: RefCounted = next_modules[row_id] as RefCounted
		if not bool(module.call("apply_current_summary", row)):
			return _current_denial("integrity_delta_invalid_state")
		next_explicit_ids[row_id] = true
		next_explicit_order.append(row_id)
	_modules = next_modules
	_current_explicit_delta_ids = next_explicit_ids
	_current_explicit_delta_order = next_explicit_order
	_current_summary_initialized = true
	_current_registered_as_float = typeof(admitted.registered) == TYPE_FLOAT
	return admission


static func _current_denial(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "initialized": false, "summary": {}}


static func _has_exact_string_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key_v in value.keys():
		if not key_v is String:
			return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _is_nonnegative_safe_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= MAX_SAFE_JSON_INTEGER \
		and number == floorf(number)


static func _is_exact_float_backed_number(value: Variant) -> bool:
	if typeof(value) == TYPE_FLOAT:
		return is_finite(float(value))
	if typeof(value) != TYPE_INT:
		return false
	# Integrity state stores health in float fields. Above the contiguous integer
	# range, an int is exact only when every bit below the float's precision is
	# zero. Reduce even values until they fit instead of converting back from a
	# rounded float, which is unsafe at the int64 upper boundary.
	var reduced: int = int(value)
	while reduced > MAX_CONTIGUOUS_FLOAT_INTEGER \
			or reduced < -MAX_CONTIGUOUS_FLOAT_INTEGER:
		if (reduced & 1) != 0:
			return false
		reduced >>= 1
	return true


static func _is_persistable_json(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_NESTING:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return absf(float(value)) <= MAX_SAFE_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child in value as Array:
				if not _is_persistable_json(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key_v in (value as Dictionary).keys():
				if not key_v is String \
						or not _is_persistable_json((value as Dictionary)[key_v], depth + 1):
					return false
			return true
		_:
			return false


static func _descriptor_primary_room(descriptor: Dictionary) -> String:
	for room_v in descriptor.get("room_bindings", []) as Array:
		if typeof(room_v) == TYPE_STRING and not (room_v as String).is_empty():
			return room_v as String
	return ""


static func _module_from_descriptor(descriptor: Dictionary) -> RefCounted:
	var module_id: String = str(descriptor.get("module_id", ""))
	var structural_kind: String = str(descriptor.get("structural_module_id", ""))
	if module_id.is_empty() or structural_kind.is_empty():
		return null
	var primary_room: String = _descriptor_primary_room(descriptor)
	var owners: PackedStringArray = PackedStringArray()
	for room_v in descriptor.get("room_bindings", []) as Array:
		if typeof(room_v) != TYPE_STRING:
			return null
		var room_id: String = room_v as String
		if not room_id.is_empty() and not owners.has(room_id):
			owners.append(room_id)
	var module: RefCounted = ModuleIntegrityStateScript.new()
	module.call("configure", {
		"module_id": module_id,
		"kind": structural_kind,
		"material_composition": {},
		"room_id": primary_room,
	})
	module.set("owner_rooms", owners)
	return module


static func _is_exactly_pristine(module: RefCounted) -> bool:
	if str(module.get("state")) != ModuleIntegrityStateScript.STATE_INTACT \
			or float(module.get("integrity")) != float(module.get("base_integrity")):
		return false
	var mounted_v: Variant = module.get("mounted_components")
	return mounted_v is Array and (mounted_v as Array).is_empty()


func _seed_module_from_descriptor(descriptor: Dictionary) -> RefCounted:
	var module_id: String = str(descriptor.get("module_id", ""))
	var structural_kind: String = str(descriptor.get("structural_module_id", ""))
	var room_bindings: Array = descriptor.get("room_bindings", []) if descriptor.get("room_bindings", []) is Array else []
	var primary_room: String = ""
	var owners: PackedStringArray = PackedStringArray()
	for room_variant in room_bindings:
		var room_id: String = str(room_variant)
		if room_id.is_empty():
			continue
		if primary_room.is_empty():
			primary_room = room_id
		if not owners.has(room_id):
			owners.append(room_id)
	var module: RefCounted = ensure_module(module_id, structural_kind, {}, primary_room)
	module.set("owner_rooms", owners)
	return module


## Determinism helper: sorted module ids + states.
func fingerprint() -> String:
	var ids: Array = _modules.keys()
	ids.sort()
	var parts: PackedStringArray = PackedStringArray()
	for mid in ids:
		var m: RefCounted = _modules[mid] as RefCounted
		parts.append("%s:%s:%.4f" % [str(mid), str(m.get("state")), float(m.get("integrity"))])
	return "|".join(parts)


## PKG-B2.1b: count wall modules that are breached or destroyed.
func count_wall_breaches() -> int:
	var count: int = 0
	for mid in _modules.keys():
		var m: RefCounted = _modules[mid] as RefCounted
		if m == null:
			continue
		var kind: String = str(m.get("kind"))
		var st: String = str(m.get("state"))
		var is_wall: bool = false
		var k: String = kind.to_lower()
		for prefix in ["wall_", "bulkhead_", "panel_", "door_"]:
			if k.begins_with(prefix) or k.find(prefix) >= 0:
				is_wall = true
				break
		if not is_wall:
			continue
		if st == ModuleIntegrityStateScript.STATE_BREACHED or st == ModuleIntegrityStateScript.STATE_DESTROYED:
			count += 1
	return count


func module_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for mid in _modules.keys():
		out.append(str(mid))
	out.sort()
	return out


## Room ids that have at least one wall module with nav_gap consequence.
func rooms_with_nav_gaps() -> PackedStringArray:
	var rooms: Dictionary = {}
	for mid in _modules.keys():
		var m: RefCounted = _modules[mid] as RefCounted
		if m == null:
			continue
		var st: String = str(m.get("state"))
		if st != ModuleIntegrityStateScript.STATE_BREACHED and st != ModuleIntegrityStateScript.STATE_DESTROYED:
			continue
		var summary: Dictionary = m.call("get_summary") if m.has_method("get_summary") else {}
		var room_id: String = str(summary.get("room_id", ""))
		if room_id.is_empty():
			room_id = str(m.get("room_id"))
		if room_id.is_empty():
			# mid format room/name
			var parts: PackedStringArray = str(mid).split("/")
			if parts.size() >= 1:
				room_id = parts[0]
		if not room_id.is_empty():
			rooms[room_id] = true
		var owners_v: Variant = m.get("owner_rooms")
		if owners_v is PackedStringArray:
			for rid in (owners_v as PackedStringArray):
				if not str(rid).is_empty():
					rooms[str(rid)] = true
		elif owners_v is Array:
			for rid_v in (owners_v as Array):
				if not str(rid_v).is_empty():
					rooms[str(rid_v)] = true
	var out: PackedStringArray = PackedStringArray()
	for rid in rooms.keys():
		out.append(str(rid))
	out.sort()
	return out
