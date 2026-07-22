extends RefCounted
class_name WorkActionChannel

## PKG-B2.5: shared WorkAction progress/interrupt channel for scene wrappers
## (RepairPoint, BreachSealPoint, FireSuppressionPoint).
## Domain gates and completion side-effects stay on the wrappers; this owns the
## pure WorkActionState tick path so all three share one progress/interrupt model.

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")

static var _shared_catalog: RefCounted = null

var work: RefCounted = null ## WorkActionState while active
var action_id: String = ""


static func shared_catalog() -> RefCounted:
	if _shared_catalog == null:
		_shared_catalog = WorkActionCatalogScript.new()
		_shared_catalog.load_default()
	return _shared_catalog


## Begin a catalog action. duration_seconds overrides the catalog default (skill-scaled repair, etc.).
## context is passed to WorkActionState.start for tool/skill/material gates when the definition has them.
func begin(p_action_id: String, target_id: String, duration_seconds: float, context: Dictionary = {}) -> bool:
	var cat = shared_catalog()
	if cat == null or not cat.has_action(p_action_id):
		return false
	var def: Dictionary = cat.get_action(p_action_id)
	if def.is_empty():
		return false
	var state = WorkActionStateScript.new()
	state.configure_action(p_action_id, def)
	state.duration = maxf(0.01, duration_seconds)
	if not state.start(target_id, context):
		return false
	work = state
	action_id = p_action_id
	return true


func tick(delta: float, context: Dictionary = {}) -> String:
	if work == null:
		return WorkActionStateScript.STATUS_IDLE
	return str(work.call("tick", delta, context))


func progress_ratio() -> float:
	if work == null:
		return 0.0
	return float(work.call("progress_ratio"))


func is_active() -> bool:
	if work == null:
		return false
	return str(work.get("status")) == WorkActionStateScript.STATUS_ACTIVE


func is_completed() -> bool:
	if work == null:
		return false
	return str(work.get("status")) == WorkActionStateScript.STATUS_COMPLETED


func is_interrupted() -> bool:
	if work == null:
		return false
	return str(work.get("status")) == WorkActionStateScript.STATUS_INTERRUPTED


func cancel() -> void:
	if work != null and work.has_method("reset"):
		work.call("reset")
	work = null
	action_id = ""


func get_summary() -> Dictionary:
	if work == null:
		return {"action_id": action_id, "status": WorkActionStateScript.STATUS_IDLE, "progress": 0.0}
	if work.has_method("get_summary"):
		return work.call("get_summary")
	return {"action_id": action_id, "status": str(work.get("status")), "progress": float(work.get("progress"))}
