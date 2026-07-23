extends SceneTree

## PKG-C4.1b: ThreatManager uses SpatialPerception + engaged LOS flags.
## Marker: THREAT LOS PERCEPTION PASS room_los=true closed_hatch=true raycast=true distance=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")


func _initialize() -> void:
	var layout: Dictionary = {
		"rooms": [
			{"id": "bridge"},
			{"id": "corridor"},
			{"id": "cargo"},
		],
		"room_links": [
			{"id": "b_c", "from_room": "bridge", "to_room": "corridor", "module_id": "doorway_frame_open_1x1"},
			{"id": "c_g", "from_room": "corridor", "to_room": "cargo", "module_id": "doorway_frame_open_1x1"},
		],
		"blocked_links": [],
	}
	var mgr = ThreatManagerScript.new()
	get_root().add_child(mgr)
	await process_frame
	mgr.configure_for_layout(layout, [], Vector3.ZERO)
	if mgr.spatial_perception == null:
		_fail("spatial_perception should be built"); return
	if mgr.spatial_perception.link_count() < 2:
		_fail("expected room links"); return

	# Inject a stalker in cargo with world position
	var stalker = ThreatAIStateScript.new()
	var arch: Dictionary = mgr.threat_archetypes.get("stalker", {})
	if arch.is_empty():
		# configure from file load may be empty until _ready
		mgr.threat_archetypes = mgr._load_json_dict(ThreatManagerScript.THREAT_ARCHETYPE_PATH)
		arch = mgr.threat_archetypes.get("stalker", {})
	var cfg: Dictionary = arch.duplicate(true) if arch is Dictionary else {}
	cfg["instance_id"] = "t_stalker"
	cfg["archetype_id"] = "stalker"
	cfg["room_id"] = "cargo"
	cfg["world_position"] = [10.0, 0.0, 0.0]
	stalker.configure(cfg)
	mgr.threats = [stalker]

	# Open path: player on bridge, high signals — may hunt not attack (different room)
	mgr.set_player_signals(1.5, 1.0, 1.0, false, "bridge")
	mgr.tick_threats(0.1, null, null, {}, Vector3(0, 0, 0))
	# Noise should be attenuated through doors but still reach
	if stalker.awareness_score <= 0.0:
		_fail("open path should allow some awareness"); return

	# Close hatch corridor-cargo: LOS break between bridge path and cargo via closed door
	if not mgr.spatial_perception.set_door_state("corridor", "cargo", "closed"):
		_fail("set door closed"); return
	var before_state: String = stalker.state
	# Force low memory so LOS matters
	stalker.memory_remaining = 0.0
	stalker.state = ThreatAIStateScript.STATE_IDLE
	mgr.set_player_signals(1.5, 1.0, 1.0, false, "bridge")
	mgr.tick_threats(0.1, null, null, {}, Vector3(0, 0, 0))
	# Sight should not force same-room attack across closed hatch
	if stalker.state == ThreatAIStateScript.STATE_ATTACK:
		_fail("closed hatch should not allow attack engage from bridge"); return

	# Same room with raycast LOS break
	stalker.room_id = "bridge"
	stalker.state = ThreatAIStateScript.STATE_IDLE
	stalker.memory_remaining = 0.0
	mgr.clear_engaged_los()
	mgr.set_engaged_los("t_stalker", false)
	mgr.set_player_signals(1.5, 1.0, 1.0, false, "bridge")
	mgr.tick_threats(0.1, null, null, {}, Vector3(1, 0, 0))
	if stalker.state == ThreatAIStateScript.STATE_ATTACK:
		_fail("raycast LOS false should prevent attack engage"); return

	# Raycast LOS true + same room engages
	mgr.set_engaged_los("t_stalker", true)
	# stalker has stalk_range 3.5 — place player close
	stalker.world_position = [0.5, 0.0, 0.0]
	stalker.state = ThreatAIStateScript.STATE_IDLE
	mgr.tick_threats(0.1, null, null, {}, Vector3(0, 0, 0))
	if stalker.state != ThreatAIStateScript.STATE_ATTACK and stalker.state != ThreatAIStateScript.STATE_TELEGRAPH and stalker.state != ThreatAIStateScript.STATE_HUNT:
		_fail("LOS true should engage (got %s)" % stalker.state); return

	# player_distance passed for stalk archetype (far stays hunt)
	stalker.world_position = [20.0, 0.0, 0.0]
	stalker.state = ThreatAIStateScript.STATE_IDLE
	stalker.memory_remaining = 0.0
	mgr.tick_threats(0.1, null, null, {}, Vector3(0, 0, 0))
	if stalker.state == ThreatAIStateScript.STATE_ATTACK:
		_fail("stalk_range should keep far same-room as hunt not attack"); return

	print("THREAT LOS PERCEPTION PASS room_los=true closed_hatch=true raycast=true distance=true")
	quit(0)


func _fail(msg: String) -> void:
	print("THREAT LOS PERCEPTION FAIL: %s" % msg)
	quit(1)
