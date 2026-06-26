extends SceneTree
# REQ-AU-005 / ADR-0029: pure model smoke for SpatialAudioResolver.
#
# Verifies:
# - At ref_distance, attenuation is 0.0 dB.
# - At max_distance, attenuation is max_attenuation_db.
# - In between, attenuation interpolates linearly in dB space.
# - Occlusion adds the configured penalty.
# - Identical inputs produce identical output (determinism).
# - Edge cases: zero distance, identical positions, NaN/Inf vectors.
#
# Pass marker: SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true

func _initialize() -> void:
	var script := load("res://scripts/systems/spatial_audio_resolver.gd")
	if script == null:
		_fail("could not load SpatialAudioResolver script")
		return
	var resolver: RefCounted = script.new()
	resolver.configure({
		"ref_distance": 2.0,
		"max_distance": 22.0,
		"max_attenuation_db": -36.0,
		"occlusion_penalty_db": -6.0,
	})

	# ref_distance: attenuation = 0.
	var ep_ref := Vector3(2.0, 0.0, 0.0)
	var lp_zero := Vector3.ZERO
	var db_at_ref: float = resolver.resolve_volume_db(ep_ref, lp_zero, false, 0.0)
	if absf(db_at_ref - 0.0) > 0.001:
		_fail("attenuation at ref_distance should be 0.0, got %s" % str(db_at_ref))
		return

	# max_distance: attenuation = max_attenuation_db.
	var ep_max := Vector3(22.0, 0.0, 0.0)
	var db_at_max: float = resolver.resolve_volume_db(ep_max, lp_zero, false, 0.0)
	if absf(db_at_max - (-36.0)) > 0.001:
		_fail("attenuation at max_distance should be -36.0, got %s" % str(db_at_max))
		return

	# Mid-point (12 units along X): t = (12 - 2) / (22 - 2) = 0.5
	# attenuation = 0.5 * -36 = -18.
	var ep_mid := Vector3(12.0, 0.0, 0.0)
	var db_mid: float = resolver.resolve_volume_db(ep_mid, lp_zero, false, 0.0)
	if absf(db_mid - (-18.0)) > 0.001:
		_fail("mid-distance attenuation should be -18.0, got %s" % str(db_mid))
		return

	# Occlusion: ep_mid + occluded=true -> -18 - 6 = -24.
	var db_mid_occ: float = resolver.resolve_volume_db(ep_mid, lp_zero, true, 0.0)
	if absf(db_mid_occ - (-24.0)) > 0.001:
		_fail("mid-distance occluded should be -24.0, got %s" % str(db_mid_occ))
		return

	# Determinism: identical inputs -> identical output (5 trials).
	var first: float = resolver.resolve_volume_db(Vector3(7.0, 3.0, -5.0), Vector3(1.0, -2.0, 4.0), true, -3.0)
	for i in range(4):
		var again: float = resolver.resolve_volume_db(Vector3(7.0, 3.0, -5.0), Vector3(1.0, -2.0, 4.0), true, -3.0)
		if absf(again - first) > 0.0001:
			_fail("non-deterministic output on trial %d" % i)
			return

	# Edge case: identical positions -> attenuation=0, base_db preserved.
	var db_same: float = resolver.resolve_volume_db(Vector3(5.0, 5.0, 5.0), Vector3(5.0, 5.0, 5.0), false, -10.0)
	if absf(db_same - (-10.0)) > 0.001:
		_fail("identical positions should preserve base_db (-10), got %s" % str(db_same))
		return

	# Edge case: NaN position clamps to 0 vector (no NaN in output).
	var db_nan: float = resolver.resolve_volume_db(Vector3(NAN, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), false, -3.0)
	if is_nan(db_nan) or is_inf(db_nan):
		_fail("NaN input should not produce NaN/Inf output")
		return

	# Far away + occluded: attenuation cap holds.
	# base_db=0, attenuation caps at -36 (resolver max), occlusion -6 -> -42.
	var db_far: float = resolver.resolve_volume_db(Vector3(1000.0, 0.0, 0.0), Vector3.ZERO, true, 0.0)
	if absf(db_far - (-42.0)) > 0.001:
		_fail("far + occluded should be -42.0 (capped max + occlusion), got %s" % str(db_far))
		return

	# Round-trip summary.
	var summary: Dictionary = resolver.get_summary()
	if str(summary.get("kind", "")) != "spatial_audio_resolver":
		_fail("summary kind missing")
		return
	var other: RefCounted = script.new()
	if not other.apply_summary(summary):
		_fail("apply_summary should report changes")
		return
	if absf(other.ref_distance - 2.0) > 0.001:
		_fail("apply_summary should restore ref_distance")
		return

	print("SPATIAL AUDIO RESOLVER PASS atten_ref=0 atten_max=-36 occluded=-6 determinism=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SPATIAL AUDIO RESOLVER FAIL reason=%s" % reason)
	quit(1)
