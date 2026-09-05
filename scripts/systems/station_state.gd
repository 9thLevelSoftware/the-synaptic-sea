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
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0

var station_kind: String = ""       # e.g. "fabricator", "workbench", "kitchen"
var ship_id: String = ""            # physical owning ship for scheduled work
var station_instance_id: String = "" # stable physical placement identity
var active_job_id: String = ""       # scheduler projection; scheduler owns mutation
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
	ship_id = str(config.get("ship_id", ""))
	station_instance_id = str(config.get("station_instance_id", ""))
	active_job_id = ""
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
		"ship_id": ship_id,
		"station_instance_id": station_instance_id,
		"active_job_id": active_job_id,
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
	if summary.has("ship_id") or summary.has("station_instance_id") \
			or summary.has("active_job_id"):
		return apply_strict_summary(summary)
	var changed: bool = false
	var new_ship_id: String = str(summary.get("ship_id", ship_id))
	if new_ship_id != ship_id:
		ship_id = new_ship_id
		changed = true
	var new_station_id: String = str(summary.get("station_instance_id", station_instance_id))
	if new_station_id != station_instance_id:
		station_instance_id = new_station_id
		changed = true
	var new_job_id: String = str(summary.get("active_job_id", active_job_id))
	if new_job_id != active_job_id:
		active_job_id = new_job_id
		changed = true
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


## Current P07 envelope loader. Unlike the legacy apply_summary shim, this
## requires exact types and validates the complete record before mutation.
func apply_strict_summary(summary: Dictionary) -> bool:
	var normalized: Dictionary = _normalize_strict_summary(summary)
	if normalized.is_empty():
		return false
	ship_id = normalized.ship_id
	station_instance_id = normalized.station_instance_id
	active_job_id = normalized.active_job_id
	station_kind = normalized.station_kind
	level = normalized.level
	tier = normalized.tier
	max_queue = normalized.max_queue
	powered = normalized.powered
	active_recipe_id = normalized.active_recipe_id
	progress_seconds = normalized.progress_seconds
	required_seconds = normalized.required_seconds
	status = normalized.status
	queue.clear()
	for recipe_id in normalized.queue:
		queue.append(recipe_id)
	return true


func _normalize_strict_summary(summary: Dictionary) -> Dictionary:
	for key in ["ship_id", "station_instance_id", "active_job_id", "station_kind", "active_recipe_id"]:
		if typeof(summary.get(key, null)) != TYPE_STRING:
			return {}
	for key in ["level", "tier", "max_queue", "status"]:
		if not _is_nonnegative_json_integer(summary.get(key, null)):
			return {}
	if typeof(summary.get("powered", null)) != TYPE_BOOL \
			or not summary.get("queue", null) is Array:
		return {}
	for key in ["progress_seconds", "required_seconds"]:
		var value: Variant = summary.get(key, null)
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) \
				or not is_finite(float(value)):
			return {}
	var next_ship: String = str(summary.ship_id)
	var next_station: String = str(summary.station_instance_id)
	var next_job: String = str(summary.active_job_id)
	var next_kind: String = str(summary.station_kind)
	var next_level: int = int(summary.level)
	var next_tier: int = int(summary.tier)
	var next_max: int = int(summary.max_queue)
	var next_status: int = int(summary.status)
	var next_recipe: String = str(summary.active_recipe_id)
	var next_progress: float = float(summary.progress_seconds)
	var next_required: float = float(summary.required_seconds)
	var raw_queue: Array = summary.queue
	if next_kind.is_empty() or next_level < 0 or next_tier < 0 \
			or next_max < 1 or next_max > DEFAULT_MAX_QUEUE \
			or next_status < Status.IDLE or next_status > Status.PAUSED_NO_MATERIALS \
			or next_progress < 0.0 or next_required < 0.0 \
			or next_progress > next_required + 0.0001 or raw_queue.size() > next_max \
			or next_ship.is_empty() != next_station.is_empty() \
			or (not next_job.is_empty() and next_ship.is_empty()):
		return {}
	var next_queue: Array[String] = []
	for recipe_variant in raw_queue:
		if typeof(recipe_variant) != TYPE_STRING or str(recipe_variant).is_empty():
			return {}
		next_queue.append(str(recipe_variant))
	match next_status:
		Status.IDLE:
			if not next_recipe.is_empty() or not next_job.is_empty() \
					or next_progress != 0.0 or next_required != 0.0:
				return {}
		Status.CRAFTING, Status.PAUSED_POWER, Status.PAUSED_NO_MATERIALS:
			if next_recipe.is_empty() or next_required <= 0.0:
				return {}
		Status.COMPLETE:
			if next_recipe.is_empty() or next_required <= 0.0 \
					or absf(next_progress - next_required) > 0.0001:
				return {}
	return {
		"ship_id": next_ship,
		"station_instance_id": next_station,
		"active_job_id": next_job,
		"station_kind": next_kind,
		"level": next_level,
		"tier": next_tier,
		"max_queue": next_max,
		"powered": bool(summary.powered),
		"active_recipe_id": next_recipe,
		"progress_seconds": next_progress,
		"required_seconds": next_required,
		"status": next_status,
		"queue": next_queue,
	}


static func _is_nonnegative_json_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 \
		and number <= MAX_SAFE_JSON_INTEGER and number == floor(number)


## Read-only projection of the scheduler authority for existing station UI/status.
func set_scheduler_projection(job_summary: Dictionary) -> void:
	if job_summary.is_empty():
		active_job_id = ""
		active_recipe_id = ""
		progress_seconds = 0.0
		required_seconds = 0.0
		status = Status.IDLE
		return
	active_job_id = str(job_summary.get("job_id", ""))
	active_recipe_id = str(job_summary.get("recipe_id", ""))
	progress_seconds = float(job_summary.get("progress_seconds", 0.0))
	required_seconds = float(job_summary.get("required_seconds", 0.0))
	match str(job_summary.get("state", job_summary.get("phase", ""))):
		"running", "queued": status = Status.CRAFTING
		"paused_power": status = Status.PAUSED_POWER
		"blocked": status = Status.PAUSED_NO_MATERIALS
		"output_ready", "collected": status = Status.COMPLETE
		_: status = Status.IDLE

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
