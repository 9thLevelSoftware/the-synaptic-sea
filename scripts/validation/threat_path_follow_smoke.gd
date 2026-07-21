extends SceneTree

## ADR-0049: ThreatManager advances along nav path instead of wall-lerp.
## Marker: THREAT PATH FOLLOW PASS advanced=true no_tunnel=true graph=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")

func _initialize() -> void:
	var layout := {
		"cell_size": 4.0,
		"deck_height": 4.0,
		"rooms": [
			{"id": "start", "structural_placements": [
				{"module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
				{"module": "floor_1x1", "world_position": [4.0, 0.0, 0.0]},
				{"module": "floor_1x1", "world_position": [8.0, 0.0, 0.0]},
			]},
		],
	}
	var mgr = ThreatManagerScript.new()
	# Skip full _ready json load issues by manual setup.
	mgr.threat_archetypes = {
		"biomatter_swarm": {
			"display_name": "Swarm", "max_health": 20.0, "attack_damage": 1.0,
			"move_speed": 4.0, "hunt_speed_mult": 1.0, "attack_range": 0.5,
		},
	}
	mgr.configure_nav_graph(layout)
	if mgr.nav_graph == null or mgr.nav_graph.node_count() < 3:
		_fail("nav graph not built")
		return
	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "t1",
		"archetype_id": "biomatter_swarm",
		"display_name": "Swarm",
		"max_health": 20.0,
		"health": 20.0,
		"world_position": [0.0, 0.0, 0.0],
		"room_id": "start",
		"state": "hunt",
		"move_speed": 4.0,
		"hunt_speed_mult": 1.0,
		"attack_range": 0.5,
	})
	mgr.threats.append(threat)
	var player := Vector3(8.0, 0.0, 0.0)
	var start_x: float = float(threat.world_position[0])
	for i in range(30):
		mgr._advance_threat_motion(threat, 0.1, player)
	var end_x: float = float(threat.world_position[0])
	if end_x <= start_x + 0.5:
		_fail("threat did not advance toward player along path (x=%.2f)" % end_x)
		return
	# Stay near corridor z=0 (no tunneling to arbitrary z).
	if absf(float(threat.world_position[2])) > 0.5:
		_fail("threat left corridor plane z=%.2f" % float(threat.world_position[2]))
		return
	print("THREAT PATH FOLLOW PASS advanced=true no_tunnel=true graph=true")
	mgr.free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("THREAT PATH FOLLOW FAIL reason=%s" % reason)
	quit(1)
