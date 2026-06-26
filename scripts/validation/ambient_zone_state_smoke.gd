extends SceneTree
# REQ-AU-003 / ADR-0029: pure model smoke for AmbientZoneState.
#
# Verifies:
# - configure(initial_role, initial_threat) snaps to the requested role.
# - set_room_role triggers a crossfade and the crossfade advances over time.
# - Unknown roles are rejected without mutating current state.
# - set_threat_level clamps to [0, 1] and updates the threat gain.
# - get_layer_gains reports the crossfade weights and threat multiplier.
# - get_summary / apply_summary round-trip cleanly.
#
# Pass marker: AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true

func _initialize() -> void:
	var script := load("res://scripts/systems/ambient_zone_state.gd")
	if script == null:
		_fail("could not load AmbientZoneState script")
		return
	var state: RefCounted = script.new()
	state.configure({
		"crossfade_seconds": 1.0,
		"threat_threshold": 0.5,
		"threat_boost": 0.25,
		"initial_role": &"docking",
		"initial_threat": 0.2,
	})
	if String(state.get_current_role()) != "docking":
		_fail("initial role should be docking, got %s" % String(state.get_current_role()))
		return
	if absf(state.get_threat_level() - 0.2) > 0.001:
		_fail("initial threat mismatch")
		return

	# Threat below threshold should NOT multiply gain.
	var gains: Dictionary = state.get_layer_gains()
	if absf(float(gains.get("threat_multiplier", 1.0)) - 1.0) > 0.001:
		_fail("threat below threshold should keep multiplier=1.0")
		return

	# Move to a new role -> crossfade activates.
	state.set_room_role(&"engine", false)
	if not state.is_crossfade_active():
		_fail("crossfade should be active after set_room_role")
		return
	if String(state.get_current_role()) != "engine":
		_fail("current_role should be engine")
		return
	if String(state.get_current_track_id()) != "amb.engine":
		_fail("track id mismatch for engine role, got %s" % String(state.get_current_track_id()))
		return

	# Tick halfway -> crossfade weight t=0.5.
	state.tick(0.5)
	gains = state.get_layer_gains()
	if absf(float(gains.get("current_gain", 0.0)) - 0.5) > 0.05:
		_fail("halfway crossfade current_gain should be ~0.5, got %s" % str(gains.get("current_gain")))
		return
	if absf(float(gains.get("previous_gain", 1.0)) - 0.5) > 0.05:
		_fail("halfway crossfade previous_gain should be ~0.5")
		return

	# Finish the crossfade.
	state.tick(0.6)
	if state.is_crossfade_active():
		_fail("crossfade should be complete after total 1.1s")
		return
	gains = state.get_layer_gains()
	if absf(float(gains.get("current_gain", 0.0)) - 1.0) > 0.001:
		_fail("completed current_gain should be 1.0")
		return
	if absf(float(gains.get("previous_gain", 0.0)) - 0.0) > 0.001:
		_fail("completed previous_gain should be 0.0")
		return

	# Unknown role -> warning, no state change.
	var roles_before: String = String(state.get_current_role())
	state.set_room_role(&"nonexistent_role", false, false)
	if String(state.get_current_role()) != roles_before:
		_fail("unknown role should not mutate current role")
		return

	# Threat above threshold -> multiplier > 1.0.
	state.set_threat_level(1.0)
	gains = state.get_layer_gains()
	if float(gains.get("threat_multiplier", 1.0)) <= 1.0:
		_fail("threat=1.0 should multiply gains > 1.0")
		return

	# set_threat_level clamps to [0, 1].
	state.set_threat_level(5.0)
	if absf(state.get_threat_level() - 1.0) > 0.001:
		_fail("threat should clamp to 1.0")
		return
	state.set_threat_level(-1.0)
	if absf(state.get_threat_level() - 0.0) > 0.001:
		_fail("threat should clamp to 0.0")
		return

	# Restart with force_restart while no fade active.
	state.set_room_role(&"med_bay", true)
	if not state.is_crossfade_active():
		_fail("force_restart should kick off a new crossfade")
		return

	# Round-trip summary.
	var summary: Dictionary = state.get_summary()
	if str(summary.get("kind", "")) != "ambient_zone_state":
		_fail("summary kind missing")
		return
	if str(summary.get("current_role", "")) != "med_bay":
		_fail("summary.current_role should be med_bay, got %s" % str(summary.get("current_role")))
		return
	var other: RefCounted = script.new()
	other.configure({"crossfade_seconds": 1.0})
	if not other.apply_summary(summary):
		_fail("apply_summary should report changes")
		return
	if String(other.get_current_role()) != "med_bay":
		_fail("apply_summary did not restore role")
		return

	print("AMBIENT ZONE STATE PASS roles_changed=2 crossfades_completed=1 threat_applied=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("AMBIENT ZONE STATE FAIL reason=%s" % reason)
	quit(1)
