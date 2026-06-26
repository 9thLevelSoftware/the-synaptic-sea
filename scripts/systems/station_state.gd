extends RefCounted
class_name StationState

## Pure model for a crafting station. Tracks station kind, level, power state,
## active recipe, and progress. Never touches the scene tree.

enum Status {
	IDLE = 0,
	CRAFTING = 1,
	PAUSED_POWER = 2,
	COMPLETE = 3,
	PAUSED_NO_MATERIALS = 4,
}

var station_kind: String = ""       # e.g. "fabricator", "workbench", "kitchen"
var level: int = 0                  # upgrade level (0 = base)
var powered: bool = true            # power available
var active_recipe_id: String = ""   # currently crafting recipe
var progress_seconds: float = 0.0   # elapsed craft time
var required_seconds: float = 0.0   # total craft time for active recipe
var status: int = Status.IDLE
var queue: Array[String] = []       # queued recipe_ids

func configure(config: Dictionary) -> void:
	station_kind = str(config.get("station_kind", ""))
	level = maxi(0, int(config.get("level", 0)))
	powered = bool(config.get("powered", true))
	active_recipe_id = ""
	progress_seconds = 0.0
	required_seconds = 0.0
	status = Status.IDLE
	queue.clear()
	var q: Variant = config.get("queue", [])
	if q is Array:
		for item in (q as Array):
			var rid: String = str(item)
			if not rid.is_empty():
				queue.append(rid)

## Start crafting a recipe. Returns true if started.
func start_recipe(recipe_id: String, craft_time: float) -> bool:
	if recipe_id.is_empty() or craft_time <= 0.0:
		return false
	if not powered:
		status = Status.PAUSED_POWER
		active_recipe_id = recipe_id
		required_seconds = craft_time
		progress_seconds = 0.0
		return false
	active_recipe_id = recipe_id
	required_seconds = craft_time
	progress_seconds = 0.0
	status = Status.CRAFTING
	return true

## Queue a recipe for later.
func enqueue(recipe_id: String) -> void:
	if not recipe_id.is_empty():
		queue.append(recipe_id)

func dequeue() -> String:
	if queue.is_empty():
		return ""
	return queue.pop_at(0)

## Advance craft progress by delta_seconds. Returns true when the craft completes.
func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	if status == Status.COMPLETE:
		return false
	if not powered:
		if status == Status.CRAFTING:
			status = Status.PAUSED_POWER
		return false
	if status == Status.PAUSED_POWER and powered:
		status = Status.CRAFTING
	if status != Status.CRAFTING:
		return false
	progress_seconds += delta_seconds
	if progress_seconds >= required_seconds:
		progress_seconds = required_seconds
		status = Status.COMPLETE
		return true
	return false

## Mark the completed craft as consumed and advance to the next queued recipe.
## Returns the next recipe_id if one was queued, else empty.
func finish_and_advance() -> String:
	if status != Status.COMPLETE:
		return ""
	var previous_required_seconds: float = required_seconds
	active_recipe_id = ""
	progress_seconds = 0.0
	required_seconds = 0.0
	status = Status.IDLE
	var next: String = dequeue()
	if not next.is_empty():
		active_recipe_id = next
		required_seconds = previous_required_seconds
		progress_seconds = 0.0
		status = Status.CRAFTING if powered else Status.PAUSED_POWER
	return next

func set_power(p: bool) -> void:
	powered = p
	if not p and status == Status.CRAFTING:
		status = Status.PAUSED_POWER
	elif p and status == Status.PAUSED_POWER:
		status = Status.CRAFTING

func is_crafting() -> bool:
	return status == Status.CRAFTING or status == Status.PAUSED_POWER

func get_progress_ratio() -> float:
	if required_seconds <= 0.0:
		return 0.0
	return clampf(progress_seconds / required_seconds, 0.0, 1.0)

func get_summary() -> Dictionary:
	return {
		"station_kind": station_kind,
		"level": level,
		"powered": powered,
		"active_recipe_id": active_recipe_id,
		"progress_seconds": progress_seconds,
		"required_seconds": required_seconds,
		"status": status,
		"queue": queue.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_kind: String = str(summary.get("station_kind", station_kind))
	if new_kind != station_kind:
		station_kind = new_kind
		changed = true
	var new_level: int = int(summary.get("level", level))
	if new_level != level:
		level = new_level
		changed = true
	var new_powered: bool = bool(summary.get("powered", powered))
	if new_powered != powered:
		powered = new_powered
		changed = true
	var new_recipe: String = str(summary.get("active_recipe_id", active_recipe_id))
	if new_recipe != active_recipe_id:
		active_recipe_id = new_recipe
		changed = true
	var new_prog: float = float(summary.get("progress_seconds", progress_seconds))
	if absf(new_prog - progress_seconds) > 0.001:
		progress_seconds = new_prog
		changed = true
	var new_req: float = float(summary.get("required_seconds", required_seconds))
	if absf(new_req - required_seconds) > 0.001:
		required_seconds = new_req
		changed = true
	var new_status: int = int(summary.get("status", status))
	if new_status != status:
		status = new_status
		changed = true
	var new_q: Variant = summary.get("queue", [])
	if new_q is Array:
		var arr: Array = new_q as Array
		if arr != queue:
			queue.clear()
			for item in arr:
				queue.append(str(item))
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var status_name: String = "IDLE"
	match status:
		Status.CRAFTING: status_name = "CRAFTING"
		Status.PAUSED_POWER: status_name = "PAUSED_POWER"
		Status.PAUSED_NO_MATERIALS: status_name = "PAUSED_NO_MATERIALS"
		Status.COMPLETE: status_name = "COMPLETE"
	lines.append("Station: %s L%d [%s]" % [station_kind, level, status_name])
	if is_crafting() or status == Status.COMPLETE:
		lines.append("Recipe: %s %.1f/%.1fs" % [active_recipe_id, progress_seconds, required_seconds])
	if not queue.is_empty():
		lines.append("Queue: %d" % queue.size())
	return lines
