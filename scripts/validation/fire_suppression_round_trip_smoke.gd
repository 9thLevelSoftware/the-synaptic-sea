extends SceneTree

## Proves FireSuppressionState.get_summary()/apply_summary() round-trips the FULL
## state — including compartments + adjacency (spread topology) — so a per-ship fire
## model restored from a snapshot still spreads. Refutes the prior lossy apply_summary.
## Marker: FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true

const FireScript := preload("res://scripts/systems/fire_suppression_state.gd")

func _initialize() -> void:
	var src = FireScript.new()
	src.configure({
		"compartments": ["a", "b", "c"],
		"adjacency": {"a": ["b"], "b": ["a", "c"], "c": ["b"]},
		"spread_rate_per_second": 5.0,
		"ignition_rate_per_second": 0.0,
		"power_threshold": 0.5,
	})
	src.ignite("a", 1.0)
	var summary: Dictionary = src.get_summary()

	# Restore into a BARE instance (no configure) — must reproduce topology + fires.
	var dst = FireScript.new()
	dst.apply_summary(summary)
	var topo: bool = dst.get_summary().get("compartments", []).size() == 3 \
		and dst.get_summary().get("adjacency", {}).has("b")
	var fires: bool = dst.is_burning("a") and not dst.is_burning("b")

	# Spread must work on the restored instance: with no oxygen gating in ctx,
	# fire in "a" spreads to neighbour "b" after enough ticks.
	var ctx := {"ship_oxygen_present": true, "powered_ratio": 0.0,
		"breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(20):
		dst.tick(0.1, ctx)
	var spreads: bool = dst.is_burning("b")

	if topo and fires and spreads:
		print("FIRE SUPPRESSION ROUND TRIP PASS topo=true fires=true spreads=true")
		quit(0)
	else:
		push_error("FIRE SUPPRESSION ROUND TRIP FAIL topo=%s fires=%s spreads=%s" % [topo, fires, spreads])
		quit(1)
