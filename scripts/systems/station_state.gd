extends RefCounted
class_name StationState

## Pure model for a crafting station. Tracks station kind, level/tier, power state,
## active recipe, batch queue, and progress. Never touches the scene tree.
## PKG-B2.4b: tier from installed components; max_queue + batch enqueue.

enum Status {
	IDLE = 0,
	CRAFTING = 1,
	PAUSED_POWER = 2,
	COMPLETE = 3,
	PAUSED_NO_MATERIALS = 4,
}

const DEFAULT_MAX_QUEUE: int = 8

var station_kind: String = ""       # e.g. "fabricator", "workbench", "kitchen"
var level: int = 0                  # upgrade level (0 = base); mirrors tier when unset
var tier: int = 0                   # PKG-B2.4b: effective station tier (component-derived)
var powered: bool = true            # power available
var active_recipe_id: String = ""   # currently crafting recipe
var progress_seconds: float = 0.0   # elapsed craft time
var required_seconds: float = 0.0   # total craft time for active recipe
var status: int = Status.IDLE
var queue: Array[String] = []       # queued recipe_ids
var max_queue: int = DEFAULT_MAX_QUEUE

func configure(config: Dictionary) -> void:
	station_kind = str(config.get("station_kind", ""))
	level = maxi(0, int(config.get("level", 0)))
	tier = maxi(0, int(config.get("tier", level)))
	powered = bool(config.get("powered", true))
	max_queue = maxi(1, int(config.get("max_queue", DEFAULT_MAX_QUEUE)))
	active_recipe_id = ""
	progress_seconds = 0.0
	required_seconds = 0.0
	status = Status.IDLE
	queue.clear()
	var q: Variant = config.get("queue", [])
	if q is Array:
		for item in (q as Array):
			var rid: String = str(item)
			if not rid.is_empty() and queue.size() < max_queue:
				queue.append(rid)

## PKG-B2.4b: set tier from installed components (max of bonuses, at least level).
func apply_component_tier(component_tier_bonus: int) -> void:
	tier = maxi(level, maxi(0, component_tier_bonus))


func effective_tier() -> int:
	return maxi(tier, level)

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

## Queue a recipe for later. Returns false if queue is full or id empty.
func enqueue(recipe_id: String) -> bool:
	if recipe_id.is_empty():
		return false
	if queue.size() >= max_queue:
		return false
	queue.append(recipe_id)
	return true


## PKG-B2.4b: enqueue the same recipe count times (batch). Returns accepted count.
func enqueue_batch(recipe_id: String, count: int) -> int:
	if recipe_id.is_empty() or count <= 0:
		return 0
	var accepted: int = 0
	for _i in range(count):
		if not enqueue(recipe_id):
			break
		accepted += 1
	return accepted


func queue_space() -> int:
	return maxi(0, max_queue - queue.size())


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
		"tier": tier,
		"max_queue": max_queue,
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
	var new_tier: int = int(summary.get("tier", tier))
	if new_tier != tier:
		tier = new_tier
		changed = true
	var new_max_q: int = int(summary.get("max_queue", max_queue))
	if new_max_q != max_queue and new_max_q >= 1:
		max_queue = new_max_q
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
	lines.append("Station: %s L%d T%d [%s]" % [station_kind, level, effective_tier(), status_name])
	if is_crafting() or status == Status.COMPLETE:
		lines.append("Recipe: %s %.1f/%.1fs" % [active_recipe_id, progress_seconds, required_seconds])
	if not queue.is_empty():
		lines.append("Queue: %d/%d" % [queue.size(), max_queue])
	return lines
