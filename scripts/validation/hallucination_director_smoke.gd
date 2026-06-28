extends SceneTree

## Pure-model proof for HallucinationDirector (sanity hallucinations).
## Marker: HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true

const Director := preload("res://scripts/systems/hallucination_director.gd")

func _initialize() -> void:
	var anchors: Array = [Vector3(1, 0, 0), Vector3(0, 0, 2), Vector3(3, 0, 3)]

	# --- tiers ---
	var d = Director.new(); d.configure({"seed": 7})
	var tiers_ok := d.get_tier() == 0
	d.tick(0.1, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 0
	d.tick(0.1, {"sanity": 35.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 1
	d.tick(0.1, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 2
	d.tick(0.1, {"sanity": 10.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 3

	# --- gating: tier 1 only ambient (no hud/phantom); safe zone => no events ---
	var g = Director.new(); g.configure({"seed": 3})
	for i in range(400):
		g.tick(0.5, {"sanity": 35.0, "in_safe_zone": false, "anchor_positions": anchors})
	var gated_ok := g.get_active_events("hud").is_empty() and g.get_active_events("phantom").is_empty()
	gated_ok = gated_ok and not g.get_active_events("ambient").is_empty()
	# safe zone is a refuge: clears events AND forces tier 0 so teeth/FX do not leak
	# (regression guard for the whole-branch review finding — recovering in the hub at
	# sanity<15 must not keep draining health or show the red FX overlay).
	g.tick(0.5, {"sanity": 10.0, "in_safe_zone": true, "anchor_positions": anchors})
	gated_ok = gated_ok and g.get_active_events().is_empty()
	gated_ok = gated_ok and g.get_tier() == 0
	gated_ok = gated_ok and float(g.get_direct_teeth()["health_drain_per_second"]) == 0.0
	gated_ok = gated_ok and float(g.get_direct_teeth()["stamina_recovery_mult"]) == 1.0
	gated_ok = gated_ok and g.get_fx_intensity() == 0.0
	# but teeth/FX still apply in the FIELD with no anchors (only event PLACEMENT needs anchors)
	var ga = Director.new(); ga.configure({"seed": 3})
	ga.tick(0.5, {"sanity": 10.0, "in_safe_zone": false, "anchor_positions": []})
	gated_ok = gated_ok and ga.get_tier() == 3 and float(ga.get_direct_teeth()["health_drain_per_second"]) > 0.0 and ga.get_fx_intensity() >= 0.99
	# tier 2 enables hud + phantom
	var g2 = Director.new(); g2.configure({"seed": 3})
	for i in range(400):
		g2.tick(0.5, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors})
	gated_ok = gated_ok and not g2.get_active_events("hud").is_empty() and not g2.get_active_events("phantom").is_empty()

	# --- determinism: same seed + identical inputs => identical event stream ---
	var a = Director.new(); a.configure({"seed": 42})
	var b = Director.new(); b.configure({"seed": 42})
	var det_ok := true
	for i in range(200):
		var ctx := {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors}
		a.tick(0.25, ctx); b.tick(0.25, ctx)
		det_ok = det_ok and _events_equal(a.get_active_events(), b.get_active_events())
	# different seed => different stream at some point
	var c = Director.new(); c.configure({"seed": 99})
	var differs := false
	for i in range(200):
		var ctx2 := {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors}
		a.tick(0.25, ctx2); c.tick(0.25, ctx2)
		if not _events_equal(a.get_active_events(), c.get_active_events()):
			differs = true
	det_ok = det_ok and differs

	# --- ttl: events expire after enough time with no new spawns possible ---
	var t = Director.new(); t.configure({"seed": 1})
	t.tick(0.1, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	# force a spawn window then starve by going to tier 0
	for i in range(50):
		t.tick(0.2, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	var had_events := not t.get_active_events().is_empty()
	for i in range(200):
		t.tick(0.5, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors})
	var ttl_ok := had_events and t.get_active_events().is_empty()

	# --- teeth: zero above tier 3, non-zero at tier 3 ---
	var te = Director.new(); te.configure({"seed": 5})
	te.tick(0.1, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors})
	var teeth2 := te.get_direct_teeth()
	te.tick(0.1, {"sanity": 10.0, "in_safe_zone": false, "anchor_positions": anchors})
	var teeth3 := te.get_direct_teeth()
	var teeth_ok := float(teeth2["health_drain_per_second"]) == 0.0 and float(teeth2["stamina_recovery_mult"]) == 1.0
	teeth_ok = teeth_ok and float(teeth3["health_drain_per_second"]) > 0.0 and float(teeth3["stamina_recovery_mult"]) < 1.0

	# --- fx intensity rises with tier ---
	var fx_ok := te.get_fx_intensity() > 0.0
	var fx0 = Director.new(); fx0.configure({"seed": 5})
	fx0.tick(0.1, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors})
	fx_ok = fx_ok and fx0.get_fx_intensity() == 0.0

	# --- round trip ---
	var r = Director.new(); r.configure({"seed": 11})
	for i in range(20):
		r.tick(0.3, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	var summ := r.get_summary()
	var r2 = Director.new(); r2.configure({"seed": 0})
	var rt_ok: bool = r2.apply_summary(summ) and r2.get_summary()["seed"] == summ["seed"] and r2.get_summary()["step"] == summ["step"]

	if tiers_ok and gated_ok and det_ok and ttl_ok and teeth_ok and fx_ok and rt_ok:
		print("HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true")
		quit(0)
	else:
		push_error("HALLUCINATION DIRECTOR FAIL tiers=%s gated=%s det=%s ttl=%s teeth=%s fx=%s rt=%s" % [tiers_ok, gated_ok, det_ok, ttl_ok, teeth_ok, fx_ok, rt_ok])
		quit(1)

func _events_equal(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for i in range(x.size()):
		if str(x[i]) != str(y[i]):
			return false
	return true
