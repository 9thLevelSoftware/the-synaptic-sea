extends SceneTree

## DockPorts derives a local-space dock port for the lifeboat (airlock) and the
## derelict (dock room), with outward-facing normals on opposite axes.

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	var lb_port: Dictionary = DockPortsScript.for_lifeboat(lb_layout)
	if not lb_port.has("position") or not lb_port.has("facing"):
		ok = false; msg = "lifeboat port missing fields"
	elif (lb_port["facing"] as Vector3).distance_to(Vector3(-1, 0, 0)) > 0.001:
		ok = false; msg = "lifeboat facing not -X"

	# A minimal derelict layout with one dock room at world x=12.
	var der_layout := {
		"rooms": [{
			"id": "dock_01", "room_role": "dock",
			"structural_placements": [
				{"module_id": "floor_1x1", "world_position": [12.0, 0.0, 0.0]},
			],
		}],
	}
	var der_port: Dictionary = DockPortsScript.for_derelict(der_layout)
	if ok and (not der_port.has("position") or not der_port.has("facing")):
		ok = false; msg = "derelict port missing fields"
	elif ok and (der_port["position"] as Vector3).distance_to(Vector3(12, 0, 0)) > 0.001:
		ok = false; msg = "derelict port position not at dock center"
	elif ok and (der_port["facing"] as Vector3).distance_to(Vector3(1, 0, 0)) > 0.001:
		ok = false; msg = "derelict facing not +X"

	if ok and DockPortsScript.for_derelict({"rooms": []}).size() != 0:
		ok = false; msg = "missing dock room should return empty"

	if ok:
		print("DOCK PORTS PASS lifeboat=true derelict=true empty_guard=true")
		quit(0)
	else:
		push_error("DOCK PORTS FAIL reason=%s" % msg)
		quit(1)
