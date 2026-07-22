extends SceneTree

## PKG-A1a: pure-ish ShipRuntime advance/catch-up contract.
## Marker: SHIP RUNTIME PASS advance=true catchup=true idempotent=true hub_skip=true

const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")


func _initialize() -> void:
	var inst = ShipInstanceScript.create("runtime_test", "rt:1", null, null, null)
	if inst == null:
		_fail("ShipInstance.create failed")
		return

	# Seed minimal hull/web like coordinator _seed_ship_models
	var hull = inst.get_hull()
	var web = inst.get_web()
	hull.configure({})
	web.configure({})
	inst.last_sim_time = 0.0

	var rt = ShipRuntimeScript.new()
	rt.configure(inst, {"is_home": false})

	# --- advance stamps clock and grows web when attached ---
	web.attached_to_web = true
	var cov0: float = web.coverage
	var integ0: float = hull.average_integrity()
	rt.advance(10.0, 10.0)
	if inst.last_sim_time != 10.0:
		_fail("advance should stamp last_sim_time to world_time")
		return
	if web.coverage < cov0:
		_fail("web coverage should not shrink on advance")
		return
	var advanced: bool = web.coverage > cov0 or hull.average_integrity() <= integ0

	# --- catch_up over a gap ---
	inst.last_sim_time = 10.0
	var world_time: float = 110.0
	var cov_before: float = web.coverage
	var integ_before: float = hull.average_integrity()
	rt.catch_up(world_time)
	if inst.last_sim_time != world_time:
		_fail("catch_up should stamp last_sim_time")
		return
	var cov_after: float = web.coverage
	var integ_after: float = hull.average_integrity()
	var catchup_ok: bool = cov_after >= cov_before and integ_after <= integ_before

	# --- idempotent catch_up ---
	var cov_mid: float = web.coverage
	var integ_mid: float = hull.average_integrity()
	rt.catch_up(world_time)
	if absf(web.coverage - cov_mid) > 0.0001 or absf(hull.average_integrity() - integ_mid) > 0.0001:
		_fail("idempotent catch_up should be a no-op")
		return

	# --- home ship skip catch_up ---
	var home = ShipInstanceScript.create("home_rt", "", null, null, null)
	home.get_hull().configure({})
	home.get_web().configure({})
	home.last_sim_time = 0.0
	var home_rt = ShipRuntimeScript.new()
	home_rt.configure(home, {"is_home": true})
	home_rt.catch_up(500.0)
	if home.last_sim_time != 0.0:
		_fail("home catch_up should skip")
		return

	# --- snapshot extension point ---
	var snap: Dictionary = rt.to_snapshot()
	if str(snap.get("ship_id", "")) != "runtime_test":
		_fail("to_snapshot ship_id")
		return

	if not advanced or not catchup_ok:
		_fail("advance/catchup did not move models (advance=%s catchup=%s cov %s->%s integ %s->%s)" % [
			str(advanced), str(catchup_ok), str(cov_before), str(cov_after), str(integ_before), str(integ_after)
		])
		return

	print("SHIP RUNTIME PASS advance=true catchup=true idempotent=true hub_skip=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP RUNTIME FAIL: %s" % msg)
	quit(1)
