extends SceneTree
## Top-down threat smoke: 3 archetypes × 3 movement states = 9 cases.

const TopDownThreatManagerScript = preload("res://scripts/threats/topdown_threat_manager.gd")

var _p := 0
var _f := 0


func _init() -> void:
	var m = TopDownThreatManagerScript.new()
	m._init_systems()

	# --- Spawn ---
	print("\n--- Spawn all archetypes ---")
	var sw = m.spawn_threat("biomatter_swarm", Vector2(100, 100))
	_a(sw != null, "swarm spawned")
	_a(sw.archetype_id == "biomatter_swarm", "swarm archetype ok")
	var sk = m.spawn_threat("stalker", Vector2(200, 200))
	_a(sk != null, "stalker spawned")
	var td = m.spawn_threat("hull_tendril", Vector2(300, 300))
	_a(td != null, "tendril spawned")
	_a(m.get_threat_count() == 3, "3 threats total")

	# --- Idle ---
	print("\n--- Idle state ---")
	var ctx_lo = {"noise_level": 0.0, "light_level": 0.0, "sight_level": 0.0}
	m.tick_threats(0.1, Vector2(500, 500), ctx_lo)
	_a(sw.state == "idle", "swarm idle low-awareness")
	_a(sk.state == "idle", "stalker idle low-awareness")
	_a(td.state == "idle", "tendril idle low-awareness")

	# --- Hunt ---
	print("\n--- Hunt movement ---")
	var m2 = TopDownThreatManagerScript.new()
	m2._init_systems()
	var sw2 = m2.spawn_threat("biomatter_swarm", Vector2(100, 100))
	var sx = float(sw2.world_position[0])
	var ctx_hi = {"noise_level": 1.5, "light_level": 1.0, "sight_level": 1.0}
	for i in range(30):
		m2.tick_threats(0.1, Vector2(300, 100), ctx_hi)
	var ex = float(sw2.world_position[0])
	_a(ex > sx + 5.0, "swarm moved toward player (%.0f -> %.0f)" % [sx, ex])

	# --- Flee ---
	print("\n--- Flee movement ---")
	var m3 = TopDownThreatManagerScript.new()
	m3._init_systems()
	var sw3 = m3.spawn_threat("biomatter_swarm", Vector2(200, 200))
	sw3.apply_damage({"amount": 22.0})
	_a(sw3.state == "flee" or sw3.health < 5.0, "swarm below flee threshold")
	var fx = float(sw3.world_position[0])
	for i in range(30):
		m3.tick_threats(0.1, Vector2(100, 200), ctx_hi)
	var fx2 = float(sw3.world_position[0])
	_a(sw3.state == "flee", "swarm in flee state")
	_a(fx2 > fx, "swarm fled away (%.0f -> %.0f)" % [fx, fx2])

	# --- Damage and death ---
	print("\n--- Damage and death ---")
	var m4 = TopDownThreatManagerScript.new()
	m4._init_systems()
	var td4 = m4.spawn_threat("hull_tendril", Vector2(300, 300))
	_a(td4.health == td4.max_health, "tendril full health")
	var res = m4.apply_damage_to_threat(td4.instance_id, {"amount": 100.0})
	_a(res.size() > 0, "damage result returned")
	_a(td4.state == "dead", "tendril died")
	_a(m4.get_alive_count() == 0, "no threats alive")

	print("\n========================================")
	print("Top-down threat smoke: %d PASS / %d FAIL" % [_p, _f])
	print("========================================")
	print("RESULT: %s" % ("PASS" if _f == 0 else "FAIL"))
	quit(0 if _f == 0 else 1)


func _a(cond: bool, label: String) -> void:
	if cond:
		_p += 1
		print("  PASS  ", label)
	else:
		_f += 1
		print("  FAIL  ", label)
