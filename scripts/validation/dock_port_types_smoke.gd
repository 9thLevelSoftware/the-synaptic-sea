extends SceneTree

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
	var ok := true
	var msg := ""

	# Lifeboat airlock port from the fixed lifeboat layout.
	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	var lb_port: Dictionary = DockPortsScript.for_lifeboat(lb_layout)
	if lb_port.is_empty() or str(lb_port.get("type", "")) != "airlock" or int(lb_port.get("size_class", -1)) != 1 or str(lb_port.get("condition", "")) != "intact":
		ok = false; msg = "lifeboat port malformed: %s" % str(lb_port)

	# condition_from_seed is deterministic and yields both values across the class range.
	if ok:
		var intact := DockPortsScript.condition_from_seed(123, 0)   # good condition -> intact
		var broken := DockPortsScript.condition_from_seed(123, 3)   # poor condition -> broken
		if intact != "intact" or broken != "broken":
			ok = false; msg = "condition_from_seed wrong: intact=%s broken=%s" % [intact, broken]
		# Determinism: same inputs, same output.
		if ok and DockPortsScript.condition_from_seed(123, 3) != broken:
			ok = false; msg = "condition_from_seed not deterministic"

	# Compatibility matrix.
	if ok:
		var airlock_a := {"type": "airlock", "size_class": 1}
		var airlock_b := {"type": "airlock", "size_class": 1}
		var hangar := {"type": "hangar", "size_class": 1}
		var big_airlock := {"type": "airlock", "size_class": 2}
		if not DockPortsScript.ports_compatible(airlock_a, airlock_b):
			ok = false; msg = "airlock<->airlock should be compatible"
		if ok and DockPortsScript.ports_compatible(airlock_a, hangar):
			ok = false; msg = "airlock<->hangar should be incompatible (type)"
		if ok and DockPortsScript.ports_compatible(airlock_a, big_airlock):
			ok = false; msg = "airlock<->airlock size mismatch should be incompatible"
		if ok and DockPortsScript.ports_compatible({}, airlock_b):
			ok = false; msg = "empty port should be incompatible"

	if ok:
		print("DOCK PORT TYPES PASS compat=true condition_from_seed=true typed=true")
		quit(0)
	else:
		push_error("DOCK PORT TYPES FAIL reason=%s" % msg)
		quit(1)
