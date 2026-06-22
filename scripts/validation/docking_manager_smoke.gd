extends SceneTree

## Pure-model: DockingManager aligns two ship ports (coincident position,
## opposing facing) and writes/clears the dock relationship. No scene tree
## traversal beyond two bare Node3D roots used as transform carriers.

const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Host placed 20 units down +X, its dock port facing +X (outward).
	var host_root := Node3D.new()
	host_root.position = Vector3(20.0, 0.0, 0.0)
	var host = ShipInstanceScript.create("host", "", null, null, host_root)
	var host_port := {"position": Vector3(22.0, 0.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}

	# Mobile (lifeboat) port sits at local +X edge, facing +X in local space.
	var mobile_root := Node3D.new()
	var mobile = ShipInstanceScript.create("mobile", "", null, null, mobile_root)
	var mobile_port := {"position": Vector3(2.0, 0.0, 0.0), "facing": Vector3(1.0, 0.0, 0.0)}

	var res: Dictionary = DockingManagerScript.dock(host, mobile, host_port, mobile_port)
	if not bool(res.get("success", false)):
		ok = false; msg = "dock failed: %s" % str(res.get("reason", ""))

	# Mobile port now in world space must coincide with the host port and face the opposite way.
	var mobile_port_world: Vector3 = mobile_root.transform * (mobile_port["position"] as Vector3)
	var mobile_facing_world: Vector3 = (mobile_root.transform.basis * (mobile_port["facing"] as Vector3)).normalized()
	if ok and mobile_port_world.distance_to(host_port["position"]) > 0.001:
		ok = false; msg = "ports not coincident: %s vs %s" % [str(mobile_port_world), str(host_port["position"])]
	if ok and mobile_facing_world.distance_to(-(host_port["facing"] as Vector3)) > 0.001:
		ok = false; msg = "facings not opposed: %s" % str(mobile_facing_world)
	if ok and mobile.parent_ship != host:
		ok = false; msg = "parent_ship not set"
	if ok and not host.docked_ships.has(mobile):
		ok = false; msg = "mobile not in host.docked_ships"

	# Undock clears the relationship.
	if ok:
		DockingManagerScript.undock(mobile)
		if mobile.parent_ship != null or host.docked_ships.has(mobile) or not mobile.docking_ports.is_empty():
			ok = false; msg = "undock did not clear relationship"

	# Double-undock is idempotent: a second undock on an already-undocked ship
	# must not crash and must report not_docked.
	if ok:
		var res2: Dictionary = DockingManagerScript.undock(mobile)
		if not bool(res2.get("success", false)) or str(res2.get("reason", "")) != "not_docked":
			ok = false; msg = "double-undock not idempotent: %s" % str(res2)

	# Malformed ports are rejected with dock_failed (no state mutation, no crash).
	var rejects := false
	if ok:
		var bad_host := Node3D.new()
		var bad_host_inst = ShipInstanceScript.create("bad_host", "", null, null, bad_host)
		var bad_mobile := Node3D.new()
		var bad_mobile_inst = ShipInstanceScript.create("bad_mobile", "", null, null, bad_mobile)
		var bad_res: Dictionary = DockingManagerScript.dock(bad_host_inst, bad_mobile_inst, {}, mobile_port)
		if bool(bad_res.get("success", true)) or str(bad_res.get("reason", "")) != "dock_failed":
			ok = false; msg = "malformed port not rejected: %s" % str(bad_res)
		else:
			rejects = true
		bad_host.free()
		bad_mobile.free()

	host_root.free()
	mobile_root.free()

	if ok:
		print("DOCKING MANAGER PASS aligned=true relationship=true undock=true rejects=%s" % str(rejects).to_lower())
		quit(0)
	else:
		push_error("DOCKING MANAGER FAIL reason=%s" % msg)
		quit(1)
