extends RefCounted
class_name SfxEventRouter

## SfxEventRouter — pure model that routes named audio events to buses
## (REQ-AU-001, ADR-0029).
##
## Routes a small set of stable event ids to the canonical bus. Each event
## carries a per-event volume (relative to the bus volume), an optional
## closed caption, and a dedup cooldown (seconds) that suppresses repeated
## firings within the cooldown window.
##
## The model never plays audio directly. `route(event_id)` returns a
## routing record (bus id, volume, caption) that the AudioManager applies
## to the right AudioStreamPlayer. The router also maintains a caption
## queue for the HUD to drain.
##
## Unknown event ids are pushed through `push_warning` and dropped — they
## are NEVER silently routed to master (the architectural invariant from
## ADR-0029).

const DEFAULT_CAPTION_DURATION: float = 2.5
const MAX_CAPTION_QUEUE: int = 16

## Per-event catalog. Each entry: {bus, volume_db, cooldown, caption}.
const EVENT_CATALOG: Dictionary = {
	String(AudioEventSeam.SFX_TOOL_PICKUP): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -3.0, "cooldown": 0.10, "caption": "Tool acquired"},
	String(AudioEventSeam.SFX_TOOL_USE): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -3.0, "cooldown": 0.05, "caption": "Tool used"},
	String(AudioEventSeam.SFX_SUIT_BREATH): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -12.0, "cooldown": 2.0, "caption": ""},
	String(AudioEventSeam.SFX_DOOR_OPEN): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -6.0, "cooldown": 0.10, "caption": "Door opened"},
	String(AudioEventSeam.SFX_DOOR_CLOSE): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -6.0, "cooldown": 0.10, "caption": "Door closed"},
	String(AudioEventSeam.SFX_FIRE_CRACKLE): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -6.0, "cooldown": 0.50, "caption": ""},
	String(AudioEventSeam.SFX_ARC_ZAP): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -4.0, "cooldown": 0.50, "caption": ""},
	String(AudioEventSeam.SFX_FOOTSTEP): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -10.0, "cooldown": 0.30, "caption": ""},
	String(AudioEventSeam.SFX_DROP_ITEM): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -6.0, "cooldown": 0.05, "caption": ""},
	String(AudioEventSeam.SFX_DOCK_LAND): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -3.0, "cooldown": 0.50, "caption": "Docked"},
	String(AudioEventSeam.SFX_HALLUCINATION_WHISPER): {"bus": AudioEventSeam.BUS_SFX, "volume_db": -14.0, "cooldown": 1.5, "caption": ""},

	String(AudioEventSeam.UI_INVENTORY_OPEN): {"bus": AudioEventSeam.BUS_UI, "volume_db": -6.0, "cooldown": 0.10, "caption": ""},
	String(AudioEventSeam.UI_INVENTORY_CLOSE): {"bus": AudioEventSeam.BUS_UI, "volume_db": -6.0, "cooldown": 0.10, "caption": ""},
	String(AudioEventSeam.UI_OBJECTIVE_ADVANCE): {"bus": AudioEventSeam.BUS_UI, "volume_db": -6.0, "cooldown": 0.10, "caption": "Objective updated"},
	String(AudioEventSeam.UI_SAVE): {"bus": AudioEventSeam.BUS_UI, "volume_db": -6.0, "cooldown": 0.10, "caption": ""},
	String(AudioEventSeam.UI_LOAD): {"bus": AudioEventSeam.BUS_UI, "volume_db": -6.0, "cooldown": 0.10, "caption": ""},
	String(AudioEventSeam.UI_VITALS_LOW): {"bus": AudioEventSeam.BUS_UI, "volume_db": -3.0, "cooldown": 4.0, "caption": "Vitals low"},

	String(AudioEventSeam.META_BEACON_DISTRESS): {"bus": AudioEventSeam.BUS_META, "volume_db": -6.0, "cooldown": 0.0, "caption": "Distress signal received"},
	String(AudioEventSeam.META_BIOMATTER_PULSE): {"bus": AudioEventSeam.BUS_META, "volume_db": -6.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.META_HULL_GROAN): {"bus": AudioEventSeam.BUS_META, "volume_db": -6.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.META_REACTOR_HUM): {"bus": AudioEventSeam.BUS_META, "volume_db": -12.0, "cooldown": 0.0, "caption": ""},

	String(AudioEventSeam.VOICE_LOG_PLAY): {"bus": AudioEventSeam.BUS_VOICE, "volume_db": -3.0, "cooldown": 0.10, "caption": ""},

	String(AudioEventSeam.AMB_CARGO): {"bus": AudioEventSeam.BUS_AMBIENT, "volume_db": -3.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.AMB_ENGINE): {"bus": AudioEventSeam.BUS_AMBIENT, "volume_db": -3.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.AMB_MED_BAY): {"bus": AudioEventSeam.BUS_AMBIENT, "volume_db": -3.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.AMB_CREW_QUARTERS): {"bus": AudioEventSeam.BUS_AMBIENT, "volume_db": -3.0, "cooldown": 0.0, "caption": ""},
	String(AudioEventSeam.AMB_DOCKING): {"bus": AudioEventSeam.BUS_AMBIENT, "volume_db": -3.0, "cooldown": 0.0, "caption": ""},
}

var captions_enabled: bool = true
var caption_duration: float = DEFAULT_CAPTION_DURATION
var _cooldown_clock: Dictionary = {}
var _tick_elapsed: float = 0.0
var _caption_queue: Array = []
var _routed_count: Dictionary = {}
var _dropped_count: int = 0

## Configure from a Dictionary. Recognized keys:
##   - "captions_enabled": bool (default true)
##   - "caption_duration": float (clamped to [0.5, 10.0])
## Unknown keys are ignored.
func configure(config: Dictionary) -> void:
	if config == null:
		return
	if config.has("captions_enabled"):
		captions_enabled = bool(config["captions_enabled"])
	if config.has("caption_duration"):
		caption_duration = clampf(float(config["caption_duration"]), 0.5, 10.0)
	_cooldown_clock.clear()
	_caption_queue.clear()
	_routed_count.clear()
	_dropped_count = 0
	_tick_elapsed = 0.0

## Route an event id. Returns a Dictionary {bus, volume_db, event_id} on
## success; null when the id is unknown or suppressed by cooldown. Captions
## are queued separately via get_pending_captions(). Set `emit_warning=false`
## for tests that deliberately probe the unknown-id contract.
func route(event_id: StringName, emit_warning: bool = true) -> Variant:
	var id_str: String = String(event_id)
	if not EVENT_CATALOG.has(id_str):
		_dropped_count += 1
		if emit_warning:
			push_warning("SfxEventRouter: dropped unknown event id '%s'" % id_str)
		return null
	var spec: Dictionary = EVENT_CATALOG[id_str]
	# Cooldown uses an elapsed surrogate carried by tick(): the entry stores
	# the "elapsed" value at the moment the event last fired. On a fresh
	# model `_cooldown_clock` is empty, so the first fire always succeeds.
	# Subsequent fires compare `now` (the latest elapsed tick) to `last`
	# (the elapsed at the previous fire) and reject when the gap is smaller
	# than the cooldown.
	var last: float = -1.0
	if _cooldown_clock.has(id_str):
		last = float(_cooldown_clock[id_str])
	var now: float = _tick_elapsed
	var cooldown: float = float(spec.get("cooldown", 0.0))
	if last >= 0.0 and (now - last) < cooldown:
		_dropped_count += 1
		return null
	_cooldown_clock[id_str] = now
	_routed_count[id_str] = int(_routed_count.get(id_str, 0)) + 1
	var caption: String = String(spec.get("caption", ""))
	if captions_enabled and not caption.is_empty():
		_enqueue_caption(id_str, caption)
	return {
		"event_id": id_str,
		"bus": spec.get("bus", AudioEventSeam.BUS_SFX),
		"volume_db": float(spec.get("volume_db", -6.0)),
	}

## Queue a caption. Internal helper; public so the playable can re-queue
## from non-router paths (e.g. dialog system). Honors the captions_enabled
## toggle and the MAX_CAPTION_QUEUE cap.
func enqueue_caption(event_id: StringName, text: String, duration: float = -1.0) -> bool:
	return _enqueue_caption(String(event_id), text, duration)

func _enqueue_caption(event_id: String, text: String, duration: float = -1.0) -> bool:
	if not captions_enabled:
		return false
	if text.is_empty():
		return false
	if _caption_queue.size() >= MAX_CAPTION_QUEUE:
		# Drop the oldest entry so a runaway emitter can't stall the HUD.
		_caption_queue.pop_front()
	var caption_duration: float = self.caption_duration if duration < 0.0 else clampf(duration, 0.5, 10.0)
	_caption_queue.append({
		"event_id": event_id,
		"text": text,
		"duration": caption_duration,
		"elapsed": 0.0,
	})
	return true

## Advance the cooldown clock and the caption queue. Cooldown uses the
## elapsed time since the last tick as the "now" value, so callers don't
## need a wall clock.
func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	_tick_elapsed += delta_seconds
	var dropped: int = 0
	var i: int = 0
	while i < _caption_queue.size():
		var entry: Dictionary = _caption_queue[i]
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta_seconds
		if float(entry.get("elapsed", 0.0)) >= float(entry.get("duration", self.caption_duration)):
			_caption_queue.remove_at(i)
			dropped += 1
		else:
			_caption_queue[i] = entry
			i += 1
	return dropped > 0

## Drain the caption queue. Returns an array of caption dicts and clears
## the queue. The HUD consumes these each frame.
func get_pending_captions() -> Array:
	var pending: Array = _caption_queue.duplicate(true)
	_caption_queue.clear()
	return pending

## Snapshot the caption queue without draining (for inspection / save).
func peek_captions() -> Array:
	return _caption_queue.duplicate(true)

func get_routed_count(event_id: StringName) -> int:
	return int(_routed_count.get(String(event_id), 0))

func get_dropped_count() -> int:
	return _dropped_count

## Static lookup helpers (used by AudioManager.apply_bus_volumes path and by
## the audio_save_load_smoke).
static func get_bus_for_event(event_id: StringName) -> StringName:
	var spec: Dictionary = EVENT_CATALOG.get(String(event_id), {})
	return spec.get("bus", AudioEventSeam.BUS_SFX) if not spec.is_empty() else AudioEventSeam.BUS_SFX

static func get_volume_for_event(event_id: StringName) -> float:
	var spec: Dictionary = EVENT_CATALOG.get(String(event_id), {})
	return float(spec.get("volume_db", -6.0)) if not spec.is_empty() else -6.0

static func get_caption_for_event(event_id: StringName) -> String:
	var spec: Dictionary = EVENT_CATALOG.get(String(event_id), {})
	return String(spec.get("caption", "")) if not spec.is_empty() else ""

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var routed_total: int = 0
	for k in _routed_count.keys():
		routed_total += int(_routed_count[k])
	lines.append("Sfx router: routed=%d dropped=%d captions=%d" % [routed_total, _dropped_count, _caption_queue.size()])
	return lines

func get_summary() -> Dictionary:
	var routed: Dictionary = {}
	for event_id in _routed_count.keys():
		routed[String(event_id)] = int(_routed_count[event_id])
	return {
		"kind": "sfx_event_router",
		"captions_enabled": captions_enabled,
		"caption_duration": caption_duration,
		"cooldown_clock": _cooldown_clock.duplicate(true),
		"routed_count": routed,
		"dropped_count": _dropped_count,
		"caption_queue_size": _caption_queue.size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "sfx_event_router":
		return false
	var changed: bool = false
	if summary.has("captions_enabled"):
		var new_ce: bool = bool(summary["captions_enabled"])
		if new_ce != captions_enabled:
			captions_enabled = new_ce
			changed = true
	if summary.has("caption_duration"):
		var new_cd: float = clampf(float(summary["caption_duration"]), 0.5, 10.0)
		if absf(new_cd - caption_duration) > 0.001:
			caption_duration = new_cd
			changed = true
	if summary.has("cooldown_clock"):
		var cd: Variant = summary["cooldown_clock"]
		if typeof(cd) == TYPE_DICTIONARY:
			_cooldown_clock = (cd as Dictionary).duplicate(true)
			changed = true
	if summary.has("routed_count"):
		var rc: Variant = summary["routed_count"]
		if typeof(rc) == TYPE_DICTIONARY:
			_routed_count.clear()
			for k in (rc as Dictionary).keys():
				_routed_count[String(k)] = int((rc as Dictionary)[k])
			changed = true
	if summary.has("dropped_count"):
		_dropped_count = int(summary["dropped_count"])
	return changed
