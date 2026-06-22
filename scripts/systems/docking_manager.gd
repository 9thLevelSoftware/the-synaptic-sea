extends RefCounted
class_name DockingManager

## Pure docking math + relationship bookkeeping. Aligns a mobile ship's dock
## port to a host ship's dock port (coincident position, opposing facing,
## yaw-only) and writes the parent/child fields already declared on ShipInstance.
## No scene-tree ownership: callers own add_child/remove_child of ship_roots.

## Yaw (radians) that rotates `from` onto `to` in the X-Z plane.
static func _yaw_between(from: Vector3, to: Vector3) -> float:
	var a := atan2(from.x, from.z)
	var b := atan2(to.x, to.z)
	return b - a

static func compute_mobile_transform(host_port: Dictionary, mobile_port: Dictionary) -> Transform3D:
	var host_pos: Vector3 = host_port.get("position", Vector3.ZERO)
	var host_facing: Vector3 = (host_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	var local_pos: Vector3 = mobile_port.get("position", Vector3.ZERO)
	var local_facing: Vector3 = (mobile_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	# Rotate the mobile so its local port facing becomes the OPPOSITE of the host facing.
	var target_facing: Vector3 = -host_facing
	var yaw: float = _yaw_between(local_facing, target_facing)
	var basis := Basis(Vector3.UP, yaw)
	# Translate so the (rotated) local port position lands on the host port position.
	var origin: Vector3 = host_pos - (basis * local_pos)
	return Transform3D(basis, origin)

static func _port_valid(p: Dictionary) -> bool:
	return p.has("position") and p.has("facing") \
		and typeof(p["position"]) == TYPE_VECTOR3 and typeof(p["facing"]) == TYPE_VECTOR3 \
		and (p["facing"] as Vector3).length() > 0.0001

static func dock(host_inst, mobile_inst, host_port: Dictionary, mobile_port: Dictionary) -> Dictionary:
	# Reject null insts and self-docking (a ship docking to itself would create a
	# self-referential parent_ship/docked_ships cycle).
	if host_inst == null or mobile_inst == null or host_inst == mobile_inst:
		return {"success": false, "reason": "dock_failed"}
	if not _port_valid(host_port) or not _port_valid(mobile_port):
		return {"success": false, "reason": "dock_failed"}
	if not ("scene_root" in mobile_inst):
		return {"success": false, "reason": "dock_failed"}
	var root = mobile_inst.scene_root
	if root == null or not is_instance_valid(root) or not (root is Node3D):
		return {"success": false, "reason": "dock_failed"}
	# Sever any existing dock relationship first so the previous host's
	# docked_ships list does not retain a stale reference to this mobile ship.
	if mobile_inst.parent_ship != null:
		undock(mobile_inst)
	(root as Node3D).transform = compute_mobile_transform(host_port, mobile_port)
	mobile_inst.parent_ship = host_inst
	if not host_inst.docked_ships.has(mobile_inst):
		host_inst.docked_ships.append(mobile_inst)
	mobile_inst.docking_ports = [{"host_port": host_port, "mobile_port": mobile_port}]
	return {"success": true, "reason": "ok"}

static func undock(mobile_inst) -> Dictionary:
	if mobile_inst == null:
		return {"success": false, "reason": "dock_failed"}
	var host = mobile_inst.parent_ship
	if host == null:
		return {"success": true, "reason": "not_docked"}
	if host.docked_ships.has(mobile_inst):
		host.docked_ships.erase(mobile_inst)
	mobile_inst.parent_ship = null
	mobile_inst.docking_ports = []
	return {"success": true, "reason": "ok"}
