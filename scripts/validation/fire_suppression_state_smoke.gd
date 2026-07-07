extends SceneTree

const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")

## Pure-model smoke for the authoritative compartment fire model (ADR-0041).
## Pass marker:
##   FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true

func _initialize() -> void:
	var cfg := {
		"compartments": ["bridge", "engineering", "hydroponics", "cargo"],
		"suppressant_units": 100.0,
		"suppression_rate_per_second": 25.0,
		"power_threshold": 0.5,
		"adjacency": {
			"bridge": ["engineering"],
			"engineering": ["bridge", "hydroponics", "cargo"],
			"hydroponics": ["engineering"],
			"cargo": ["engineering"],
		},
		"spread_rate_per_second": 0.15,
		"ignition_rate_per_second": 0.2,
		"cascade_rate_per_second": 0.5,
		"arc_compartment": "engineering",
	}

	# ignite + persist (no auto-clear without a cause).
	var m = FireSuppressionStateScript.new()
	m.configure(cfg)
	m.ignite("engineering", 1.0)
	if not m.is_burning("engineering"):
		_fail("ignite did not set engineering burning"); return
	var ctx_idle := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(20):
		m.tick(0.5, ctx_idle)
	if not m.is_burning("engineering"):
		_fail("fire did not persist with no extinguish cause"); return

	# manual extinguish.
	if not m.extinguish("engineering") or m.is_burning("engineering"):
		_fail("extinguish did not clear the fire"); return

	# powered auto-suppression clears over time.
	var sup = FireSuppressionStateScript.new(); sup.configure(cfg)
	sup.ignite("engineering", 1.0)
	var ctx_pow := {"powered_ratio": 1.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(60):
		sup.tick(0.1, ctx_pow)
		if not sup.is_burning("engineering"):
			break
	if sup.is_burning("engineering"):
		_fail("powered auto-suppression never cleared the fire"); return

	# vent: a breached (vacuum) compartment auto-extinguishes.
	var vent = FireSuppressionStateScript.new(); vent.configure(cfg)
	vent.ignite("engineering", 1.0)
	vent.tick(0.1, {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": ["engineering"], "damaged_compartments": [], "arc_arcing": false})
	if vent.is_burning("engineering"):
		_fail("vent (breach) did not extinguish the fire"); return

	# spread: engineering fire spreads to an oxygenated adjacent (bridge); cargo (vented) never ignites.
	var spr = FireSuppressionStateScript.new(); spr.configure(cfg)
	spr.ignite("engineering", 1.0)
	var ctx_spread := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": ["cargo"], "damaged_compartments": [], "arc_arcing": false}
	for i in range(200):
		spr.tick(0.5, ctx_spread)
		if spr.is_burning("bridge"):
			break
	if not spr.is_burning("bridge"):
		_fail("fire never spread to adjacent bridge"); return
	if spr.is_burning("cargo"):
		_fail("fire spread into a vented compartment (cargo) — must not"); return

	# stale spread guard (fix #1): extinguishing a source must clear the spread progress it built toward neighbors.
	var stale = FireSuppressionStateScript.new(); stale.configure(cfg)
	stale.ignite("engineering", 1.0)
	var ctx_stale := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(3):
		stale.tick(0.5, ctx_stale)
	if float(stale.spread_progress.get("bridge", 0.0)) <= 0.0:
		_fail("spread progress toward bridge never accumulated — cannot test stale guard"); return
	if stale.is_burning("bridge"):
		_fail("bridge ignited too early — accumulate partial progress only"); return
	stale.extinguish("engineering")
	if float(stale.spread_progress.get("bridge", 0.0)) != 0.0:
		_fail("stale spread_progress toward bridge survived extinguishing the source"); return

	# re-ignition: damaged + oxygen re-ignites after extinguish; clearing the damage stops it.
	var rei = FireSuppressionStateScript.new(); rei.configure(cfg)
	var ctx_dmg := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": ["engineering"], "arc_arcing": false}
	for i in range(100):
		rei.tick(0.1, ctx_dmg)
		if rei.is_burning("engineering"):
			break
	if not rei.is_burning("engineering"):
		_fail("damaged+oxygen never ignited"); return
	rei.extinguish("engineering")
	var reignited := false
	for i in range(100):
		rei.tick(0.1, ctx_dmg)
		if rei.is_burning("engineering"):
			reignited = true; break
	if not reignited:
		_fail("damaged compartment did not re-ignite after extinguish"); return
	rei.extinguish("engineering")
	var ctx_repaired := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": false}
	for i in range(100):
		rei.tick(0.1, ctx_repaired)
	if rei.is_burning("engineering"):
		_fail("repaired compartment kept re-igniting — repair must stop it"); return

	# arc cascade: arcing ignites the arc compartment.
	var cas = FireSuppressionStateScript.new(); cas.configure(cfg)
	var ctx_arc := {"powered_ratio": 0.0, "ship_oxygen_present": true, "breached_compartments": [], "damaged_compartments": [], "arc_arcing": true}
	for i in range(100):
		cas.tick(0.1, ctx_arc)
		if cas.is_burning("engineering"):
			break
	if not cas.is_burning("engineering"):
		_fail("arc cascade never ignited the arc compartment"); return

	# round-trip.
	var rt = FireSuppressionStateScript.new(); rt.configure(cfg)
	rt.ignite("bridge", 2.0)
	rt.suppressant_units = 42.0
	rt.cascade_progress = 0.3
	var summary := rt.get_summary()
	var rt2 = FireSuppressionStateScript.new(); rt2.configure(cfg)
	if not rt2.apply_summary(summary):
		_fail("apply_summary returned false on a changed summary"); return
	if not rt2.is_burning("bridge") or absf(rt2.suppressant_units - 42.0) > 0.001 or absf(rt2.cascade_progress - 0.3) > 0.001:
		_fail("round-trip did not restore state"); return

	print("FIRE SUPPRESSION STATE PASS ignite=true persist=true extinguish=true auto_suppress=true vent=true spread=true reignite=true cascade=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("FIRE SUPPRESSION STATE FAIL reason=%s" % reason)
	quit(1)
