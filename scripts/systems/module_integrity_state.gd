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

const CURRENT_SUMMARY_KEYS: Array[String] = [
	"module_id", "kind", "room_id", "integrity", "base_integrity", "state",
	"material_composition", "mounted_components", "tool_class",
]

var module_id: String = ""
var kind: String = ""
var integrity: float = 1.0
var state: String = STATE_INTACT
var material_composition: Dictionary = {}
var mounted_components: Array = []
var base_integrity: float = 1.0
var tool_class_required: String = ""
## Owning room (optional; used for fire/nav routing).
var room_id: String = ""
## All rooms sharing this compiled module (shared walls).
var owner_rooms: PackedStringArray = PackedStringArray()


func configure(config: Dictionary = {}) -> void:
	module_id = str(config.get("module_id", module_id))
	kind = str(config.get("kind", kind))
	room_id = str(config.get("room_id", room_id))
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


## Applies an explicitly authored initial state when no numeric damage amount is
## available. Runtime damage and ordinary repair continue through their existing
## amount-based methods.
func apply_authored_state(authored_state: String, authored_integrity: float = -1.0) -> bool:
	if authored_state not in [STATE_INTACT, STATE_DAMAGED, STATE_BREACHED, STATE_DESTROYED]:
		return false
	var next_integrity: float = authored_integrity
	if next_integrity < 0.0:
		match authored_state:
			STATE_INTACT:
				next_integrity = base_integrity
			STATE_DAMAGED:
				next_integrity = base_integrity * THRESHOLD_DAMAGED
			STATE_BREACHED:
				next_integrity = base_integrity * THRESHOLD_BREACHED
			STATE_DESTROYED:
				next_integrity = base_integrity * THRESHOLD_DESTROYED
	var previous_integrity: float = integrity
	var previous_state: String = state
	integrity = clampf(next_integrity, 0.0, base_integrity)
	if _recompute_state() != authored_state:
		integrity = previous_integrity
		state = previous_state
		return false
	return true


func _recompute_state() -> String:
	state = state_for_health(integrity, base_integrity)
	return state


func is_pristine() -> bool:
	# Sparse persistence must keep modules with component mutations even if undamaged.
	if state != STATE_INTACT:
		return false
	if absf(integrity - base_integrity) > 0.0001:
		return false
	if not mounted_components.is_empty():
		return false
	return true


func get_summary() -> Dictionary:
	return {
		"module_id": module_id,
		"kind": kind,
		"room_id": room_id,
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


## Current saves reach this only after ModuleIntegrityMap's public admission
## validator. Keep the checks local as a fail-closed guard for direct callers,
## then assign the admitted health tuple without configure()'s historical
## coercion, clamping, or state recomputation.
func apply_current_summary(summary: Dictionary) -> bool:
	if summary.size() != CURRENT_SUMMARY_KEYS.size():
		return false
	for key in CURRENT_SUMMARY_KEYS:
		if not summary.has(key):
			return false
	for key in ["module_id", "kind", "room_id", "state", "tool_class"]:
		if typeof(summary.get(key, null)) != TYPE_STRING:
			return false
	if (summary.module_id as String).is_empty() \
			or not summary.material_composition is Dictionary \
			or not summary.mounted_components is Array:
		return false
	var integrity_value: Variant = summary.integrity
	var base_value: Variant = summary.base_integrity
	if (typeof(integrity_value) != TYPE_INT and typeof(integrity_value) != TYPE_FLOAT) \
			or (typeof(base_value) != TYPE_INT and typeof(base_value) != TYPE_FLOAT):
		return false
	var admitted_integrity: float = float(integrity_value)
	var admitted_base: float = float(base_value)
	if not is_finite(admitted_integrity) or not is_finite(admitted_base) \
			or admitted_base <= 0.0 or admitted_integrity < 0.0 \
			or admitted_integrity > admitted_base \
			or summary.state != state_for_health(admitted_integrity, admitted_base):
		return false
	module_id = summary.module_id as String
	kind = summary.kind as String
	room_id = summary.room_id as String
	integrity = admitted_integrity
	base_integrity = admitted_base
	state = summary.state as String
	material_composition = (summary.material_composition as Dictionary).duplicate(true)
	mounted_components = (summary.mounted_components as Array).duplicate(true)
	tool_class_required = summary.tool_class as String
	return true


static func state_for_health(integrity_value: float, base_value: float) -> String:
	var ratio: float = integrity_value / base_value if base_value > 0.0 else 0.0
	if ratio <= THRESHOLD_DESTROYED:
		return STATE_DESTROYED
	if ratio <= THRESHOLD_BREACHED:
		return STATE_BREACHED
	if ratio <= THRESHOLD_DAMAGED:
		return STATE_DAMAGED
	return STATE_INTACT
