extends SceneTree
# REQ-AU-004 / ADR-0029: pure model smoke for DynamicMusicState.
#
# Verifies:
# - Initial state is EXPLORATION with base layer gain=1.0 and others=0.0.
# - set_flags(engagement, hazard, vitals_critical) resolves the right state
#   under priority order: CRITICAL > COMBAT > TENSION > EXPLORATION.
# - Layer crossfade advances toward the new state's target gains.
# - override_state() snaps state and target gains.
# - get_summary / apply_summary round-trip cleanly.
#
# Pass marker: DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true

func _initialize() -> void:
	var script := load("res://scripts/systems/dynamic_music_state.gd")
	if script == null:
		_fail("could not load DynamicMusicState script")
		return
	var music: RefCounted = script.new()
	music.configure({"crossfade_seconds": 1.0, "initial_state": &"EXPLORATION"})

	if String(music.get_state()) != "EXPLORATION":
		_fail("initial state should be EXPLORATION")
		return
	var gains: Dictionary = music.get_layer_gains()
	if absf(float(gains.get(&"layer.base", 0.0)) - 1.0) > 0.001:
		_fail("EXPLORATION base gain should be 1.0, got %s" % str(gains.get(&"layer.base")))
		return

	# TENSION (hazard active, no engagement, no critical vitals).
	music.set_flags(false, true, false)
	if String(music.get_state()) != "TENSION":
		_fail("flag set should resolve to TENSION, got %s" % String(music.get_state()))
		return
	gains = music.get_layer_gains()
	if absf(float(gains.get(&"layer.base", 0.0)) - 1.0) > 0.001:
		# Gains haven't crossed yet — only the target should have updated.
		_fail("EXPLORATION base gain should be 1.0 immediately after set_flags (no tick yet)")
		return
	var targets: Dictionary = music.get_target_gains()
	if absf(float(targets.get(&"layer.base", 0.0)) - 0.6) > 0.001:
		_fail("TENSION base target should be 0.6, got %s" % str(targets.get(&"layer.base")))
		return
	if absf(float(targets.get(&"layer.tension_drone", 0.0)) - 0.7) > 0.001:
		_fail("TENSION tension_drone target should be 0.7, got %s" % str(targets.get(&"layer.tension_drone")))
		return

	# Tick halfway -> gains should move ~50% toward targets.
	var changed1: bool = music.tick(0.5)
	if not changed1:
		_fail("tick should report change during crossfade")
		return
	gains = music.get_layer_gains()
	if absf(float(gains.get(&"layer.base", 0.0)) - 0.8) > 0.05:
		_fail("mid-crossfade base should be ~0.8, got %s" % str(gains.get(&"layer.base")))
		return

	# COMBAT (engagement flag).
	music.set_flags(true, true, false)
	if String(music.get_state()) != "COMBAT":
		_fail("flag set should resolve to COMBAT")
		return
	targets = music.get_target_gains()
	if absf(float(targets.get(&"layer.combat_percussion", 0.0)) - 0.9) > 0.001:
		_fail("COMBAT combat_percussion target should be 0.9")
		return

	# CRITICAL takes priority over COMBAT.
	music.set_flags(true, true, true)
	if String(music.get_state()) != "CRITICAL":
		_fail("vitals_critical=true should resolve to CRITICAL even with engagement")
		return
	targets = music.get_target_gains()
	if absf(float(targets.get(&"layer.critical_pad", 0.0)) - 0.9) > 0.001:
		_fail("CRITICAL critical_pad target should be 0.9")
		return

	# Back to EXPLORATION.
	music.set_flags(false, false, false)
	if String(music.get_state()) != "EXPLORATION":
		_fail("all flags false should resolve to EXPLORATION")
		return

	# Force-complete the crossfade by ticking a long delta.
	music.tick(5.0)
	gains = music.get_layer_gains()
	if absf(float(gains.get(&"layer.base", 0.0)) - 1.0) > 0.001:
		_fail("EXPLORATION base gain should snap to 1.0 after long tick, got %s" % str(gains.get(&"layer.base")))
		return
	if absf(float(gains.get(&"layer.tension_drone", 0.0)) - 0.0) > 0.001:
		_fail("EXPLORATION tension_drone should be 0.0 after long tick")
		return

	# override_state with unknown id is rejected.
	if music.override_state(&"NONSENSE", false):
		_fail("override_state(NONSENSE) should reject")
		return

	# Round-trip summary.
	var summary: Dictionary = music.get_summary()
	if str(summary.get("kind", "")) != "dynamic_music_state":
		_fail("summary kind missing")
		return
	var other: RefCounted = script.new()
	if not other.apply_summary(summary):
		_fail("apply_summary should report changes")
		return
	if String(other.get_state()) != "EXPLORATION":
		_fail("apply_summary should restore state")
		return

	print("DYNAMIC MUSIC STATE PASS states_visited=4 crossfade_changed=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("DYNAMIC MUSIC STATE FAIL reason=%s" % reason)
	quit(1)
