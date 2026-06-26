extends RefCounted
class_name AudioLog

## AudioLog — data-only registry of voice-log entries (REQ-AU-006, ADR-0029).
##
## Each entry is a dictionary with: id, label, transcript, clip_path, duration,
## volume_db. The registry is pure data: callers (meta-event scheduler,
## audio_log_panel, save/load) look up entries by id and never mutate the
## registry in place. New entries are added by editing this constant table
## or by loading them from a JSON resource (future work).
##
## Pure data only: no scene-tree reach-in, no audio playback. The
## AudioManager owns an AudioStreamPlayer per playback and queries this
## registry for the entry to play.

const DEFAULT_ENTRIES: Array = [
	{
		"id": "log.beacon_01",
		"label": "Beacon — Distress 01",
		"transcript": "Mayday. Repeat, mayday. Reactor is critical. Hull integrity failing.",
		"clip_path": "res://data/audio/voice/log_beacon_01.ogg",
		"duration": 5.0,
		"volume_db": -3.0,
	},
	{
		"id": "log.beacon_02",
		"label": "Beacon — Distress 02",
		"transcript": "Biomatter incursion in sector four. Sealing the bulkhead. If you can hear this...",
		"clip_path": "res://data/audio/voice/log_beacon_02.ogg",
		"duration": 6.0,
		"volume_db": -3.0,
	},
	{
		"id": "log.pulse_01",
		"label": "Pulse — Biomatter 01",
		"transcript": "Ambient field resonance detected. Approaching pulse from aft quadrant.",
		"clip_path": "res://data/audio/voice/log_pulse_01.ogg",
		"duration": 4.0,
		"volume_db": -6.0,
	},
	{
		"id": "log.groan_01",
		"label": "Groan — Hull 01",
		"transcript": "Structural groans increasing. Recommend abandoning lower decks.",
		"clip_path": "res://data/audio/voice/log_groan_01.ogg",
		"duration": 3.5,
		"volume_db": -6.0,
	},
	{
		"id": "log.tutorial_pickup",
		"label": "Tutorial — Pickup",
		"transcript": "Acquired a portable oxygen pump. Use it near sealed bulkheads to extend your oxygen supply.",
		"clip_path": "res://data/audio/voice/log_tutorial_pickup.ogg",
		"duration": 4.5,
		"volume_db": -3.0,
	},
	{
		"id": "log.tutorial_calibrator",
		"label": "Tutorial — Calibrator",
		"transcript": "Junction calibrator acquired. Apply it to a damaged junction to skip a repair step.",
		"clip_path": "res://data/audio/voice/log_tutorial_calibrator.ogg",
		"duration": 5.0,
		"volume_db": -3.0,
	},
]

var _entries: Dictionary = {}

func _init() -> void:
	for entry in DEFAULT_ENTRIES:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id_value: Variant = entry.get("id", null)
		if id_value == null:
			continue
		_entries[String(id_value)] = entry

## Look up an entry by id. Returns an empty Dictionary when not found.
func get_entry(entry_id: StringName) -> Dictionary:
	return _entries.get(String(entry_id), {})

func has_entry(entry_id: StringName) -> bool:
	return _entries.has(String(entry_id))

func list_entry_ids() -> Array:
	return _entries.keys()

func get_all_entries() -> Array:
	return _entries.values()
