extends SceneTree

const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")

func _initialize() -> void:
	var pipeline = DamagePipelineScript.new()
	pipeline.configure({})
	var vitals = VitalsStateScript.new()
	vitals.configure({"health": 80.0})
	var statuses = StatusEffectsStateScript.new()
	var hit := pipeline.apply_to_vitals(vitals, statuses, {
		"resistance": {"physical": 0.25},
		"durability": 20.0,
		"max_durability": 20.0,
	}, {
		"damage_type": "physical",
		"amount": 20.0,
		"noise": 0.4,
		"status_effect_id": "bleed",
		"source_id": "test_bite",
	})
	if absf(vitals.health - 65.0) > 0.01:
		_fail("expected health 65.0 got %.2f" % vitals.health)
		return
	if not statuses.has_effect("bleed"):
		_fail("bleed status effect missing")
		return
	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "target_01",
		"archetype_id": "stalker",
		"health": 24.0,
		"max_health": 24.0,
		"armor_profile": {"resistance": {"physical": 0.5}},
	})
	var threat_hit := pipeline.apply_to_threat(threat, {
		"damage_type": "physical",
		"amount": 10.0,
		"noise": 0.2,
		"stun_seconds": 1.5,
		"source_id": "crowbar",
	})
	if absf(threat.health - 19.0) > 0.01:
		_fail("expected threat health 19.0 got %.2f" % threat.health)
		return
	if threat.state != ThreatAIStateScript.STATE_STUN:
		_fail("expected threat stun state got %s" % threat.state)
		return
	if int(pipeline.get_summary().get("processed_hits", 0)) != 2:
		_fail("processed_hits mismatch")
		return
	print("DAMAGE PIPELINE PASS vitals=%.1f threat=%.1f absorbed=%.1f status=%s" % [
		vitals.health,
		threat.health,
		float(hit.get("absorbed", 0.0)) + float(threat_hit.get("absorbed", 0.0)),
		str(statuses.has_effect("bleed")).to_lower(),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("DAMAGE PIPELINE FAIL reason=%s" % reason)
	quit(1)
