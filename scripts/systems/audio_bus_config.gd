extends Resource
class_name AudioBusConfig

const AudioEventSeam := preload("res://scripts/audio/audio_event_seam.gd")

## AudioBusConfig — Resource describing the audio bus layout (REQ-AU-002,
## ADR-0029).
##
## A Resource (not a RefCounted) because it is data: a loadable asset that
## artists / designers can edit in the Godot editor or commit as a .tres.
## The seven buses (master, sfx, music, voice, ui, ambient, meta) are owned
## by this resource, which validates its own contents at load time.
##
## Per ADR-0029:
## - Each bus has an id, a parent id, and a default dB volume.
## - Volumes are clamped to [-60, 0].
## - Bus ids are unique and non-empty.
## - All buses except master must have `parent_id == "master"`.
##
## AudioManager.apply_bus_volumes() pushes the volumes into the live
## AudioServer. The AudioBusConfig resource itself never reaches into the
## engine — it is pure data + schema validation.

const MIN_DB: float = -60.0
const MAX_DB: float = 0.0

## Default per-bus volumes (dB) — the values every playable scene boots with.
const DEFAULT_MASTER_DB: float = 0.0
const DEFAULT_SFX_DB: float = -3.0
const DEFAULT_MUSIC_DB: float = -6.0
const DEFAULT_VOICE_DB: float = -3.0
const DEFAULT_UI_DB: float = -6.0
const DEFAULT_AMBIENT_DB: float = -9.0
const DEFAULT_META_DB: float = -6.0

## Internal bus records. Each entry: {"id": StringName, "parent_id": StringName,
## "volume_db": float, "muted": bool}.
## Marked as a typed Array so the .tres can serialize it via @export.
@export var buses: Array = []

## Convenience flag — set by validate() when the resource passes schema checks.
var _validated: bool = false

## Construct a default bus layout matching ADR-0029. Call this from a
## factory or from a .tres loader that wants a known-good baseline.
static func make_default() -> AudioBusConfig:
	var cfg := AudioBusConfig.new()
	cfg.buses = [
		{"id": AudioEventSeam.BUS_MASTER, "parent_id": &"", "volume_db": DEFAULT_MASTER_DB, "muted": false},
		{"id": AudioEventSeam.BUS_SFX, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_SFX_DB, "muted": false},
		{"id": AudioEventSeam.BUS_MUSIC, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_MUSIC_DB, "muted": false},
		{"id": AudioEventSeam.BUS_VOICE, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_VOICE_DB, "muted": false},
		{"id": AudioEventSeam.BUS_UI, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_UI_DB, "muted": false},
		{"id": AudioEventSeam.BUS_AMBIENT, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_AMBIENT_DB, "muted": false},
		{"id": AudioEventSeam.BUS_META, "parent_id": AudioEventSeam.BUS_MASTER, "volume_db": DEFAULT_META_DB, "muted": false},
	]
	cfg._validated = cfg.validate()
	return cfg

## Validate the bus layout. Returns true if every bus passes schema checks.
## When `emit_errors` is true (default), push_error reports the first
## offending bus. Smokes can pass false when they deliberately exercise a
## rejection path and only care about the boolean contract.
func validate(emit_errors: bool = true) -> bool:
	if buses == null:
		return _validation_fail("AudioBusConfig: buses is null", emit_errors)
	if typeof(buses) != TYPE_ARRAY:
		return _validation_fail("AudioBusConfig: buses must be an Array, got type %d" % typeof(buses), emit_errors)
	if buses.is_empty():
		return _validation_fail("AudioBusConfig: buses is empty (expected 7 entries)", emit_errors)
	var seen_ids: Dictionary = {}
	var master_seen: bool = false
	for i in range(buses.size()):
		var bus: Variant = buses[i]
		if typeof(bus) != TYPE_DICTIONARY:
			return _validation_fail("AudioBusConfig: bus[%d] must be a Dictionary, got type %d" % [i, typeof(bus)], emit_errors)
		var bus_dict: Dictionary = bus
		var id_value: Variant = bus_dict.get("id", null)
		if id_value == null or (typeof(id_value) == TYPE_STRING and (id_value as String).is_empty()) or (typeof(id_value) == TYPE_STRING_NAME and String(id_value).is_empty()):
			return _validation_fail("AudioBusConfig: bus[%d] has empty id" % i, emit_errors)
		var id_str: String = String(id_value)
		if seen_ids.has(id_str):
			return _validation_fail("AudioBusConfig: duplicate bus id '%s'" % id_str, emit_errors)
		seen_ids[id_str] = true
		var parent_value: Variant = bus_dict.get("parent_id", null)
		var parent_str: String = ""
		if parent_value != null:
			parent_str = String(parent_value)
		var volume_db: float = float(bus_dict.get("volume_db", 0.0))
		if is_nan(volume_db) or is_inf(volume_db):
			return _validation_fail("AudioBusConfig: bus[%d] '%s' has non-finite volume_db=%s" % [i, id_str, str(volume_db)], emit_errors)
		if volume_db < MIN_DB or volume_db > MAX_DB:
			return _validation_fail("AudioBusConfig: bus[%d] '%s' volume_db=%s out of range [%s, %s]" % [i, id_str, str(volume_db), str(MIN_DB), str(MAX_DB)], emit_errors)
		# Master must have no parent; every other bus must parent to master.
		if id_str == String(AudioEventSeam.BUS_MASTER):
			master_seen = true
			if not parent_str.is_empty():
				return _validation_fail("AudioBusConfig: master bus must have empty parent_id, got '%s'" % parent_str, emit_errors)
		else:
			if parent_str != String(AudioEventSeam.BUS_MASTER):
				return _validation_fail("AudioBusConfig: bus '%s' must parent to 'master', got '%s'" % [id_str, parent_str], emit_errors)
	if not master_seen:
		return _validation_fail("AudioBusConfig: master bus missing", emit_errors)
	# Every documented bus must be present so the smoke can assert them by id.
	for required_id in AudioEventSeam.ALL_BUS_IDS:
		if not seen_ids.has(String(required_id)):
			return _validation_fail("AudioBusConfig: required bus '%s' missing" % String(required_id), emit_errors)
	_validated = true
	return true

func _validation_fail(reason: String, emit_errors: bool) -> bool:
	if emit_errors:
		push_error(reason)
	_validated = false
	return false

## Look up a bus record by id. Returns null when the bus is not present.
func get_bus(bus_id: StringName) -> Dictionary:
	for bus in buses:
		if typeof(bus) != TYPE_DICTIONARY:
			continue
		var bus_dict: Dictionary = bus
		if String(bus_dict.get("id", "")) == String(bus_id):
			return bus_dict
	return {}

## Look up the volume (dB) for a bus id. Returns 0.0 when the bus is missing
## (so callers can treat it as "no attenuation" without a null check).
func get_volume_db(bus_id: StringName) -> float:
	var bus: Dictionary = get_bus(bus_id)
	if bus.is_empty():
		return 0.0
	return float(bus.get("volume_db", 0.0))

## Set the volume (dB) for a bus id. Returns true on success, false if the
## bus is missing or the volume is out of range. Re-validates after the set
## so a stale `validated` flag cannot survive a corrupted update.
func set_volume_db(bus_id: StringName, volume_db: float) -> bool:
	if volume_db < MIN_DB or volume_db > MAX_DB or is_nan(volume_db) or is_inf(volume_db):
		return false
	for i in range(buses.size()):
		var bus: Variant = buses[i]
		if typeof(bus) != TYPE_DICTIONARY:
			continue
		var bus_dict: Dictionary = bus
		if String(bus_dict.get("id", "")) == String(bus_id):
			bus_dict["volume_db"] = volume_db
			buses[i] = bus_dict
			_validated = false
			validate()
			return true
	return false

## Set the muted flag for a bus id. Returns true on success.
func set_muted(bus_id: StringName, muted: bool) -> bool:
	for i in range(buses.size()):
		var bus: Variant = buses[i]
		if typeof(bus) != TYPE_DICTIONARY:
			continue
		var bus_dict: Dictionary = bus
		if String(bus_dict.get("id", "")) == String(bus_id):
			bus_dict["muted"] = bool(muted)
			buses[i] = bus_dict
			return true
	return false

func is_muted(bus_id: StringName) -> bool:
	var bus: Dictionary = get_bus(bus_id)
	if bus.is_empty():
		return false
	return bool(bus.get("muted", false))

## Summary dictionary for save/load (REQ-AU-010). Pure data shape that
## round-trips through JSON.stringify.
func get_summary() -> Dictionary:
	var volumes: Dictionary = {}
	var mutes: Dictionary = {}
	for bus in buses:
		if typeof(bus) != TYPE_DICTIONARY:
			continue
		var bus_dict: Dictionary = bus
		var id_str: String = String(bus_dict.get("id", ""))
		if id_str.is_empty():
			continue
		volumes[id_str] = float(bus_dict.get("volume_db", 0.0))
		mutes[id_str] = bool(bus_dict.get("muted", false))
	return {
		"kind": "audio_bus_config",
		"volumes": volumes,
		"mutes": mutes,
	}

## Apply a summary (or a partial one) back into this config. Returns true if
## any field changed. Missing keys are preserved (partial apply is supported
## for forward compatibility).
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("kind", "")) != "audio_bus_config":
		return false
	var changed: bool = false
	var volumes: Variant = summary.get("volumes", null)
	if typeof(volumes) == TYPE_DICTIONARY:
		for bus_id in (volumes as Dictionary).keys():
			var new_vol: float = float((volumes as Dictionary)[bus_id])
			if set_volume_db(StringName(String(bus_id)), new_vol):
				changed = true
	var mutes: Variant = summary.get("mutes", null)
	if typeof(mutes) == TYPE_DICTIONARY:
		for bus_id in (mutes as Dictionary).keys():
			var new_muted: bool = bool((mutes as Dictionary)[bus_id])
			if set_muted(StringName(String(bus_id)), new_muted):
				changed = true
	return changed

func is_validated() -> bool:
	return _validated
