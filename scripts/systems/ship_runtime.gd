extends RefCounted
class_name ShipRuntime

## Per-ship simulation context (pre-polish PKG-A1a strangler).
##
## Owns the advance / catch-up seam formerly inlined on PlayableGeneratedShip.
## The coordinator still owns scene tree, player, UI, and hub-expanded recompute;
## this class is the per-ship systems + web/hull tick entry point.
##
## Hub ships may inject coordinator-owned hull/web models via configure() because
## the home ship historically keeps those on the coordinator, not ShipInstance.
##
## Types: ShipInstance / HullIntegrityState / WebInfestationState are loaded by
## script path (class_name globals are unreliable under headless --script).

const CATCHUP_SUBSTEP_SECONDS: float = 5.0
const MAX_CATCHUP_SECONDS: float = 1800.0

## PKG-A3 tick bands (accumulators; no balance retune of rates themselves).
const SLOW_INTERVAL_SECONDS: float = 0.35
const LAZY_INTERVAL_SECONDS: float = 3.0

const ShipInstanceScript: GDScript = preload("res://scripts/systems/ship_instance.gd")
const HullIntegrityStateScript: GDScript = preload("res://scripts/systems/hull_integrity_state.gd")
const WebInfestationStateScript: GDScript = preload("res://scripts/systems/web_infestation_state.gd")

## ShipInstance (typed as RefCounted for headless class_name safety).
var ship: RefCounted = null
var is_home: bool = false
## HullIntegrityState override for hub; null → ship.get_hull().
var hull_override: RefCounted = null
## WebInfestationState override for hub; null → ship.get_web().
var web_override: RefCounted = null
## Callable() -> bool: contact boost for hub web growth (attached derelict docked).
var contact_boost_provider: Callable = Callable()
## PKG-B2.1b: optional ModuleIntegrityMap owned by this runtime.
var module_integrity: RefCounted = null

var _slow_acc: float = 0.0
var _lazy_acc: float = 0.0
## Diagnostic counters (smokes / balance tools).
var frame_band_fires: int = 0
var slow_band_fires: int = 0
var lazy_band_fires: int = 0


func configure(ship_inst: RefCounted, opts: Dictionary = {}) -> void:
	ship = ship_inst
	is_home = bool(opts.get("is_home", false))
	var hull_opt: Variant = opts.get("hull_override", null)
	hull_override = hull_opt as RefCounted if hull_opt is RefCounted else null
	var web_opt: Variant = opts.get("web_override", null)
	web_override = web_opt as RefCounted if web_opt is RefCounted else null
	var provider: Variant = opts.get("contact_boost_provider", Callable())
	if provider is Callable:
		contact_boost_provider = provider as Callable
	else:
		contact_boost_provider = Callable()
	var mi: Variant = opts.get("module_integrity", null)
	module_integrity = mi as RefCounted if mi is RefCounted else null
	_slow_acc = 0.0
	_lazy_acc = 0.0
	frame_band_fires = 0
	slow_band_fires = 0
	lazy_band_fires = 0


func get_ship() -> RefCounted:
	return ship


func _resolve_hull() -> RefCounted:
	if hull_override != null:
		return hull_override
	if ship != null and ship.has_method("get_hull"):
		var h: Variant = ship.call("get_hull")
		return h as RefCounted if h is RefCounted else null
	return null


func _resolve_web() -> RefCounted:
	if web_override != null:
		return web_override
	if ship != null and ship.has_method("get_web"):
		var w: Variant = ship.call("get_web")
		return w as RefCounted if w is RefCounted else null
	return null


func _contact_boost() -> bool:
	if not is_home:
		return false
	if contact_boost_provider.is_valid():
		return bool(contact_boost_provider.call())
	return false


## Advance ONE ship's systems manager + biomatter-web hull damage (FRAME band).
## Does NOT tick fire, expanded hub recompute, player, or UI.
func advance(delta: float, world_time: float) -> void:
	if ship == null or delta < 0.0:
		return
	frame_band_fires += 1
	ship.set("last_sim_time", world_time)
	var systems_manager: Variant = ship.get("systems_manager")
	if systems_manager != null and systems_manager is Object and (systems_manager as Object).has_method("advance"):
		(systems_manager as Object).call("advance", delta)
	var web: RefCounted = _resolve_web()
	var hull: RefCounted = _resolve_hull()
	if web == null or hull == null:
		return
	if not web.has_method("tick") or not hull.has_method("damage_compartment"):
		return
	var contact: bool = _contact_boost()
	var dmg: float = float(web.call("tick", delta, contact))
	if dmg <= 0.0:
		return
	var compartments: Variant = hull.get("compartments")
	if typeof(compartments) != TYPE_DICTIONARY:
		return
	for cid in (compartments as Dictionary).keys():
		hull.call("damage_compartment", str(cid), dmg)


## PKG-A3: accumulate delta and report which bands should fire this call.
## Returns { "frame": true, "slow": bool, "lazy": bool, "slow_dt": float, "lazy_dt": float }.
func poll_bands(delta: float) -> Dictionary:
	var result: Dictionary = {
		"frame": true,
		"slow": false,
		"lazy": false,
		"slow_dt": 0.0,
		"lazy_dt": 0.0,
	}
	if delta <= 0.0:
		result["frame"] = false
		return result
	_slow_acc += delta
	_lazy_acc += delta
	if _slow_acc >= SLOW_INTERVAL_SECONDS:
		result["slow"] = true
		result["slow_dt"] = _slow_acc
		_slow_acc = 0.0
		slow_band_fires += 1
	if _lazy_acc >= LAZY_INTERVAL_SECONDS:
		result["lazy"] = true
		result["lazy_dt"] = _lazy_acc
		_lazy_acc = 0.0
		lazy_band_fires += 1
	return result


## Fast-forward an absent ship by world_time - last_sim_time in capped sub-steps.
## Home ships are never catch-up targets (always present).
## PKG-A3: prefer LAZY quanta for inactive catch-up when gap is large; still
## bounded by CATCHUP_SUBSTEP_SECONDS so model rates stay stable.
func catch_up(world_time: float) -> void:
	if ship == null or is_home:
		return
	var last: float = float(ship.get("last_sim_time"))
	var dt: float = minf(world_time - last, MAX_CATCHUP_SECONDS)
	if dt <= 0.0:
		return
	ship.set("last_sim_time", world_time)
	var quantum: float = minf(CATCHUP_SUBSTEP_SECONDS, LAZY_INTERVAL_SECONDS)
	while dt > 0.0:
		var step: float = minf(quantum, dt)
		advance(step, world_time)
		lazy_band_fires += 1
		dt -= step


## PKG-A1b: compose one ship's runtime state for higher-level snapshots.
## RunSnapshot/WorldSnapshot still own top-level schema; this is the per-ship
## composition unit (ship_summary + last_sim_time + empty extension slots).
func to_snapshot() -> Dictionary:
	if ship == null:
		return {}
	var ship_id: String = str(ship.get("ship_id"))
	var last_sim_time: float = float(ship.get("last_sim_time"))
	var out: Dictionary = {
		"schema": "ship_runtime_v1",
		"ship_id": ship_id,
		"last_sim_time": last_sim_time,
		"is_home": is_home,
		"module_integrity": {},
		"component_manifest": {},
	}
	if ship.has_method("get_summary"):
		out["ship_summary"] = ship.call("get_summary")
	if module_integrity != null and module_integrity.has_method("get_summary"):
		out["module_integrity"] = module_integrity.call("get_summary")
	return out


func from_snapshot(data: Dictionary) -> void:
	if ship == null or data.is_empty():
		return
	if data.has("last_sim_time"):
		ship.set("last_sim_time", float(data.get("last_sim_time", ship.get("last_sim_time"))))
	if data.has("ship_summary") and ship.has_method("apply_summary"):
		var summary: Variant = data.get("ship_summary", {})
		if typeof(summary) == TYPE_DICTIONARY and not (summary as Dictionary).is_empty():
			ship.call("apply_summary", summary)
	if data.has("module_integrity") and module_integrity != null and module_integrity.has_method("apply_summary"):
		var mi: Variant = data.get("module_integrity", {})
		if typeof(mi) == TYPE_DICTIONARY:
			module_integrity.call("apply_summary", mi)


## Compose multiple runtimes into one dictionary for multi-ship persistence tests.
static func compose_runtime_snapshots(runtimes: Array) -> Dictionary:
	var ships: Array = []
	for rt_variant in runtimes:
		if rt_variant is RefCounted and (rt_variant as RefCounted).has_method("to_snapshot"):
			ships.append((rt_variant as RefCounted).call("to_snapshot"))
	return {"schema": "ship_runtime_bundle_v1", "ships": ships}