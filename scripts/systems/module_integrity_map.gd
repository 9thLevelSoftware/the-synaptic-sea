extends RefCounted
class_name ModuleIntegrityMap

## PKG-B2.1a: ship-level sparse map of ModuleIntegrityState (ADR-0051).
## Only non-pristine (or explicitly registered) modules are stored for persistence.

const ModuleIntegrityStateScript: GDScript = preload("res://scripts/systems/module_integrity_state.gd")

## module_id -> ModuleIntegrityState
var _modules: Dictionary = {}


func clear() -> void:
	_modules.clear()


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


func get_state(module_id: String) -> String:
	var m: RefCounted = get_module(module_id)
	if m == null:
		return ModuleIntegrityStateScript.STATE_INTACT
	return str(m.get("state"))


## Sparse deltas: only modules that are not pristine.
func to_sparse_deltas() -> Array:
	var out: Array = []
	for mid in _modules.keys():
		var m: RefCounted = _modules[mid] as RefCounted
		if m == null:
			continue
		if m.has_method("is_pristine") and bool(m.call("is_pristine")):
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
		"registered": _modules.size(),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	var deltas: Variant = summary.get("deltas", [])
	if typeof(deltas) != TYPE_ARRAY:
		return false
	clear()
	apply_sparse_deltas(deltas as Array)
	return true


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
			# mid format room/name
			var parts: PackedStringArray = str(mid).split("/")
			if parts.size() >= 1:
				room_id = parts[0]
		if not room_id.is_empty():
			rooms[room_id] = true
	var out: PackedStringArray = PackedStringArray()
	for rid in rooms.keys():
		out.append(str(rid))
	out.sort()
	return out
