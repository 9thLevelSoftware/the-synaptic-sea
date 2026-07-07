extends RefCounted
class_name HallucinationDirector

## Deterministic, pure-data scheduler for sanity-driven hallucinations (ADR-0042).
## Maps sanity to a tier (0..3) and schedules discrete manifestation events
## (ambient/hud/phantom) with NO RNG — selection is a seeded integer hash so the
## same (seed, step, inputs) always yields the same stream. Screen FX is continuous
## (get_fx_intensity), not a scheduled event. The owning HallucinationManager renders
## active events; the coordinator applies get_direct_teeth() into the vitals tick.

const TIER_UNEASE: float = 40.0      # sanity < 40 -> tier 1
const TIER_DISTORTION: float = 25.0  # sanity < 25 -> tier 2
const TIER_BREAKDOWN: float = 15.0   # sanity < 15 -> tier 3

const DEFAULT_HEALTH_DRAIN: float = 0.5         # tier-3 health drain per second
const DEFAULT_STAMINA_RECOVERY_MULT: float = 0.5 # tier-3 stamina-recovery penalty

# Per-kind scheduling. min_tier gates the kind; interval/max may tighten at tier 3.
const KIND_CONFIG := {
	"ambient": {"min_tier": 1, "interval": 6.0, "interval_t3": 4.0, "max": 2, "max_t3": 2, "ttl": 3.0},
	"hud":     {"min_tier": 2, "interval": 5.0, "interval_t3": 3.0, "max": 3, "max_t3": 3, "ttl": 2.5},
	"phantom": {"min_tier": 2, "interval": 8.0, "interval_t3": 3.5, "max": 1, "max_t3": 3, "ttl": 12.0},
}

var rng_seed: int = 0  # not "seed": avoid shadowing GDScript's global seed() utility
var step: int = 0
var health_drain_per_second: float = DEFAULT_HEALTH_DRAIN
var stamina_recovery_mult: float = DEFAULT_STAMINA_RECOVERY_MULT

var active_events: Array = []   # [{ id, kind, position, ttl }]
var _next_id: int = 1
var _spawn_timers: Dictionary = {}  # kind -> float
var _current_tier: int = 0

func configure(config: Dictionary) -> void:
	rng_seed = int(config.get("seed", 0))
	step = 0
	health_drain_per_second = maxf(0.0, float(config.get("health_drain_per_second", DEFAULT_HEALTH_DRAIN)))
	stamina_recovery_mult = clampf(float(config.get("stamina_recovery_mult", DEFAULT_STAMINA_RECOVERY_MULT)), 0.0, 1.0)
	active_events.clear()
	_spawn_timers.clear()
	_next_id = 1
	_current_tier = 0

func tick(delta: float, context: Dictionary) -> bool:
	if delta <= 0.0:
		return false
	var changed: bool = false
	var sanity: float = float(context.get("sanity", 100.0))
	var in_safe_zone: bool = bool(context.get("in_safe_zone", false))
	var anchors: Array = context.get("anchor_positions", []) if context.get("anchor_positions", []) is Array else []
	_current_tier = _tier_for(sanity)

	# A safe zone is a refuge: force tier 0 so NO manifestations OR teeth/FX apply while
	# recovering in the hub/lifeboat, regardless of sanity (design contract). Tier 0 (sanity
	# >= 40) likewise produces nothing. In both cases clear discrete events and return.
	if in_safe_zone:
		_current_tier = 0
	if _current_tier == 0:
		if not active_events.is_empty():
			active_events.clear()
			changed = true
		_spawn_timers.clear()
		step += 1
		return changed

	# Expire timed-out events.
	for i in range(active_events.size() - 1, -1, -1):
		active_events[i]["ttl"] = float(active_events[i]["ttl"]) - delta
		if float(active_events[i]["ttl"]) <= 0.0:
			active_events.remove_at(i)
			changed = true

	# Schedule discrete events only when anchor positions are available. Direct teeth and
	# FX intensity are tier-driven (get_direct_teeth / get_fx_intensity) and remain active
	# in the field even without anchors — only event PLACEMENT needs anchors.
	if anchors.is_empty():
		step += 1
		return changed

	# Schedule per enabled kind.
	for kind in KIND_CONFIG.keys():
		var cfg: Dictionary = KIND_CONFIG[kind]
		if _current_tier < int(cfg["min_tier"]):
			continue
		var interval: float = float(cfg["interval_t3"]) if _current_tier >= 3 else float(cfg["interval"])
		var cap: int = int(cfg["max_t3"]) if _current_tier >= 3 else int(cfg["max"])
		_spawn_timers[kind] = float(_spawn_timers.get(kind, 0.0)) + delta
		if _spawn_timers[kind] >= interval and _count_kind(kind) < cap:
			_spawn_timers[kind] = float(_spawn_timers[kind]) - interval
			var idx: int = _pick_index(kind, anchors.size())
			active_events.append({
				"id": _next_id,
				"kind": kind,
				"position": anchors[idx],
				"ttl": float(cfg["ttl"]),
			})
			_next_id += 1
			changed = true

	step += 1
	return changed

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

## Remove a single active event by id (called when a phantom is dissipated, so it is not
## immediately re-rendered from active_events on the next frame).
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
	# Session 3 B3: event positions are Vector3, which JSON.stringify turns
	# into an opaque string — a naive duplicate would round-trip to a String
	# and crash HallucinationManager.render's typed `var pos: Vector3`
	# assignment. Serialize positions as [x, y, z] arrays instead.
	var events_out: Array = []
	for e in active_events:
		var copy: Dictionary = (e as Dictionary).duplicate(true)
		var pos: Variant = copy.get("position", null)
		if pos is Vector3:
			copy["position"] = [(pos as Vector3).x, (pos as Vector3).y, (pos as Vector3).z]
		events_out.append(copy)
	return {
		"seed": rng_seed,
		"step": step,
		"health_drain_per_second": health_drain_per_second,
		"stamina_recovery_mult": stamina_recovery_mult,
		"active_events": events_out,
		"current_tier": _current_tier,
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
			# Parse serialized [x, y, z] back into Vector3; tolerate an
			# in-memory Vector3 (pre-serialization apply path).
			var pos: Variant = e.get("position", null)
			if pos is Array and (pos as Array).size() >= 3:
				var pa: Array = pos as Array
				e["position"] = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			elif not (pos is Vector3):
				continue  # unusable event (e.g. a legacy stringified position)
			active_events.append(e)
			max_id = maxi(max_id, int(e.get("id", 0)))
		# _next_id is not persisted: re-derive past the restored ids so a
		# newly-spawned event cannot collide with (and be dissipated as)
		# a restored one via remove_event's first-id match.
		_next_id = max_id + 1
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

# Deterministic index in [0, count) from (seed, step, kind). No RNG.
func _pick_index(kind: String, count: int) -> int:
	if count <= 0:
		return 0
	var h: int = rng_seed * 1103515245 + step * 12345 + hash(kind)
	h = (h ^ (h >> 16)) & 0x7fffffff
	return h % count
