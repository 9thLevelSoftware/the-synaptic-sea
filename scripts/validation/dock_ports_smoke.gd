extends SceneTree

## DockPorts publishes only the exact authored structural endpoint for each
## owner. Room-center fallbacks and the retired west-facing lifeboat descriptor
## must remain unavailable.

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	var lb_port: Dictionary = DockPortsScript.for_lifeboat(lb_layout)
	var lb_endpoint: Dictionary = lb_layout.boarding_endpoints_v1[0]
	if not lb_port.has("position") or not lb_port.has("facing"):
		ok = false; msg = "lifeboat port missing fields"
	elif str(lb_endpoint.get("structural_edge_key", "")) != "0|h|-1|0" \
			or str(lb_endpoint.get("edge_direction", "")) != "north" \
			or str(lb_endpoint.get("room_id", "")) != "airlock_01" \
			or lb_endpoint.get("edge_cell", []) != [0, 0, 0]:
		ok = false; msg = "lifeboat authored airlock edge changed"
	elif str(lb_port.get("endpoint_id", "")) != str(lb_endpoint.get("endpoint_id", "")):
		ok = false; msg = "lifeboat port did not preserve authored endpoint identity"
	elif (lb_port["facing"] as Vector3) != Vector3(0, 0, -1):
		ok = false; msg = "lifeboat does not publish authored north normal"
	elif (lb_port["position"] as Vector3) != _vector3(lb_endpoint.local_position):
		ok = false; msg = "lifeboat does not publish authored outer frame face"

	var der_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/procgen/golden/coherent_ship_001/layout.json"))
	var der_layout: Dictionary = der_variant if der_variant is Dictionary else {}
	var der_documents: Dictionary = ShipGeneratorScript.new()._prepare_layout_documents(der_layout)
	if ok and not bool(der_documents.get("ok", false)):
		ok = false; msg = "derelict production preparation failed"
	elif ok:
		der_layout = der_documents.get("layout", {}) as Dictionary
	var der_port: Dictionary = DockPortsScript.for_derelict(der_layout)
	if ok and (not der_port.has("position") or not der_port.has("facing")):
		ok = false; msg = "derelict port missing fields"
	elif ok and str(der_port.get("endpoint_id", "")) != "boarding:0|v|0|-1":
		ok = false; msg = "home endpoint identity changed"
	elif ok and (der_port["position"] as Vector3) != Vector3(-2.1, 0, 0):
		ok = false; msg = "home does not publish authored outer frame face"
	elif ok and (der_port["facing"] as Vector3) != Vector3(-1, 0, 0):
		ok = false; msg = "home does not publish authored west normal"

	var retired_room_center := {"rooms": [{
		"id": "dock_01", "room_role": "dock", "structural_placements": [
			{"module_id": "floor_1x1", "world_position": [12.0, 0.0, 0.0]},
		]}]}
	if ok and not DockPortsScript.for_derelict(retired_room_center).is_empty():
		ok = false; msg = "retired room-center descriptor was accepted"

	if ok:
		print("DOCK PORTS PASS lifeboat=true derelict=true empty_guard=true")
		quit(0)
	else:
		push_error("DOCK PORTS FAIL reason=%s" % msg)
		quit(1)

func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
