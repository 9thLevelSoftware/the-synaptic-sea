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

	# condition_from_seed: tier extremes are fixed, middle band is seed-split.
	if ok:
		# Tier extremes: class 0 always intact, class 3 always broken.
		if DockPortsScript.condition_from_seed(123, 0) != "intact":
			ok = false; msg = "condition_from_seed(123, 0) should be intact"
		if ok and DockPortsScript.condition_from_seed(123, 3) != "broken":
			ok = false; msg = "condition_from_seed(123, 3) should be broken"
		# Stability: same (seed, class) -> identical result.
		if ok and DockPortsScript.condition_from_seed(123, 2) != DockPortsScript.condition_from_seed(123, 2):
			ok = false; msg = "condition_from_seed not stable for same (seed, class)"
		# Seed actually splits the middle band: across seeds 1..80 at class 2,
		# both "intact" and "broken" must appear.
		if ok:
			var saw_intact := false
			var saw_broken := false
			for s in range(1, 81):
				var c := DockPortsScript.condition_from_seed(s, 2)
				if c == "intact":
					saw_intact = true
				elif c == "broken":
					saw_broken = true
			if not saw_intact:
				ok = false; msg = "seed never produced an intact outcome at class 2"
			elif not saw_broken:
				ok = false; msg = "seed never produced a broken outcome at class 2"

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
