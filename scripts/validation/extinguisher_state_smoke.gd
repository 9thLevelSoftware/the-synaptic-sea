extends SceneTree

## Pass marker: EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true

func _initialize() -> void:
	var e := ExtinguisherState.new()
	e.configure({"charge": 100.0, "max_charge": 100.0, "charge_cost_per_use": 34.0, "recharge_per_second": 5.0})
	# consume: 100 -> 66 -> 32 -> blocked (32 < 34).
	if not e.has_charge_for_use() or not e.consume_use():
		_fail("first use should succeed"); return
	if not e.consume_use():
		_fail("second use should succeed"); return
	if e.has_charge_for_use() or e.consume_use():
		_fail("third use should be blocked (insufficient charge)"); return
	if absf(e.charge - 32.0) > 0.001:
		_fail("charge after two uses should be 32.0, got %.3f" % e.charge); return
	# recharge clamps to max.
	e.recharge(100.0)
	if absf(e.charge - 100.0) > 0.001:
		_fail("recharge should clamp to max_charge"); return
	# round-trip.
	e.consume_use()
	var s := e.get_summary()
	var e2 := ExtinguisherState.new()
	e2.configure({"charge": 0.0, "max_charge": 100.0})
	if not e2.apply_summary(s) or absf(e2.charge - e.charge) > 0.001:
		_fail("round-trip failed"); return
	print("EXTINGUISHER STATE PASS consume=true recharge=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("EXTINGUISHER STATE FAIL reason=%s" % reason)
	quit(1)
