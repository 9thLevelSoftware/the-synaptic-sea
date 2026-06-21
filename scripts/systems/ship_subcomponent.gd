extends RefCounted
class_name ShipSubcomponent

## One repairable part of a ship system. Pure data model: never touches the
## scene tree. health is 0.0 (destroyed) .. 1.0 (perfect); at/above
## operational_threshold the part counts as functional.

var subcomponent_id: String = ""
var health: float = 1.0
var operational_threshold: float = 0.5
var required_parts: Array[String] = []
var required_tools: Array[String] = []
var min_skill: int = 0
var repair_seconds: float = 5.0

func _init(
		p_id: String = "",
		p_required_parts: Array[String] = [],
		p_required_tools: Array[String] = [],
		p_min_skill: int = 0,
		p_repair_seconds: float = 5.0,
		p_operational_threshold: float = 0.5) -> void:
	subcomponent_id = p_id
	required_parts = p_required_parts.duplicate()
	required_tools = p_required_tools.duplicate()
	min_skill = p_min_skill
	repair_seconds = p_repair_seconds
	operational_threshold = p_operational_threshold

func is_functional() -> bool:
	return health >= operational_threshold

## Parameterized repair. Deterministic: success is fully determined by the
## requirements being met. Returns {success, reason, seconds}.
func repair(available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary:
	if is_functional():
		return {"success": false, "reason": "already_functional", "seconds": 0.0}
	for part in required_parts:
		if not available_parts.has(part):
			return {"success": false, "reason": "missing_parts", "seconds": 0.0}
	for tool in required_tools:
		if not available_tools.has(tool):
			return {"success": false, "reason": "missing_tools", "seconds": 0.0}
	if skill_level < min_skill:
		return {"success": false, "reason": "insufficient_skill", "seconds": 0.0}
	health = 1.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, skill_level - min_skill))
	return {"success": true, "reason": "ok", "seconds": repair_seconds / factor}

func get_summary() -> Dictionary:
	return {
		"subcomponent_id": subcomponent_id,
		"health": health,
		"operational_threshold": operational_threshold,
		"required_parts": required_parts.duplicate(),
		"required_tools": required_tools.duplicate(),
		"min_skill": min_skill,
		"repair_seconds": repair_seconds,
	}

## Restores mutable runtime state (health) from a summary. Static config
## (requirements/threshold) is not re-applied. Returns false on empty input.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_health: float = clampf(float(summary.get("health", health)), 0.0, 1.0)
	if absf(new_health - health) > 0.0001:
		health = new_health
		changed = true
	return changed
