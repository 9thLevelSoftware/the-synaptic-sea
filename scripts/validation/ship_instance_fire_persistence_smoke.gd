extends SceneTree

## Proves per-ship fire round-trips through ShipInstance.get_summary()/apply_summary(),
## so a revisited derelict remembers its burning set. Also proves "fire" is omitted when
## the ship was never seeded and nothing burns/vents (no snapshot bloat), but a
## fire_seeded vents-only model still persists — otherwise load skips seed and
## drops vented_compartments.
## Marker: SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true seeded_vents=true

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")

func _initialize() -> void:
	# Never seeded, not burning, not vented -> "fire" key omitted.
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

	# Seeded + vented, nothing burning -> still persist and restore vents.
	var d = ShipInstanceScript.create("s3", "m3", null, null, null)
	d.fire_seeded = true
	d.get_fire().configure({"compartments": ["x"], "vented_compartments": ["x"]})
	var vsum: Dictionary = d.get_summary()
	var e = ShipInstanceScript.create("s3", "m3", null, null, null)
	e.apply_summary(vsum)
	var seeded_vents: bool = vsum.has("fire") and e.fire_seeded \
		and e.get_fire().is_vented("x") and e.get_fire().get_burning_compartments().is_empty()

	if omitted and restored and seeded_vents:
		print("SHIP INSTANCE FIRE PERSISTENCE PASS omitted=true restored=true seeded_vents=true")
		quit(0)
	else:
		push_error("SHIP INSTANCE FIRE PERSISTENCE FAIL omitted=%s has_fire=%s restored=%s seeded_vents=%s" % [omitted, has_fire, restored, seeded_vents])
		quit(1)
