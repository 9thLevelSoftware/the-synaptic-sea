extends SceneTree

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")

func _initialize() -> void:
	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "threat_01",
		"archetype_id": "stalker",
		"display_name": "Stalker",
		"room_id": "bridge",
		"memory_seconds": 4.0,
		"noise_sensitivity": 1.0,
		"light_sensitivity": 0.5,
		"sight_sensitivity": 0.5,
		"attack_interval": 1.2,
	})
	threat.tick(0.1, {
		"noise_level": 1.0,
		"light_level": 0.4,
		"sight_level": 0.4,
		"crouching": false,
		"room_id": "bridge",
		"same_room": true,
		"detect_threshold": 0.85,
	})
	if threat.state != ThreatAIStateScript.STATE_ATTACK:
		_fail("expected attack state got %s" % threat.state)
		return
	if not threat.can_attack():
		_fail("expected threat to be able to attack")
		return
	threat.consume_attack()
	if threat.can_attack():
		_fail("expected cooldown after consume_attack")
		return
	threat.tick(0.6, {
		"noise_level": 0.0,
		"light_level": 0.0,
		"sight_level": 0.0,
		"crouching": true,
		"room_id": "bridge",
		"same_room": false,
		"detect_threshold": 0.85,
	})
	if threat.state != ThreatAIStateScript.STATE_HUNT and threat.state != ThreatAIStateScript.STATE_INVESTIGATE:
		_fail("expected hunt/investigate memory state got %s" % threat.state)
		return
	threat.apply_damage({"final_damage": 50.0})
	if threat.state != ThreatAIStateScript.STATE_DEAD:
		_fail("expected dead state after lethal damage")
		return
	print("THREAT AI STATE PASS final_state=%s previous=%s awareness=%.2f" % [
		threat.state,
		threat.previous_state,
		float(threat.awareness_score),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("THREAT AI STATE FAIL reason=%s" % reason)
	quit(1)
