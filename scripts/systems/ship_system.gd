extends RefCounted
class_name ShipSystem

## One ship system: a set of subcomponents plus the ids of other systems it
## depends on. Pure data model. Operational status is NOT stored here — the
## manager computes it (it owns the dependency graph). This class answers the
## health half of that decision via is_self_functional().

var system_id: String = ""
var subcomponents: Array = []  # Array of ShipSubcomponent
var dependency_ids: Array[String] = []

func _init(p_system_id: String = "", p_dependency_ids: Array[String] = []) -> void:
	system_id = p_system_id
	dependency_ids = p_dependency_ids.duplicate()
	subcomponents = []

func add_subcomponent(sub) -> void:
	subcomponents.append(sub)

func get_subcomponent(sub_id: String):
	for sub in subcomponents:
		if sub.subcomponent_id == sub_id:
			return sub
	return null

## Health of the weakest subcomponent (a system is only as good as its worst
## part). Returns 1.0 when there are no subcomponents.
func health() -> float:
	if subcomponents.is_empty():
		return 1.0
	var lowest: float = 1.0
	for sub in subcomponents:
		lowest = minf(lowest, sub.health)
	return lowest

func is_self_functional() -> bool:
	for sub in subcomponents:
		if not sub.is_functional():
			return false
	return true

## Base systems have no model-level time effect. Subclasses (LifeSupportSystem)
## override this. `operational` is the manager-resolved status for this system.
func advance(_delta: float, _operational: bool) -> void:
	pass

func get_summary() -> Dictionary:
	var subs: Array = []
	for sub in subcomponents:
		subs.append(sub.get_summary())
	return {
		"system_id": system_id,
		"dependency_ids": dependency_ids.duplicate(),
		"subcomponents": subs,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var subs_variant: Variant = summary.get("subcomponents", [])
	if typeof(subs_variant) == TYPE_ARRAY:
		for sub_summary in (subs_variant as Array):
			if typeof(sub_summary) != TYPE_DICTIONARY:
				continue
			var sub = get_subcomponent(str((sub_summary as Dictionary).get("subcomponent_id", "")))
			if sub != null and sub.apply_summary(sub_summary):
				changed = true
	return changed
