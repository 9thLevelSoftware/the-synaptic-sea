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

	host_root.free()
	mobile_root.free()

	if ok:
		print("DOCKING MANAGER PASS aligned=true relationship=true undock=true")
		quit(0)
	else:
		push_error("DOCKING MANAGER FAIL reason=%s" % msg)
		quit(1)
