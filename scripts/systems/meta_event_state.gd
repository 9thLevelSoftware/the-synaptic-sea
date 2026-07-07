extends RefCounted
class_name MetaEventState

const AudioEventSeam := preload("res://scripts/audio/audio_event_seam.gd")

## MetaEventState — deterministic seed-derived meta-event scheduler
## (REQ-AU-007, ADR-0029).
##
## Holds a schedule of scripted meta-events (id, trigger_time, voice_log_id,
## base_volume_db). The model ticks every frame; when `time >= trigger_time`
## the event fires and is recorded in the summary so it never re-fires
## within a run.
##
## Determinism:
## - The schedule is built from a run seed (passed to configure()) so
##   re-running with the same seed produces the same sequence.
## - Trigger times are sorted ascending after construction so `tick()`
##   only walks the schedule once per event.
##
## The model is pure: it never reaches into AudioManager or the scene tree.
## AudioManager reads get_due_events() each tick and routes each one
## through SfxEventRouter + AudioManager.play_sfx(...).

## Default trigger schedule (seconds from run start). Used when configure
## is not given an explicit "events" array. Covers one of each canonical
## meta-event type so the smoke exercises every kind.
const DEFAULT_SCHEDULE: Array = [
	{"id": AudioEventSeam.META_EVENT_BEACON, "trigger_time": 12.0, "voice_log_id": "log.beacon_01", "volume_db": -3.0},
	{"id": AudioEventSeam.META_EVENT_PULSE, "trigger_time": 30.0, "voice_log_id": "log.pulse_01", "volume_db": -6.0},
	{"id": AudioEventSeam.META_EVENT_GROAN, "trigger_time": 55.0, "voice_log_id": "", "volume_db": -6.0},
]

var _run_seed: int = 0
var _elapsed: float = 0.0
var _events: Array = []
var _fired_events: Array = []

func configure(config: Dictionary) -> void:
	if config == null:
		config = {}
	_run_seed = int(config.get("run_seed", 0))
	var events_in: Variant = config.get("events", DEFAULT_SCHEDULE)
	_events.clear()
	_fired_events.clear()
	_elapsed = float(config.get("initial_elapsed", 0.0))
	if typeof(events_in) == TYPE_ARRAY:
		for ev in (events_in as Array):
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var ev_dict: Dictionary = ev
			var id_value: Variant = ev_dict.get("id", null)
			if id_value == null:
				continue
			_events.append({
				"id": String(id_value),
				"trigger_time": maxf(0.0, float(ev_dict.get("trigger_time", 0.0))),
				"voice_log_id": String(ev_dict.get("voice_log_id", "")),
				"volume_db": clampf(float(ev_dict.get("volume_db", -6.0)), -60.0, 0.0),
			})
	_events.sort_custom(func(a, b): return float(a.get("trigger_time", 0.0)) < float(b.get("trigger_time", 0.0)))
	# Seed determinism: if a seed is supplied and no explicit events were
	# provided, derive a deterministic time-offset (in seconds) that perturbs
	# the schedule consistently across calls without touching the order.
	if _run_seed != 0 and config.get("events", null) == null:
		var offset: float = float(abs(_run_seed) % 7) * 0.5
		for i in range(_events.size()):
			var ev: Dictionary = _events[i]
			ev["trigger_time"] = float(ev.get("trigger_time", 0.0)) + offset
			_events[i] = ev
		_events.sort_custom(func(a, b): return float(a.get("trigger_time", 0.0)) < float(b.get("trigger_time", 0.0)))

## Advance time and fire any due events. Returns the array of events that
## fired during this tick (each: {id, trigger_time, voice_log_id, volume_db}).
func tick(delta_seconds: float) -> Array:
	if delta_seconds <= 0.0:
		return []
	_elapsed += delta_seconds
	var due: Array = []
	var keep: Array = []
	for ev in _events:
		var trigger_time: float = float(ev.get("trigger_time", 0.0))
		if _elapsed >= trigger_time:
			var fired: Dictionary = ev.duplicate(true)
			fired["fired_at"] = _elapsed
			due.append(fired)
			_fired_events.append(fired)
		else:
			keep.append(ev)
	_events = keep
	return due

## Inject an event at a specific time. Useful for runtime scheduling (a
## future meta-event system can call this without rebuilding the schedule).
## Returns true if the event was added.
func schedule_event(event_id: StringName, trigger_time: float, voice_log_id: String = "", volume_db: float = -6.0) -> bool:
	if String(event_id).is_empty():
		return false
	_events.append({
		"id": String(event_id),
		"trigger_time": maxf(0.0, trigger_time),
		"voice_log_id": voice_log_id,
		"volume_db": clampf(volume_db, -60.0, 0.0),
	})
	_events.sort_custom(func(a, b): return float(a.get("trigger_time", 0.0)) < float(b.get("trigger_time", 0.0)))
	return true

func get_elapsed() -> float:
	return _elapsed

func get_pending_count() -> int:
	return _events.size()

func get_fired_count() -> int:
	return _fired_events.size()

func get_pending_events() -> Array:
	return _events.duplicate(true)

func get_fired_events() -> Array:
	return _fired_events.duplicate(true)

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Meta events: elapsed=%.2f pending=%d fired=%d" % [_elapsed, _events.size(), _fired_events.size()])
	return lines

func get_summary() -> Dictionary:
	return {
		"kind": "meta_event_state",
		"run_seed": _run_seed,
		"elapsed": _elapsed,
		"pending": _events.duplicate(true),
		"fired": _fired_events.duplicate(true),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "meta_event_state":
		return false
	var changed: bool = false
	if summary.has("run_seed"):
		_run_seed = int(summary["run_seed"])
	if summary.has("elapsed"):
		_elapsed = float(summary["elapsed"])
		changed = true
	if summary.has("pending"):
		var pending: Variant = summary["pending"]
		if typeof(pending) == TYPE_ARRAY:
			_events = (pending as Array).duplicate(true)
			changed = true
	if summary.has("fired"):
		var fired: Variant = summary["fired"]
		if typeof(fired) == TYPE_ARRAY:
			_fired_events = (fired as Array).duplicate(true)
			changed = true
	return changed
