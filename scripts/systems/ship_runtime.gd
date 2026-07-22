extends RefCounted
class_name ShipRuntime

## Per-ship simulation context (pre-polish PKG-A1a strangler).
##
## Owns the advance / catch-up seam formerly inlined on PlayableGeneratedShip.
## The coordinator still owns scene tree, player, UI, and hub-expanded recompute;
## this class is the pure-ish per-ship systems + web/hull tick entry point.
##
## Hub ships may inject coordinator-owned hull/web models via configure() because
## the home ship historically keeps those on the coordinator, not ShipInstance.

const CATCHUP_SUBSTEP_SECONDS: float = 5.0
const MAX_CATCHUP_SECONDS: float = 1800.0

var ship = null
var is_home: bool = false
var hull_override = null
var web_override = null
## Callable() -> bool: contact boost for hub web growth (attached derelict docked).
var contact_boost_provider: Callable = Callable()


func configure(ship_inst, opts: Dictionary = {}) -> void:
	ship = ship_inst
	is_home = bool(opts.get("is_home", false))
	hull_override = opts.get("hull_override", null)
	web_override = opts.get("web_override", null)
	var provider: Variant = opts.get("contact_boost_provider", Callable())
	if provider is Callable:
		contact_boost_provider = provider
	else:
		contact_boost_provider = Callable()


func get_ship():
	return ship


func _resolve_hull():
	if hull_override != null:
		return hull_override
	if ship != null and ship.has_method("get_hull"):
		return ship.get_hull()
	return null


func _resolve_web():
	if web_override != null:
		return web_override
	if ship != null and ship.has_method("get_web"):
		return ship.get_web()
	return null


func _contact_boost() -> bool:
	if not is_home:
		return false
	if contact_boost_provider.is_valid():
		return bool(contact_boost_provider.call())
	return false


## Advance ONE ship's systems manager + biomatter-web hull damage.
## Does NOT tick fire, expanded hub recompute, player, or UI.
func advance(delta: float, world_time: float) -> void:
	if ship == null or delta < 0.0:
		return
	ship.last_sim_time = world_time
	if ship.systems_manager != null and ship.systems_manager.has_method("advance"):
		ship.systems_manager.advance(delta)
	var web = _resolve_web()
	var hull = _resolve_hull()
	if web == null or hull == null:
		return
	var contact: bool = _contact_boost()
	var dmg: float = web.tick(delta, contact)
	if dmg <= 0.0:
		return
	if hull.compartments == null:
		return
	for cid in hull.compartments.keys():
		hull.damage_compartment(str(cid), dmg)


## Fast-forward an absent ship by world_time - last_sim_time in capped sub-steps.
## Home ships are never catch-up targets (always present).
func catch_up(world_time: float) -> void:
	if ship == null or is_home:
		return
	var dt: float = minf(world_time - ship.last_sim_time, MAX_CATCHUP_SECONDS)
	if dt <= 0.0:
		return
	ship.last_sim_time = world_time
	while dt > 0.0:
		var step: float = minf(CATCHUP_SUBSTEP_SECONDS, dt)
		advance(step, world_time)
		dt -= step


## Extension points for later packages (snapshots, integrity map, components).
func to_snapshot() -> Dictionary:
	if ship == null:
		return {}
	var out: Dictionary = {
		"ship_id": str(ship.ship_id) if "ship_id" in ship else "",
		"last_sim_time": float(ship.last_sim_time) if "last_sim_time" in ship else 0.0,
	}
	if ship.has_method("get_summary"):
		out["ship_summary"] = ship.get_summary()
	return out


func from_snapshot(data: Dictionary) -> void:
	if ship == null or data.is_empty():
		return
	if data.has("last_sim_time"):
		ship.last_sim_time = float(data.get("last_sim_time", ship.last_sim_time))
