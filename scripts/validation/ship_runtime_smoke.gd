extends SceneTree

## PKG-A1a: ShipRuntime advance/catch-up contract (REQ-ARCH-003).
## Marker: SHIP RUNTIME PASS advance=true catchup=true idempotent=true hub_skip=true

const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")


func _initialize() -> void:
	var inst = ShipInstanceScript.create("runtime_test", "rt:1", null, null, null)
	if inst == null:
		_fail("ShipInstance.create failed")
		return

	var hull = inst.get_hull()
	var web = inst.get_web()
	# Seed non-empty compartments so web damage can change integrity.
	hull.configure({
		"compartments": [
			{"compartment_id": "bridge", "health": 1.0, "breach_open": false},
			{"compartment_id": "engineering", "health": 1.0, "breach_open": false},
		]
	})
	web.configure({"attached_to_web": true, "seed_coverage": 0.0, "growth_rate": 0.05, "damage_rate": 0.1})
	inst.last_sim_time = 0.0

	var rt = ShipRuntimeScript.new()
	rt.configure(inst, {"is_home": false})

	# --- advance must move web coverage OR hull integrity ---
	var cov0: float = float(web.coverage)
	var integ0: float = float(hull.average_integrity())
	rt.advance(5.0, 5.0)
	if absf(float(inst.last_sim_time) - 5.0) > 0.0001:
		_fail("advance should stamp last_sim_time to world_time")
		return
	var cov1: float = float(web.coverage)
	var integ1: float = float(hull.average_integrity())
	var advanced: bool = (cov1 > cov0 + 0.0001) or (integ1 < integ0 - 0.0001)
	if not advanced:
		_fail("advance must change web coverage or hull integrity (cov %s->%s integ %s->%s)" % [
			str(cov0), str(cov1), str(integ0), str(integ1)
		])
		return

	# --- catch_up over a gap must further change models (leave headroom below caps) ---
	web.coverage = 0.2
	hull.compartments["bridge"] = {"health": 1.0, "breach_open": false, "isolation_rating": 0.5}
	hull.compartments["engineering"] = {"health": 1.0, "breach_open": false, "isolation_rating": 0.5}
	inst.last_sim_time = 5.0
	var world_time: float = 65.0
	var cov_before: float = float(web.coverage)
	var integ_before: float = float(hull.average_integrity())
	rt.catch_up(world_time)
	if absf(float(inst.last_sim_time) - world_time) > 0.0001:
		_fail("catch_up should stamp last_sim_time")
		return
	var cov_after: float = float(web.coverage)
	var integ_after: float = float(hull.average_integrity())
	var catchup_ok: bool = (cov_after > cov_before + 0.0001) or (integ_after < integ_before - 0.0001)
	if not catchup_ok:
		_fail("catch_up must change web or hull (cov %s->%s integ %s->%s)" % [
			str(cov_before), str(cov_after), str(integ_before), str(integ_after)
		])
		return

	# --- idempotent catch_up ---
	var cov_mid: float = float(web.coverage)
	var integ_mid: float = float(hull.average_integrity())
	rt.catch_up(world_time)
	if absf(float(web.coverage) - cov_mid) > 0.0001 or absf(float(hull.average_integrity()) - integ_mid) > 0.0001:
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
	if absf(float(home.last_sim_time) - 0.0) > 0.0001:
		_fail("home catch_up should skip")
		return

	var snap: Dictionary = rt.to_snapshot()
	if str(snap.get("ship_id", "")) != "runtime_test":
		_fail("to_snapshot ship_id")
		return
	if str(snap.get("schema", "")) != "ship_runtime_v1":
		_fail("to_snapshot schema")
		return

	# --- PKG-A1b: snapshot round-trip preserves last_sim_time + ship summary fields ---
	var inst2 = ShipInstanceScript.create("runtime_test", "rt:1", null, null, null)
	inst2.get_hull().configure({
		"compartments": [
			{"compartment_id": "bridge", "health": 1.0, "breach_open": false},
			{"compartment_id": "engineering", "health": 1.0, "breach_open": false},
		]
	})
	inst2.get_web().configure({"attached_to_web": true, "seed_coverage": 0.0})
	var rt2 = ShipRuntimeScript.new()
	rt2.configure(inst2, {"is_home": false})
	rt2.from_snapshot(snap)
	if absf(float(inst2.last_sim_time) - float(snap.get("last_sim_time", -1.0))) > 0.0001:
		_fail("from_snapshot last_sim_time")
		return

	# --- PKG-A1b: second independent runtime advances without coordinator branches ---
	var other = ShipInstanceScript.create("runtime_other", "rt:2", null, null, null)
	other.get_hull().configure({
		"compartments": [{"compartment_id": "cargo", "health": 1.0, "breach_open": false}]
	})
	other.get_web().configure({"attached_to_web": true, "seed_coverage": 0.0, "growth_rate": 0.05})
	other.last_sim_time = 0.0
	var rt_other = ShipRuntimeScript.new()
	rt_other.configure(other, {"is_home": false})
	var o_cov0: float = float(other.get_web().coverage)
	rt_other.advance(8.0, 8.0)
	if float(other.get_web().coverage) <= o_cov0 + 0.0001:
		_fail("second runtime must advance independently")
		return
	# First runtime unchanged by second's advance
	var first_cov: float = float(web.coverage)
	rt_other.advance(5.0, 13.0)
	if absf(float(web.coverage) - first_cov) > 0.0001:
		_fail("second runtime must not mutate first ship's web")
		return

	var bundle: Dictionary = ShipRuntimeScript.compose_runtime_snapshots([rt, rt_other])
	if str(bundle.get("schema", "")) != "ship_runtime_bundle_v1":
		_fail("compose schema")
		return
	var ships: Array = bundle.get("ships", [])
	if ships.size() != 2:
		_fail("compose should include both runtimes")
		return

	print("SHIP RUNTIME PASS advance=true catchup=true idempotent=true hub_skip=true snapshot=true multi=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP RUNTIME FAIL: %s" % msg)
	quit(1)
