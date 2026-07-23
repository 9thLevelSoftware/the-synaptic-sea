extends RefCounted
class_name PillarPersistence

## PKG-D8: pure pack/unpack for pre-polish pillar models that need save survival:
## ModuleIntegrityMap, ComponentPlacementState, in-progress WorkActionState.
## Nested under RunSnapshot fields; empty defaults keep historical fixtures loadable.

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


static func pack_module_integrity(map: RefCounted) -> Dictionary:
	if map == null:
		return {"schema": "module_integrity_v1", "deltas": []}
	var deltas: Array = []
	if map.has_method("to_sparse_deltas"):
		deltas = map.call("to_sparse_deltas")
	return {
		"schema": "module_integrity_v1",
		"deltas": deltas if deltas is Array else [],
	}


static func unpack_module_integrity(summary: Dictionary) -> RefCounted:
	var map = ModuleIntegrityMapScript.new()
	if summary.is_empty():
		return map
	var deltas: Variant = summary.get("deltas", [])
	if deltas is Array and map.has_method("apply_sparse_deltas"):
		map.call("apply_sparse_deltas", deltas)
	return map


static func pack_component_placement(placement: RefCounted) -> Dictionary:
	if placement == null:
		return {"schema": "component_placement_v1", "seed": 0, "count": 0, "placed": []}
	if placement.has_method("get_summary"):
		var s: Dictionary = placement.call("get_summary")
		s["schema"] = "component_placement_v1"
		return s
	return {"schema": "component_placement_v1", "seed": 0, "count": 0, "placed": []}


static func unpack_component_placement(summary: Dictionary) -> RefCounted:
	var place = ComponentPlacementStateScript.new()
	if summary.is_empty():
		return place
	if place.has_method("apply_summary"):
		place.call("apply_summary", summary)
	return place


static func pack_work_action(work: RefCounted) -> Dictionary:
	if work == null:
		return {"schema": "work_action_v1", "active": false}
	if not work.has_method("get_summary"):
		return {"schema": "work_action_v1", "active": false}
	var s: Dictionary = work.call("get_summary")
	var status: String = str(s.get("status", "idle"))
	return {
		"schema": "work_action_v1",
		"active": status == "active" or status == "interrupted",
		"summary": s,
	}


static func unpack_work_action(summary: Dictionary) -> RefCounted:
	var work = WorkActionStateScript.new()
	if summary.is_empty() or not bool(summary.get("active", false)):
		return work
	var inner: Variant = summary.get("summary", {})
	if typeof(inner) == TYPE_DICTIONARY and work.has_method("apply_summary"):
		work.call("apply_summary", inner as Dictionary)
	return work


## Bundle for RunSnapshot / ship instance attachment.
static func pack_all(map: RefCounted, placement: RefCounted, work: RefCounted) -> Dictionary:
	return {
		"schema": "pillar_persistence_v1",
		"module_integrity": pack_module_integrity(map),
		"component_placement": pack_component_placement(placement),
		"work_action": pack_work_action(work),
	}


static func unpack_all(bundle: Dictionary) -> Dictionary:
	return {
		"module_integrity": unpack_module_integrity(_dict(bundle.get("module_integrity", {}))),
		"component_placement": unpack_component_placement(_dict(bundle.get("component_placement", {}))),
		"work_action": unpack_work_action(_dict(bundle.get("work_action", {}))),
	}


static func _dict(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v as Dictionary
	return {}


## Fuzz: strip unknown keys, tolerate missing pillar fields (historical fixtures).
static func sanitize_historical(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	# Always ensure pillar keys exist as empty dicts for loaders
	if not out.has("module_integrity_summary"):
		out["module_integrity_summary"] = {}
	if not out.has("component_placement_summary"):
		out["component_placement_summary"] = {}
	if not out.has("work_action_summary"):
		out["work_action_summary"] = {}
	if not out.has("ship_modification_summary"):
		out["ship_modification_summary"] = {}
	# Drop garbage non-dict values
	for k in [
		"module_integrity_summary",
		"component_placement_summary",
		"work_action_summary",
		"ship_modification_summary",
	]:
		if typeof(out.get(k, null)) != TYPE_DICTIONARY:
			out[k] = {}
	return out
