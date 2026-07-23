extends RefCounted
class_name HallucinationDirector

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")
const ManifestationPoolScript := preload("res://scripts/systems/manifestation_pool.gd")

## Deterministic, pure-data scheduler for sanity-driven hallucinations (ADR-0042).
## Maps sanity to a tier (0..3) and schedules discrete manifestation events
## with NO RNG — selection is a seeded integer hash so the same (seed, step, inputs)
## always yields the same stream. PKG-C3.3: kinds/entries load from ManifestationPool
## when available; narrative force_trigger hooks for rooms/audio-logs.

const TIER_UNEASE: float = 40.0      # sanity < 40 -> tier 1
const TIER_DISTORTION: float = 25.0  # sanity < 25 -> tier 2
const TIER_BREAKDOWN: float = 15.0   # sanity < 15 -> tier 3

const DEFAULT_HEALTH_DRAIN: float = 0.5
const DEFAULT_STAMINA_RECOVERY_MULT: float = 0.5

## Fallback kind schedule if pool fails to load (legacy ADR-0042 baseline).
const KIND_CONFIG_FALLBACK := {
	"ambient": {"min_tier": 1, "interval": 6.0, "interval_t3": 4.0, "max": 2, "max_t3": 2, "ttl": 3.0},
	"hud":     {"min_tier": 2, "interval": 5.0, "interval_t3": 3.0, "max": 3, "max_t3": 3, "ttl": 2.5},
	"phantom": {"min_tier": 2, "interval": 8.0, "interval_t3": 3.5, "max": 1, "max_t3": 3, "ttl": 12.0},
}

var rng_seed: int = 0
var step: int = 0
var health_drain_per_second: float = DEFAULT_HEALTH_DRAIN
var stamina_recovery_mult: float = DEFAULT_STAMINA_RECOVERY_MULT

var active_events: Array = []   # [{ id, kind, position, ttl, entry_id, caption, audio_event }]
var _next_id: int = 1
var _spawn_timers: Dictionary = {}  # kind -> float
var _current_tier: int = 0
var pool: RefCounted = null  ## ManifestationPool
var _kind_config: Dictionary = {}


func configure(config: Dictionary = {}) -> void:
	rng_seed = int(config.get("seed", 0))
	step = 0
	health_drain_per_second = maxf(0.0, float(config.get("health_drain_per_second", DEFAULT_HEALTH_DRAIN)))
	stamina_recovery_mult = clampf(float(config.get("stamina_recovery_mult", DEFAULT_STAMINA_RECOVERY_MULT)), 0.0, 1.0)
	active_events.clear()
	_spawn_timers.clear()
	_next_id = 1
	_current_tier = 0
	_load_pool(bool(config.get("load_pool", true)))


func _load_pool(enabled: bool) -> void:
	pool = null
	_kind_config = KIND_CONFIG_FALLBACK.duplicate(true)
	if not enabled:
		return
	var p = ManifestationPoolScript.new()
	if p.load_default():
		pool = p
		_kind_config = p.kind_schedule_config()
		if _kind_config.is_empty():
			_kind_config = KIND_CONFIG_FALLBACK.duplicate(true)


func tick(delta: float, context: Dictionary) -> bool:
	if delta <= 0.0:
		return false
	var changed: bool = false
	var sanity: float = float(context.get(SimKeysScript.SANITY, 100.0))
	var in_safe_zone: bool = bool(context.get(SimKeysScript.IN_SAFE_ZONE, false))
	var anchors: Array = context.get(SimKeysScript.ANCHOR_POSITIONS, []) if context.get(SimKeysScript.ANCHOR_POSITIONS, []) is Array else []
	_current_tier = _tier_for(sanity)

	if in_safe_zone:
		_current_tier = 0
	if _current_tier == 0:
		if not active_events.is_empty():
			active_events.clear()
			changed = true
		_spawn_timers.clear()
		step += 1
		return changed

	for i in range(active_events.size() - 1, -1, -1):
		active_events[i]["ttl"] = float(active_events[i]["ttl"]) - delta
		if float(active_events[i]["ttl"]) <= 0.0:
			active_events.remove_at(i)
			changed = true

	if anchors.is_empty():
		step += 1
		return changed

	for kind in _kind_config.keys():
		var cfg: Dictionary = _kind_config[kind]
		if _current_tier < int(cfg["min_tier"]):
			continue
		var interval: float = float(cfg["interval_t3"]) if _current_tier >= 3 else float(cfg["interval"])
		var cap: int = int(cfg["max_t3"]) if _current_tier >= 3 else int(cfg["max"])
		_spawn_timers[kind] = float(_spawn_timers.get(kind, 0.0)) + delta
		if _spawn_timers[kind] >= interval and _count_kind(str(kind)) < cap:
			_spawn_timers[kind] = float(_spawn_timers[kind]) - interval
			var idx: int = _pick_index(str(kind), anchors.size())
			var entry_id: String = ""
			var caption: String = ""
			var audio_event: String = ""
			if pool != null and pool.has_method("pick_entry_id"):
				var h: int = rng_seed * 1103515245 + step * 12345 + hash(str(kind))
				entry_id = str(pool.call("pick_entry_id", str(kind), _current_tier, h))
				if not entry_id.is_empty() and pool.has_method("get_entry"):
					var ent: Dictionary = pool.call("get_entry", entry_id)
					caption = str(ent.get("caption", ""))
					audio_event = str(ent.get("audio_event", ""))
			active_events.append({
				"id": _next_id,
				"kind": str(kind),
				"position": anchors[idx],
				"ttl": float(cfg["ttl"]),
				"entry_id": entry_id,
				"caption": caption,
				"audio_event": audio_event,
			})
			_next_id += 1
			changed = true

	step += 1
	return changed


## PKG-C3.3: force a catalog entry by id (room/audio-log narrative). Returns event id or -1.
func force_trigger(entry_id: String, position: Variant = null, ttl_override: float = -1.0) -> int:
	if pool == null or entry_id.is_empty():
		return -1
	if not pool.has_method("get_entry") or not bool(pool.call("has_entry", entry_id)):
		return -1
	var ent: Dictionary = pool.call("get_entry", entry_id)
	var kind: String = str(ent.get("kind", ""))
	if kind.is_empty():
		return -1
	var ttl: float = float(ent.get("ttl", -1.0))
	if ttl <= 0.0 and _kind_config.has(kind):
		ttl = float((_kind_config[kind] as Dictionary).get("ttl", 3.0))
	if ttl_override > 0.0:
		ttl = ttl_override
	if ttl <= 0.0:
		ttl = 3.0
	var pos: Variant = position
	if pos == null:
		pos = Vector3.ZERO
	var ev: Dictionary = {
		"id": _next_id,
		"kind": kind,
		"position": pos,
		"ttl": ttl,
		"entry_id": entry_id,
		"caption": str(ent.get("caption", "")),
		"audio_event": str(ent.get("audio_event", "")),
		"forced": true,
	}
	active_events.append(ev)
	_next_id += 1
	return int(ev["id"])


## Force all narrative entries bound to a room id. Returns count spawned.
func force_room_triggers(room_id: String, position: Variant = null) -> int:
	if pool == null or not pool.has_method("force_entries_for_room"):
		return 0
	var ids: Array = pool.call("force_entries_for_room", room_id)
	var n: int = 0
	for eid in ids:
		if force_trigger(str(eid), position) >= 0:
			n += 1
	return n


## Force all narrative entries bound to an audio log id. Returns count spawned.
func force_audio_log_triggers(log_id: String, position: Variant = null) -> int:
	if pool == null or not pool.has_method("force_entries_for_audio_log"):
		return 0
	var ids: Array = pool.call("force_entries_for_audio_log", log_id)
	var n: int = 0
	for eid in ids:
		if force_trigger(str(eid), position) >= 0:
			n += 1
	return n


func get_tier() -> int:
	return _current_tier


func get_active_events(kind: String = "") -> Array:
	if kind.is_empty():
		return active_events.duplicate(true)
	var out: Array = []
	for e in active_events:
		if str(e["kind"]) == kind:
			out.append(e.duplicate(true))
	return out


func remove_event(id: int) -> void:
	for i in range(active_events.size()):
		if int(active_events[i]["id"]) == id:
			active_events.remove_at(i)
			return


func get_direct_teeth() -> Dictionary:
	if _current_tier >= 3:
		return {"health_drain_per_second": health_drain_per_second, "stamina_recovery_mult": stamina_recovery_mult}
	return {"health_drain_per_second": 0.0, "stamina_recovery_mult": 1.0}


func get_fx_intensity() -> float:
	return clampf(float(_current_tier) / 3.0, 0.0, 1.0)


func get_summary() -> Dictionary:
	var events_out: Array = []
	for e in active_events:
		if not (e is Dictionary):
			continue
		var copy: Dictionary = (e as Dictionary).duplicate(true)
		var pos: Variant = copy.get("position", null)
		if pos is Vector3:
			copy["position"] = [(pos as Vector3).x, (pos as Vector3).y, (pos as Vector3).z]
		events_out.append(copy)
	var timers_out: Dictionary = {}
	for kind in _spawn_timers:
		timers_out[str(kind)] = maxf(0.0, float(_spawn_timers[kind]))
	return {
		"seed": rng_seed,
		"step": step,
		"health_drain_per_second": health_drain_per_second,
		"stamina_recovery_mult": stamina_recovery_mult,
		"active_events": events_out,
		"spawn_timers": timers_out,
		"current_tier": _current_tier,
		"pool_loaded": pool != null,
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	rng_seed = int(summary.get("seed", rng_seed))
	step = int(summary.get("step", step))
	health_drain_per_second = maxf(0.0, float(summary.get("health_drain_per_second", health_drain_per_second)))
	stamina_recovery_mult = clampf(float(summary.get("stamina_recovery_mult", stamina_recovery_mult)), 0.0, 1.0)
	if summary.get("active_events", null) is Array:
		active_events.clear()
		var max_id: int = 0
		for raw in summary["active_events"] as Array:
			if not (raw is Dictionary):
				continue
			var e: Dictionary = (raw as Dictionary).duplicate(true)
			var pos: Variant = e.get("position", null)
			if pos is Array and (pos as Array).size() >= 3:
				var pa: Array = pos as Array
				if not ((pa[0] is int or pa[0] is float) and (pa[1] is int or pa[1] is float) and (pa[2] is int or pa[2] is float)):
					continue
				e["position"] = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			elif not (pos is Vector3):
				continue
			active_events.append(e)
			max_id = maxi(max_id, int(e.get("id", 0)))
		_next_id = max_id + 1
	if summary.get("spawn_timers", null) is Dictionary:
		_spawn_timers.clear()
		var timers: Dictionary = summary["spawn_timers"] as Dictionary
		for raw_kind in timers:
			var kind: String = str(raw_kind)
			if not _kind_config.has(kind):
				continue
			var raw_value: Variant = timers[raw_kind]
			if raw_value is int or raw_value is float:
				_spawn_timers[kind] = maxf(0.0, float(raw_value))
	_current_tier = int(summary.get("current_tier", _current_tier))
	return true


func _tier_for(sanity: float) -> int:
	if sanity < TIER_BREAKDOWN:
		return 3
	if sanity < TIER_DISTORTION:
		return 2
	if sanity < TIER_UNEASE:
		return 1
	return 0


func _count_kind(kind: String) -> int:
	var n: int = 0
	for e in active_events:
		if str(e["kind"]) == kind:
			n += 1
	return n


func _pick_index(kind: String, count: int) -> int:
	if count <= 0:
		return 0
	var h: int = rng_seed * 1103515245 + step * 12345 + hash(kind)
	h = (h ^ (h >> 16)) & 0x7fffffff
	return h % count
