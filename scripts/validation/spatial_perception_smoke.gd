extends SceneTree

## PKG-C4.1a: pure room-graph perception — closed hatch muffles noise; LOS needs open path.
## Marker: SPATIAL PERCEPTION PASS los=true muffle=true blocked=true open=true round_trip=true

const SpatialPerceptionStateScript := preload("res://scripts/systems/spatial_perception_state.gd")


func _initialize() -> void:
	var layout: Dictionary = {
		"rooms": [
			{"id": "airlock"},
			{"id": "corridor"},
			{"id": "bridge"},
			{"id": "reactor"},
		],
		"room_links": [
			{
				"id": "air_to_cor",
				"from_room": "airlock",
				"to_room": "corridor",
				"module_id": "doorway_frame_open_1x1",
			},
			{
				"id": "cor_to_br",
				"from_room": "corridor",
				"to_room": "bridge",
				"module_id": "doorway_frame_open_1x1",
			},
		],
		"blocked_links": [
			{
				"id": "cor_to_reac",
				"from_room": "corridor",
				"to_room": "reactor",
				"module_id": "doorway_frame_blocked_1x1",
			},
		],
	}

	var perc = SpatialPerceptionStateScript.new()
	var n: int = perc.configure_from_layout(layout)
	if n < 3:
		_fail("expected >=3 links, got %d" % n); return
	if not perc.has_room("bridge"):
		_fail("missing bridge room"); return

	# Same room always visible / full noise
	if not perc.can_see("corridor", "corridor"):
		_fail("same room sight"); return
	if absf(perc.attenuate_noise("bridge", "bridge", 1.0) - 1.0) > 0.001:
		_fail("same room noise"); return

	# Open path airlock -> bridge LOS
	if not perc.can_see("airlock", "bridge"):
		_fail("open path should allow LOS"); return

	# Close the corridor-bridge hatch — LOS breaks
	if not perc.set_door_state("corridor", "bridge", "closed"):
		_fail("set closed"); return
	if perc.can_see("airlock", "bridge"):
		_fail("closed hatch should break LOS to bridge"); return
	if perc.can_see("corridor", "bridge"):
		_fail("adjacent closed hatch should break LOS"); return

	# Noise still leaks through closed hatch but muffled
	var open_noise: float = 1.0
	# reopen for baseline open attenuation over 1 hop
	perc.set_door_state("corridor", "bridge", "open")
	var noise_open: float = perc.attenuate_noise("bridge", "corridor", open_noise)
	perc.set_door_state("corridor", "bridge", "closed")
	var noise_closed: float = perc.attenuate_noise("bridge", "corridor", open_noise)
	if noise_closed >= noise_open:
		_fail("closed should muffle more than open (%s vs %s)" % [str(noise_closed), str(noise_open)]); return
	if noise_closed > 0.25:
		_fail("closed hatch should heavily muffle, got %s" % str(noise_closed)); return
	if noise_closed <= 0.0:
		_fail("some noise should leak through closed hatch"); return

	# Blocked reactor link never allows sight; noise almost gone
	if perc.can_see("corridor", "reactor"):
		_fail("blocked link should not allow sight"); return
	var noise_blocked: float = perc.attenuate_noise("reactor", "corridor", 1.0)
	if noise_blocked > 0.1:
		_fail("blocked should nearly silence, got %s" % str(noise_blocked)); return

	# Reopen hatch restores LOS
	perc.set_door_state("corridor", "bridge", "open")
	if not perc.can_see("airlock", "bridge"):
		_fail("reopen should restore LOS"); return

	# Probe helper
	var probe: Dictionary = perc.probe("bridge", "airlock", 0.9, 1.0)
	if not bool(probe.get("seen", false)):
		_fail("probe seen"); return
	if float(probe.get("noise_at_observer", 0.0)) <= 0.0:
		_fail("probe noise"); return

	# Cannot open blocked without unblock
	if perc.set_door_state("corridor", "reactor", "open"):
		_fail("blocked must not open via set_door_state"); return
	if not perc.unblock_link("corridor", "reactor"):
		_fail("unblock"); return
	if not perc.can_see("corridor", "reactor"):
		_fail("unblocked should allow sight"); return

	# Round-trip
	var snap: Dictionary = perc.get_summary()
	var p2 = SpatialPerceptionStateScript.new()
	if not p2.apply_summary(snap):
		_fail("apply_summary"); return
	if p2.link_count() != perc.link_count():
		_fail("round-trip links"); return
	if p2.can_see("airlock", "bridge") != perc.can_see("airlock", "bridge"):
		_fail("round-trip sight"); return

	# Golden layout smoke (optional file)
	var golden_path: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
	if FileAccess.file_exists(golden_path):
		var f := FileAccess.open(golden_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var g = SpatialPerceptionStateScript.new()
			var gn: int = g.configure_from_layout(parsed)
			if gn < 1:
				_fail("golden layout should yield links"); return

	print("SPATIAL PERCEPTION PASS los=true muffle=true blocked=true open=true round_trip=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SPATIAL PERCEPTION FAIL: %s" % msg)
	quit(1)
