extends RefCounted
class_name ModuleIntegrityState

## PKG-B2.1a pure model — per placed structural module integrity (ADR-0051).

const STATE_INTACT: String = "intact"
const STATE_DAMAGED: String = "damaged"
const STATE_BREACHED: String = "breached"
const STATE_DESTROYED: String = "destroyed"

const THRESHOLD_DAMAGED: float = 0.75
const THRESHOLD_BREACHED: float = 0.40
const THRESHOLD_DESTROYED: float = 0.05

var module_id: String = ""
var kind: String = ""
var integrity: float = 1.0
var state: String = STATE_INTACT
var material_composition: Dictionary = {}
var mounted_components: Array = []
var base_integrity: float = 1.0
var tool_class_required: String = ""


func configure(config: Dictionary = {}) -> void:
	module_id = str(config.get("module_id", module_id))
	kind = str(config.get("kind", kind))
	base_integrity = maxf(0.01, float(config.get("base_integrity", 1.0)))
	integrity = clampf(float(config.get("integrity", base_integrity)), 0.0, base_integrity)
	tool_class_required = str(config.get("tool_class", tool_class_required))
	var comp: Variant = config.get("material_composition", {})
	if typeof(comp) == TYPE_DICTIONARY:
		material_composition = (comp as Dictionary).duplicate(true)
	var mounted: Variant = config.get("mounted_components", [])
	if typeof(mounted) == TYPE_ARRAY:
		mounted_components = (mounted as Array).duplicate(true)
	_recompute_state()


func apply_damage(amount: float) -> String:
	if amount <= 0.0 or state == STATE_DESTROYED:
		return state
	integrity = maxf(0.0, integrity - amount)
	return _recompute_state()


func repair(amount: float) -> String:
	if amount <= 0.0 or state == STATE_DESTROYED:
		return state
	integrity = minf(base_integrity, integrity + amount)
	return _recompute_state()


func _recompute_state() -> String:
	var ratio: float = integrity / base_integrity if base_integrity > 0.0 else 0.0
	if ratio <= THRESHOLD_DESTROYED:
		state = STATE_DESTROYED
	elif ratio <= THRESHOLD_BREACHED:
		state = STATE_BREACHED
	elif ratio <= THRESHOLD_DAMAGED:
		state = STATE_DAMAGED
	else:
		state = STATE_INTACT
	return state


func is_pristine() -> bool:
	return state == STATE_INTACT and absf(integrity - base_integrity) < 0.0001


func get_summary() -> Dictionary:
	return {
		"module_id": module_id,
		"kind": kind,
		"integrity": integrity,
		"base_integrity": base_integrity,
		"state": state,
		"material_composition": material_composition.duplicate(true),
		"mounted_components": mounted_components.duplicate(true),
		"tool_class": tool_class_required,
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	configure(summary)
	return true
