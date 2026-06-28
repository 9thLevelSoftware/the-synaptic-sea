extends SceneTree

## Proves per-ship fire round-trips through ShipInstance.get_summary()/apply_summary(),
## so a revisited derelict remembers its burning set. Also proves "fire" is omitted when
## no compartment burns (no snapshot bloat).
## Marker: SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	# No fire -> "fire" key omitted.
	var a = ShipInstanceScript.create("s1", "m1", null, null, null)
	var omitted: bool = not a.get_summary().has("fire")

	# Burning -> persists and restores.
	var b = ShipInstanceScript.create("s2", "m2", null, null, null)
	b.get_fire().configure({"compartments": ["x", "y"], "adjacency": {"x": ["y"]}})
	b.get_fire().ignite("x", 1.0)
	var summary: Dictionary = b.get_summary()
	var has_fire: bool = summary.has("fire")

	var c = ShipInstanceScript.create("s2", "m2", null, null, null)
	c.apply_summary(summary)
	var restored: bool = has_fire and c.fire != null and c.fire.is_burning("x")

	if omitted and restored:
		print("SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true")
		quit(0)
	else:
		push_error("SHIP INSTANCE FIRE PERSISTENCE FAIL omitted=%s has_fire=%s restored=%s" % [omitted, has_fire, restored])
		quit(1)
