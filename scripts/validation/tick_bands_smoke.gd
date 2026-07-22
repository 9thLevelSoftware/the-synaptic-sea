extends SceneTree

## PKG-A3: ShipRuntime FRAME/SLOW/LAZY band accumulators.
## Marker: TICK BANDS PASS frame=true slow=true lazy=true catchup_lazy=true

const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")


func _initialize() -> void:
	var inst = ShipInstanceScript.create("bands", "b:1", null, null, null)
	inst.get_hull().configure({
		"compartments": [{"compartment_id": "bridge", "health": 1.0}]
	})
	inst.get_web().configure({"attached_to_web": true, "seed_coverage": 0.0})
	var rt = ShipRuntimeScript.new()
	rt.configure(inst, {"is_home": false})

	var slow_hits: int = 0
	var lazy_hits: int = 0
	var frame_hits: int = 0
	# 2.0 seconds at 0.1s frames → 20 frames; slow every 0.35 → ~5; lazy every 3 → 0
	var t: float = 0.0
	while t < 2.0:
		var bands: Dictionary = rt.poll_bands(0.1)
		if bands.get("frame", false):
			frame_hits += 1
		if bands.get("slow", false):
			slow_hits += 1
		if bands.get("lazy", false):
			lazy_hits += 1
		rt.advance(0.1, t + 0.1)
		t += 0.1

	if frame_hits < 15:
		_fail("expected many FRAME fires in 2s, got %d" % frame_hits)
		return
	if slow_hits < 4:
		_fail("expected multiple SLOW fires in 2s, got %d" % slow_hits)
		return
	if lazy_hits != 0:
		_fail("LAZY should not fire within 2s, got %d" % lazy_hits)
		return

	# Continue to 3.5s for one LAZY
	while t < 3.5:
		var b2: Dictionary = rt.poll_bands(0.1)
		if b2.get("lazy", false):
			lazy_hits += 1
		t += 0.1
	if lazy_hits < 1:
		_fail("expected LAZY fire by 3.5s")
		return

	# catch_up uses LAZY-aligned quanta and increments lazy_band_fires
	var lazy_before: int = rt.lazy_band_fires
	inst.last_sim_time = 0.0
	rt.catch_up(30.0)
	if rt.lazy_band_fires <= lazy_before:
		_fail("catch_up should increment lazy_band_fires")
		return

	print("TICK BANDS PASS frame=true slow=true lazy=true catchup_lazy=true slow_hits=%d lazy_hits=%d" % [
		slow_hits, lazy_hits
	])
	quit(0)


func _fail(msg: String) -> void:
	print("TICK BANDS FAIL: %s" % msg)
	quit(1)
