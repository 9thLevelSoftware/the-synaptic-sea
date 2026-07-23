extends RefCounted
class_name ManifestationPool

## PKG-C3.3: data-driven sanity manifestation pool + narrative force hooks.
## Pure — HallucinationDirector consumes kinds/entries; scene never loads this JSON.

const DEFAULT_PATH: String = "res://data/sanity/manifestation_pool.json"

var schema: String = ""
var version: String = ""
var kinds: Dictionary = {}          # kind_id -> config
var entries: Dictionary = {}        # entry_id -> entry
var room_triggers: Dictionary = {}  # room_id -> Array[entry_id]
var audio_log_triggers: Dictionary = {}  # log_id -> Array[entry_id]
var _loaded_path: String = ""


func load_default() -> bool:
	return load_file(DEFAULT_PATH)


func load_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var root: Dictionary = parsed
	schema = str(root.get("schema", ""))
	version = str(root.get("version", ""))
	var kinds_v: Variant = root.get("kinds", {})
	var entries_v: Variant = root.get("entries", {})
	if typeof(kinds_v) != TYPE_DICTIONARY or typeof(entries_v) != TYPE_DICTIONARY:
		return false
	kinds = (kinds_v as Dictionary).duplicate(true)
	entries = (entries_v as Dictionary).duplicate(true)
	room_triggers.clear()
	audio_log_triggers.clear()
	var hooks: Variant = root.get("narrative_hooks", {})
	if typeof(hooks) == TYPE_DICTIONARY:
		var rt: Variant = (hooks as Dictionary).get("room_triggers", {})
		var at: Variant = (hooks as Dictionary).get("audio_log_triggers", {})
		if typeof(rt) == TYPE_DICTIONARY:
			for k in (rt as Dictionary).keys():
				room_triggers[str(k)] = _as_string_array((rt as Dictionary)[k])
		if typeof(at) == TYPE_DICTIONARY:
			for k2 in (at as Dictionary).keys():
				audio_log_triggers[str(k2)] = _as_string_array((at as Dictionary)[k2])
	_loaded_path = path
	return not kinds.is_empty()


func _as_string_array(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for item in v:
		var s: String = str(item)
		if not s.is_empty():
			out.append(s)
	return out


func has_kind(kind_id: String) -> bool:
	return kinds.has(kind_id)


func get_kind(kind_id: String) -> Dictionary:
	if not kinds.has(kind_id):
		return {}
	return (kinds[kind_id] as Dictionary).duplicate(true)


func kind_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in kinds.keys():
		out.append(str(k))
	out.sort()
	return out


func has_entry(entry_id: String) -> bool:
	return entries.has(entry_id)


func get_entry(entry_id: String) -> Dictionary:
	if not entries.has(entry_id):
		return {}
	return (entries[entry_id] as Dictionary).duplicate(true)


func entry_count() -> int:
	return entries.size()


func kind_count() -> int:
	return kinds.size()


## Weighted entry pick for a kind at tier (excludes force_only entries).
func pick_entry_id(kind_id: String, tier: int, seed_hash: int) -> String:
	var candidates: Array = []
	var total_w: int = 0
	for eid in entries.keys():
		var e: Dictionary = entries[eid]
		if str(e.get("kind", "")) != kind_id:
			continue
		if bool(e.get("force_only", false)):
			continue
		if int(e.get("min_tier", 0)) > tier:
			continue
		var w: int = maxi(0, int(e.get("weight", 1)))
		if w <= 0:
			continue
		candidates.append({"id": str(eid), "w": w})
		total_w += w
	if candidates.is_empty() or total_w <= 0:
		return ""
	var roll: int = absi(seed_hash) % total_w
	var cum: int = 0
	for c in candidates:
		cum += int(c["w"])
		if roll < cum:
			return str(c["id"])
	return str(candidates[candidates.size() - 1]["id"])


## Narrative: room enter force list (entry ids that exist).
func force_entries_for_room(room_id: String) -> Array:
	if room_id.is_empty() or not room_triggers.has(room_id):
		return []
	return _filter_existing(room_triggers[room_id])


## Narrative: audio log force list.
func force_entries_for_audio_log(log_id: String) -> Array:
	if log_id.is_empty() or not audio_log_triggers.has(log_id):
		return []
	return _filter_existing(audio_log_triggers[log_id])


func _filter_existing(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var s: String = str(id)
		if entries.has(s):
			out.append(s)
	return out


## Kind config usable by HallucinationDirector (mirrors legacy KIND_CONFIG shape).
func kind_schedule_config() -> Dictionary:
	var out: Dictionary = {}
	for kid in kinds.keys():
		var k: Dictionary = kinds[kid]
		out[str(kid)] = {
			"min_tier": int(k.get("min_tier", 1)),
			"interval": float(k.get("interval", 6.0)),
			"interval_t3": float(k.get("interval_t3", k.get("interval", 4.0))),
			"max": int(k.get("max", 1)),
			"max_t3": int(k.get("max_t3", k.get("max", 1))),
			"ttl": float(k.get("ttl", 3.0)),
		}
	return out
