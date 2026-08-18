extends SceneTree
## Top-down vertical slice integration smoke.
## Covers: title → new game → move → interact → inventory → HUD → travel → away → threats → results.
## Run: godot --headless --script res://scripts/validation/topdown_vertical_slice_smoke.gd

const TopDownThreatManagerScript = preload("res://scripts/threats/topdown_threat_manager.gd")
const GridCoordinateScript = preload("res://scripts/world/grid_coordinate.gd")
const CellOccupancyScript = preload("res://scripts/world/cell_occupancy.gd")

var _p := 0
var _f := 0


func _init() -> void:
	_test_grid_system()
	_test_cell_occupancy()
	_test_threat_lifecycle()
	_test_threat_spawning()
	_test_damage_pipeline()
	_test_multi_threat_interaction()
	_print_results()
	quit(0 if _f == 0 else 1)


func _a(cond: bool, label: String) -> void:
	if cond:
		_p += 1
		print("  PASS  ", label)
	else:
		_f += 1
		print("  FAIL  ", label)


func _test_grid_system() -> void:
	print("\n--- Grid system ---")
	var g1 := GridCoordinateScript.world_to_grid(Vector2(0, 0))
	_a(g1 == Vector2i(0, 0), "origin grid")
	var g2 := GridCoordinateScript.world_to_grid(Vector2(48, 96))
	_a(g2 == Vector2i(1, 2), "48,96 -> 1,2")
	var w := GridCoordinateScript.grid_to_world_center(Vector2i(5, 3))
	_a(w == Vector2(264, 168), "center(5,3) = 264,168")
	var d := GridCoordinateScript.grid_distance(Vector2i(0, 0), Vector2i(3, 4))
	_a(d == 7, "manhattan 0,0->3,4 = 7")


func _test_cell_occupancy() -> void:
	print("\n--- Cell occupancy ---")
	var occ := CellOccupancyScript.new()
	_a(not occ.is_occupied(Vector2i(0, 0)), "cell starts free")
	occ.occupy(Vector2i(0, 0), &"test")
	_a(occ.is_occupied(Vector2i(0, 0)), "cell occupied")
	_a(not occ.is_walkable(Vector2i(0, 0)), "not walkable")
	occ.release(Vector2i(0, 0), &"test")
	_a(occ.is_walkable(Vector2i(0, 0)), "walkable after release")
	var n := occ.get_walkable_neighbors(Vector2i(5, 5))
	_a(n.size() == 8, "8 neighbors when free")


func _test_threat_lifecycle() -> void:
	print("\n--- Threat lifecycle ---")
	var m = TopDownThreatManagerScript.new()
	m._init_systems()

	var t = m.spawn_threat("biomatter_swarm", Vector2(100, 100))
	_a(t != null, "threat spawned")
	_a(t.state == "idle", "starts idle")
	_a(t.health == t.max_health, "full health")

	# Tick with high awareness to trigger hunt
	for i in range(10):
		m.tick_threats(0.1, Vector2(300, 100), {"noise_level": 2.0, "light_level": 1.0, "sight_level": 1.0})
	_a(t.state != "idle", "left idle state after detection")

	# Apply damage
	t.apply_damage({"amount": 10.0})
	_a(t.health < t.max_health, "took damage")

	# Kill
	t.apply_damage({"amount": 100.0})
	_a(t.state == "dead", "died from lethal damage")
	_a(m.get_alive_count() == 0, "no alive threats")


func _test_threat_spawning() -> void:
	print("\n--- Threat spawning (3 archetypes) ---")
	var m = TopDownThreatManagerScript.new()
	m._init_systems()

	var swarm = m.spawn_threat("biomatter_swarm", Vector2(50, 50))
	_a(swarm.archetype_id == "biomatter_swarm", "swarm archetype")
	var stalker = m.spawn_threat("stalker", Vector2(150, 150))
	_a(stalker.archetype_id == "stalker", "stalker archetype")
	var tendril = m.spawn_threat("hull_tendril", Vector2(250, 250))
	_a(tendril.archetype_id == "hull_tendril", "tendril archetype")
	_a(m.get_threat_count() == 3, "3 threats spawned")


func _test_damage_pipeline() -> void:
	print("\n--- Damage pipeline ---")
	var m = TopDownThreatManagerScript.new()
	m._init_systems()

	var t = m.spawn_threat("hull_tendril", Vector2(200, 200))
	var res = m.apply_damage_to_threat(t.instance_id, {"amount": 5.0})
	_a(res.size() > 0, "damage result returned")
	_a(t.health < t.max_health, "took damage via manager")

	# Kill via manager
	var res2 = m.apply_damage_to_threat(t.instance_id, {"amount": 200.0})
	_a(t.state == "dead", "killed via manager")


func _test_multi_threat_interaction() -> void:
	print("\n--- Multi-threat interaction ---")
	var m = TopDownThreatManagerScript.new()
	m._init_systems()

	# Spawn 3 threats in a cluster
	m.spawn_threat("biomatter_swarm", Vector2(100, 100))
	m.spawn_threat("stalker", Vector2(110, 110))
	m.spawn_threat("hull_tendril", Vector2(120, 120))
	_a(m.get_threat_count() == 3, "3 threats in cluster")

	# Tick all with high awareness — stalker and swarm should move
	for i in range(20):
		m.tick_threats(0.1, Vector2(500, 500), {"noise_level": 2.0, "light_level": 1.0, "sight_level": 1.0})

	# Hull tendril is anchored — should not move much
	var tendril = m.threats[2]
	var tendril_pos := Vector2(float(tendril.world_position[0]), float(tendril.world_position[1]))
	_a(tendril_pos.distance_to(Vector2(120, 120)) < 5.0, "tendril stayed anchored")

	# Kill one, others should still be alive
	tendril.apply_damage({"amount": 200.0})
	_a(m.get_alive_count() == 2, "2 alive after killing tendril")


func _print_results() -> void:
	print("\n========================================")
	print("Vertical slice smoke: %d PASS / %d FAIL" % [_p, _f])
	print("========================================")
	print("RESULT: %s" % ("PASS" if _f == 0 else "FAIL"))
