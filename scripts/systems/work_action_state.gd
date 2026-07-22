extends RefCounted
class_name WorkActionState

## PKG-B2.2a pure timed work model: progress, interrupt, tool/skill/material gates.
## Scene layer drives start/tick; this never touches the tree.

const STATUS_IDLE: String = "idle"
const STATUS_ACTIVE: String = "active"
const STATUS_COMPLETED: String = "completed"
const STATUS_INTERRUPTED: String = "interrupted"
const STATUS_BLOCKED: String = "blocked"

var action_id: String = ""
var definition: Dictionary = {}
var status: String = STATUS_IDLE
var progress: float = 0.0
var duration: float = 1.0
var target_id: String = ""
var block_reason: String = ""


func configure_action(p_action_id: String, def: Dictionary) -> void:
	action_id = p_action_id
	definition = def.duplicate(true)
	duration = maxf(0.1, float(definition.get("duration", 1.0)))
	status = STATUS_IDLE
	progress = 0.0
	block_reason = ""
	target_id = ""


## context keys: tool_class, skill_id, skill_level, inventory (Dictionary item->qty), damaged (bool)
func can_start(context: Dictionary = {}) -> bool:
	block_reason = ""
	if definition.is_empty():
		block_reason = "no_definition"
		return false
	var required_tool: String = str(definition.get("tool_class", ""))
	if not required_tool.is_empty():
		var have_tool: String = str(context.get("tool_class", ""))
		if have_tool != required_tool:
			block_reason = "tool"
			return false
	var min_skill: String = str(definition.get("min_skill", ""))
	if not min_skill.is_empty():
		var skill_id: String = str(context.get("skill_id", ""))
		var skill_level: int = int(context.get("skill_level", 0))
		var need: int = int(definition.get("min_skill_level", 0))
		if skill_id != min_skill or skill_level < need:
			block_reason = "skill"
			return false
	var consumed: Variant = definition.get("materials_consumed", {})
	if typeof(consumed) == TYPE_DICTIONARY and not (consumed as Dictionary).is_empty():
		var inv: Variant = context.get("inventory", {})
		if typeof(inv) != TYPE_DICTIONARY:
			block_reason = "materials"
			return false
		for item_id in (consumed as Dictionary).keys():
			var need_qty: int = int((consumed as Dictionary)[item_id])
			var have_qty: int = int((inv as Dictionary).get(str(item_id), 0))
			if have_qty < need_qty:
				block_reason = "materials"
				return false
	return true


func start(p_target_id: String, context: Dictionary = {}) -> bool:
	if status == STATUS_ACTIVE:
		return false
	if not can_start(context):
		status = STATUS_BLOCKED
		return false
	target_id = p_target_id
	progress = 0.0
	status = STATUS_ACTIVE
	block_reason = ""
	return true


func tick(delta: float, context: Dictionary = {}) -> String:
	if status != STATUS_ACTIVE:
		return status
	if bool(context.get("damaged", false)) and bool(definition.get("interruptible", true)):
		status = STATUS_INTERRUPTED
		return status
	if delta <= 0.0:
		return status
	# Optional work-speed mult (wounds/arm injury later).
	var speed: float = maxf(0.05, float(context.get("work_speed_mult", 1.0)))
	progress = minf(duration, progress + delta * speed)
	if progress >= duration - 0.0001:
		status = STATUS_COMPLETED
		progress = duration
	return status


func interrupt() -> void:
	if status == STATUS_ACTIVE:
		status = STATUS_INTERRUPTED


func reset() -> void:
	status = STATUS_IDLE
	progress = 0.0
	target_id = ""
	block_reason = ""


func progress_ratio() -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(progress / duration, 0.0, 1.0)


func noise() -> float:
	return maxf(0.0, float(definition.get("noise", 0.0)))


func xp_event() -> String:
	return str(definition.get("xp_event", ""))


func materials_yielded() -> Dictionary:
	var y: Variant = definition.get("materials_yielded", {})
	if typeof(y) == TYPE_DICTIONARY:
		return (y as Dictionary).duplicate(true)
	return {}


func materials_consumed() -> Dictionary:
	var c: Variant = definition.get("materials_consumed", {})
	if typeof(c) == TYPE_DICTIONARY:
		return (c as Dictionary).duplicate(true)
	return {}


func get_summary() -> Dictionary:
	return {
		"action_id": action_id,
		"status": status,
		"progress": progress,
		"duration": duration,
		"target_id": target_id,
		"block_reason": block_reason,
		"definition": definition.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	action_id = str(summary.get("action_id", action_id))
	status = str(summary.get("status", STATUS_IDLE))
	progress = float(summary.get("progress", 0.0))
	duration = maxf(0.1, float(summary.get("duration", duration)))
	target_id = str(summary.get("target_id", ""))
	block_reason = str(summary.get("block_reason", ""))
	var def: Variant = summary.get("definition", {})
	if typeof(def) == TYPE_DICTIONARY:
		definition = (def as Dictionary).duplicate(true)
	return true
