extends RefCounted
class_name ShipSystemsManager

## Owns the six ship systems, resolves dependency cascades on demand, and
## (Task 6) drives time effects and repair. Pure data model — no scene tree.

const ShipSystemScript := preload("res://scripts/systems/ship_system.gd")
const LifeSupportSystemScript := preload("res://scripts/systems/life_support_system.gd")
const ShipSubcomponentScript := preload("res://scripts/systems/ship_subcomponent.gd")

const DEFINITIONS_PATH := "res://data/ship_systems/systems.json"

# Mirrors ShipBlueprint.Condition (PRISTINE=0, DAMAGED=1, WRECKED=2).
const CONDITION_PRISTINE := 0
const CONDITION_DAMAGED := 1
const CONDITION_WRECKED := 2

const DAMAGED_HEALTH := 0.2  # health a "broken" subcomponent is set to

var systems: Dictionary = {}            # system_id -> ShipSystem
var system_order: Array[String] = []

func load_definitions() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(DEFINITIONS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func configure(definitions: Dictionary, condition: int, seed_value: int) -> void:
	systems.clear()
	system_order.clear()
	var systems_variant: Variant = definitions.get("systems", [])
	if typeof(systems_variant) != TYPE_ARRAY:
		return
	for sys_variant in (systems_variant as Array):
		if typeof(sys_variant) != TYPE_DICTIONARY:
			continue
		var sys_def: Dictionary = sys_variant
		var sid: String = str(sys_def.get("system_id", ""))
		if sid.is_empty():
			continue
		var deps: Array[String] = []
		for d in sys_def.get("dependency_ids", []):
			deps.append(str(d))
		var system
		if sid == "life_support":
			system = LifeSupportSystemScript.new(sid, deps)
		else:
			system = ShipSystemScript.new(sid, deps)
		for sub_variant in sys_def.get("subcomponents", []):
			if typeof(sub_variant) != TYPE_DICTIONARY:
				continue
			var sub_def: Dictionary = sub_variant
			var parts: Array[String] = []
			for p in sub_def.get("required_parts", []):
				parts.append(str(p))
			var tools: Array[String] = []
			for t in sub_def.get("required_tools", []):
				tools.append(str(t))
			var sub = ShipSubcomponentScript.new(
				str(sub_def.get("subcomponent_id", "")),
				parts,
				tools,
				int(sub_def.get("min_skill", 0)),
				float(sub_def.get("repair_seconds", 5.0)),
				float(sub_def.get("operational_threshold", 0.5)))
			system.add_subcomponent(sub)
		systems[sid] = system
		system_order.append(sid)
	_apply_condition_damage(condition, seed_value)

## Deterministically damages subcomponents based on condition. A seeded RNG
## walks subcomponents in declaration order so the same (condition, seed)
## always produces the same damage set.
func _apply_condition_damage(condition: int, seed_value: int) -> void:
	var break_chance: float = 0.0
	match condition:
		CONDITION_PRISTINE:
			break_chance = 0.0
		CONDITION_DAMAGED:
			break_chance = 0.4
		CONDITION_WRECKED:
			break_chance = 0.8
		_:
			break_chance = 0.0
	if break_chance <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for sid in system_order:
		for sub in systems[sid].subcomponents:
			if rng.randf() < break_chance:
				sub.health = DAMAGED_HEALTH

func get_system(system_id: String):
	return systems.get(system_id, null)

## Derived operational status: self-functional AND every dependency operational.
## Cycle-safe via the visiting set (no cycles are expected in the data).
func is_operational(system_id: String) -> bool:
	return _resolve_operational(system_id, {})

func _resolve_operational(system_id: String, visiting: Dictionary) -> bool:
	if not systems.has(system_id):
		return false
	if visiting.has(system_id):
		return false
	var system = systems[system_id]
	if not system.is_self_functional():
		return false
	visiting[system_id] = true
	for dep in system.dependency_ids:
		if not _resolve_operational(dep, visiting):
			visiting.erase(system_id)
			return false
	visiting.erase(system_id)
	return true

## Flat, ordered list of every subcomponent health — used by smokes to assert
## deterministic builds without depending on dictionary ordering.
func get_summary_health_list() -> Array:
	var out: Array = []
	for sid in system_order:
		for sub in systems[sid].subcomponents:
			out.append(sub.health)
	return out

## Ticks every system with its resolved operational status. Only LifeSupport
## acts on the time delta (oxygen drain when offline).
func advance(delta: float) -> void:
	for sid in system_order:
		systems[sid].advance(delta, is_operational(sid))

## Parameterized repair routed to the named subcomponent. Returns the
## subcomponent's RepairResult, or an unknown_system / unknown_subcomponent
## rejection.
func repair(system_id: String, subcomponent_id: String, available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary:
	if not systems.has(system_id):
		return {"success": false, "reason": "unknown_system", "seconds": 0.0}
	var sub = systems[system_id].get_subcomponent(subcomponent_id)
	if sub == null:
		return {"success": false, "reason": "unknown_subcomponent", "seconds": 0.0}
	return sub.repair(available_parts, available_tools, skill_level)

func get_status_summary() -> Dictionary:
	var out: Dictionary = {}
	for sid in system_order:
		out[sid] = {"operational": is_operational(sid), "health": systems[sid].health()}
	return out

func get_summary() -> Dictionary:
	var sys_summaries: Dictionary = {}
	for sid in system_order:
		sys_summaries[sid] = systems[sid].get_summary()
	return {"systems": sys_summaries, "system_order": system_order.duplicate()}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var sys_summaries_variant: Variant = summary.get("systems", {})
	if typeof(sys_summaries_variant) != TYPE_DICTIONARY:
		return false
	var changed: bool = false
	for sid in (sys_summaries_variant as Dictionary):
		if systems.has(sid):
			if systems[sid].apply_summary((sys_summaries_variant as Dictionary)[sid]):
				changed = true
	return changed
