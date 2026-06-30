extends SceneTree

## Domain 2 (BP1): the threat AI consumes DetectionState's emitted profile as the
## single signal source — changing the profile changes every threat's awareness,
## two archetypes with different sensitivities perceive the SAME profile
## differently, and a closer threat perceives more visibility than a far one.
##
## Pass marker:
##   THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

var tm: Node3D
var tm2: Node3D

func _initialize() -> void:
	tm = ThreatManagerScript.new()
	tm._ready()  # loads archetypes (no scene tree needed for the model path)
	# Two archetypes with different sensitivities, one near, one far.
	tm.inject_validation_encounter(["stalker", "biomatter_swarm"], Vector3.ZERO)
	if tm.threats.size() < 2:
		_fail("expected 2 injected threats")
		return
	# Place threat 0 near the player, threat 1 far.
	tm.threats[0].world_position = [1.0, 0.0, 0.0]
	tm.threats[1].world_position = [50.0, 0.0, 0.0]
	# Low emitted signal -> low awareness for both.
	tm.set_player_signals(0.05, 0.1, 0.1, false, "")
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	var low0: float = float(tm.threats[0].awareness_score)
	# Raise the emitted signal -> awareness must rise (single source drives the AI).
	tm.set_player_signals(1.5, 1.5, 1.5, false, "")
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	var hi0: float = float(tm.threats[0].awareness_score)
	var hi1: float = float(tm.threats[1].awareness_score)
	if not (hi0 > low0):
		_fail("raising the emitted profile must raise threat awareness (single source)")
		return
	# Per-archetype: the two threats perceive the same profile differently.
	if absf(hi0 - hi1) < 0.0001:
		_fail("different archetypes should perceive the same profile differently")
		return
	# Proximity: the NEAR threat perceives more visibility-driven awareness than the FAR one
	# (same archetype comparison via two stalkers, near vs far).
	tm2 = ThreatManagerScript.new()
	tm2._ready()
	tm2.inject_validation_encounter(["stalker", "stalker"], Vector3.ZERO)
	tm2.threats[0].world_position = [1.0, 0.0, 0.0]
	tm2.threats[1].world_position = [50.0, 0.0, 0.0]
	tm2.set_player_signals(0.0, 0.0, 1.5, false, "")  # visibility-only signal
	tm2.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if not (float(tm2.threats[0].awareness_score) > float(tm2.threats[1].awareness_score)):
		_fail("near threat should perceive more visibility than far threat")
		return
	print("THREAT DETECTION SOURCE PASS single_source=true per_archetype=true proximity=true")
	_cleanup()
	quit(0)

## Free the bare ThreatManager nodes (and their spawned MeshInstance3D placeholders)
## so headless teardown does not leak renderer RIDs into the regression bundle.
func _cleanup() -> void:
	if tm != null and is_instance_valid(tm):
		tm.free()
		tm = null
	if tm2 != null and is_instance_valid(tm2):
		tm2.free()
		tm2 = null

func _fail(reason: String) -> void:
	push_error("THREAT DETECTION SOURCE FAIL reason=%s" % reason)
	_cleanup()
	quit(1)
