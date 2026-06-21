extends SceneTree

const DEFINITIONS_PATH := "res://data/ship_systems/systems.json"

const EXPECTED := {
	"power": [],
	"life_support": ["power"],
	"gravity": ["power"],
	"navigation": ["power"],
	"propulsion": ["power", "navigation"],
	"scanners": ["power", "navigation"],
}

const EXPECTED_SUBCOMPONENTS := {
	"power": ["reactor_core", "power_distribution", "battery_cells"],
	"life_support": ["air_recycler", "co2_scrubber", "oxygen_tanks"],
	"gravity": ["gravity_plating", "field_emitter", "inertial_dampeners"],
	"navigation": ["star_charts", "nav_computer", "sensor_array"],
	"propulsion": ["thruster_array", "fuel_injection", "nav_linkage"],
	"scanners": ["scanner_dish", "signal_processor", "power_coupling"],
}

func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(DEFINITIONS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL not a JSON object")
		quit(1)
		return
	var systems_variant: Variant = (parsed as Dictionary).get("systems", null)
	if typeof(systems_variant) != TYPE_ARRAY:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL missing systems array")
		quit(1)
		return
	var systems: Array = systems_variant
	if systems.size() != 6:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL expected 6 systems, got %d" % systems.size())
		quit(1)
		return

	var seen_ids: Array[String] = []
	for sys_variant in systems:
		if typeof(sys_variant) != TYPE_DICTIONARY:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL system is not an object")
			quit(1)
			return
		var sys: Dictionary = sys_variant
		var sid: String = str(sys.get("system_id", ""))
		if not EXPECTED.has(sid):
			push_error("SHIP SYSTEMS DEFINITIONS FAIL unexpected system_id '%s'" % sid)
			quit(1)
			return
		seen_ids.append(sid)
		# Dependencies match the expected graph.
		var deps: Array = sys.get("dependency_ids", [])
		var dep_strs: Array[String] = []
		for d in deps:
			dep_strs.append(str(d))
		if dep_strs != EXPECTED[sid]:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL %s deps=%s expected=%s" % [sid, str(dep_strs), str(EXPECTED[sid])])
			quit(1)
			return
		# Exactly 3 subcomponents, each with the required keys.
		var subs: Array = sys.get("subcomponents", [])
		if subs.size() != 3:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL %s expected 3 subcomponents, got %d" % [sid, subs.size()])
			quit(1)
			return
		for sub_variant in subs:
			if typeof(sub_variant) != TYPE_DICTIONARY:
				push_error("SHIP SYSTEMS DEFINITIONS FAIL %s subcomponent not an object" % sid)
				quit(1)
				return
			var sub: Dictionary = sub_variant
			for key in ["subcomponent_id", "required_parts", "required_tools", "min_skill", "repair_seconds", "operational_threshold"]:
				if not sub.has(key):
					push_error("SHIP SYSTEMS DEFINITIONS FAIL %s subcomponent missing key '%s'" % [sid, key])
					quit(1)
					return
			# Verify subcomponent_id matches the expected set for this system
			var sub_id: String = str(sub.get("subcomponent_id", ""))
			var expected_subs: Array = EXPECTED_SUBCOMPONENTS[sid]
			if sub_id not in expected_subs:
				push_error("SHIP SYSTEMS DEFINITIONS FAIL %s unexpected subcomponent_id '%s'" % [sid, sub_id])
				quit(1)
				return
		# Check that all expected subcomponent IDs are present for this system
		var found_sub_ids: Array[String] = []
		for sub_variant in subs:
			var sub: Dictionary = sub_variant
			found_sub_ids.append(str(sub.get("subcomponent_id", "")))
		var expected_subs: Array = EXPECTED_SUBCOMPONENTS[sid]
		for exp_id in expected_subs:
			if exp_id not in found_sub_ids:
				push_error("SHIP SYSTEMS DEFINITIONS FAIL %s missing expected subcomponent '%s'" % [sid, exp_id])
				quit(1)
				return

	for expected_id in EXPECTED.keys():
		if expected_id not in seen_ids:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL missing system '%s'" % expected_id)
			quit(1)
			return

	print("SHIP SYSTEMS DEFINITIONS PASS systems=6 subcomponents=18 deps=ok")
	quit(0)
