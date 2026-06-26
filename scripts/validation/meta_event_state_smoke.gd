extends SceneTree
# REQ-AU-007 / ADR-0029: pure model smoke for MetaEventState.
#
# Verifies:
# - Default schedule fires three events in trigger_time order.
# - tick() returns the due events and removes them from pending.
# - Fired events are recorded and never re-fire.
# - Custom schedule via configure(events=[...]) is honored.
# - Seed-derived offset is deterministic (same seed -> same offset).
# - schedule_event() inserts at the right position.
# - get_summary / apply_summary round-trip cleanly.
#
# Pass marker: META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true

func _initialize() -> void:
	var script := load("res://scripts/systems/meta_event_state.gd")
	if script == null:
		_fail("could not load MetaEventState script")
		return
	var meta: RefCounted = script.new()
	meta.configure({})

	if meta.get_pending_count() != 3:
		_fail("default schedule should have 3 pending events, got %d" % meta.get_pending_count())
		return

	# Tick through the full schedule (default: 12, 30, 55).
	# 12s tick: only the 12s event fires.
	var due1: Array = meta.tick(20.0)
	if due1.size() != 1:
		_fail("at 20s exactly one event (12s) should have fired, got %d" % due1.size())
		return
	# 20s tick: only the 30s event fires (elapsed becomes 40s).
	var due2: Array = meta.tick(20.0)
	if due2.size() != 1:
		_fail("at 40s exactly one event (30s) should fire, got %d" % due2.size())
		return
	# 20s tick: only the 55s event fires (elapsed becomes 60s).
	var due3: Array = meta.tick(20.0)
	if due3.size() != 1:
		_fail("at 60s exactly one event (55s) should fire, got %d" % due3.size())
		return

	if meta.get_pending_count() != 0:
		_fail("after full schedule pending should be 0, got %d" % meta.get_pending_count())
		return
	if meta.get_fired_count() != 3:
		_fail("fired_count should be 3")
		return

	# Tick past the schedule -> nothing new fires.
	var due_post: Array = meta.tick(10.0)
	if due_post.size() != 0:
		_fail("no events should fire past the schedule")
		return

	# Custom schedule.
	var meta2: RefCounted = script.new()
	meta2.configure({"events": [
		{"id": "beacon_distress", "trigger_time": 5.0, "voice_log_id": "log.beacon_01", "volume_db": -3.0},
		{"id": "hull_groan", "trigger_time": 15.0, "voice_log_id": "", "volume_db": -6.0},
	]})
	if meta2.get_pending_count() != 2:
		_fail("custom schedule should have 2 events")
		return
	var due4: Array = meta2.tick(10.0)
	if due4.size() != 1:
		_fail("first event should fire at 5s")
		return
	var first_fired: Dictionary = due4[0]
	if String(first_fired.get("id", "")) != "beacon_distress":
		_fail("first fired should be beacon_distress, got %s" % str(first_fired.get("id")))
		return
	if String(first_fired.get("voice_log_id", "")) != "log.beacon_01":
		_fail("voice_log_id should propagate")
		return

	# schedule_event inserts at the right slot.
	meta2.schedule_event(&"biomatter_pulse", 8.0, "log.pulse_01", -6.0)
	if meta2.get_pending_count() != 2:
		_fail("schedule_event should add 1 entry")
		return
	# Now fire 8s tick: the just-scheduled biomatter_pulse fires (was scheduled at 8.0).
	var due5: Array = meta2.tick(2.0)
	if due5.size() != 1:
		_fail("biomatter_pulse should fire at 8s, got %d events" % due5.size())
		return
	if String((due5[0] as Dictionary).get("id", "")) != "biomatter_pulse":
		_fail("biomatter_pulse should fire before hull_groan")
		return

	# Seed determinism: same seed -> same offset.
	var m_seed_a: RefCounted = script.new()
	m_seed_a.configure({"run_seed": 7})
	var m_seed_b: RefCounted = script.new()
	m_seed_b.configure({"run_seed": 7})
	var pending_a: Array = m_seed_a.get_pending_events()
	var pending_b: Array = m_seed_b.get_pending_events()
	if pending_a.size() != pending_b.size():
		_fail("seeded runs should have same pending count")
		return
	for i in range(pending_a.size()):
		if absf(float((pending_a[i] as Dictionary).get("trigger_time", 0.0)) - float((pending_b[i] as Dictionary).get("trigger_time", 0.0))) > 0.001:
			_fail("seeded runs should have matching trigger_times")
			return

	# Round-trip summary.
	var summary: Dictionary = meta2.get_summary()
	if str(summary.get("kind", "")) != "meta_event_state":
		_fail("summary kind missing")
		return
	var other: RefCounted = script.new()
	if not other.apply_summary(summary):
		_fail("apply_summary should report changes")
		return
	if other.get_fired_count() != meta2.get_fired_count():
		_fail("apply_summary should restore fired count")
		return

	print("META EVENT STATE PASS fired=3 pending=0 deterministic_seed=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("META EVENT STATE FAIL reason=%s" % reason)
	quit(1)
