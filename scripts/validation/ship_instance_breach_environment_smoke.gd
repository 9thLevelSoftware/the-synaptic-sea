extends SceneTree

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")


func _initialize() -> void:
	var source = ShipInstanceScript.create("ship_a", "marker_a", null, null, null)
	source.breach_environment_summary = {
		"hazard_kind": "oxygen",
		"breach_open": false,
		"breach_sealed": true,
		"passability_blocked": false,
		"breach_zone_ids": ["breach_a"],
	}
	var packed: Dictionary = source.get_summary()
	var restored = ShipInstanceScript.create("", "", null, null, null)
	if not restored.apply_summary(packed) \
			or restored.breach_environment_summary != source.breach_environment_summary:
		push_error("SHIP INSTANCE BREACH ENVIRONMENT FAIL summary=%s" % str(packed))
		quit(1)
		return
	print("SHIP INSTANCE BREACH ENVIRONMENT PASS isolated=true round_trip=true")
	quit(0)
