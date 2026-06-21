extends SceneTree

const LifeSupportScript := preload("res://scripts/systems/life_support_system.gd")
const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	var deps: Array[String] = ["power"]
	var ls = LifeSupportScript.new("life_support", deps)
	ls.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))

	var oxy = ls.get_oxygen_state()
	if oxy == null:
		push_error("LIFE SUPPORT SYSTEM FAIL no oxygen state")
		quit(1)
		return
	var start_oxygen: float = oxy.oxygen

	# Offline -> oxygen drains.
	ls.advance(1.0, false)
	if ls.get_oxygen_state().oxygen >= start_oxygen:
		push_error("LIFE SUPPORT SYSTEM FAIL offline did not drain oxygen (%f -> %f)" % [start_oxygen, ls.get_oxygen_state().oxygen])
		quit(1)
		return
	var drained_oxygen: float = ls.get_oxygen_state().oxygen

	# Operational -> oxygen recovers (does not drain further).
	ls.advance(1.0, true)
	if ls.get_oxygen_state().oxygen < drained_oxygen:
		push_error("LIFE SUPPORT SYSTEM FAIL operational drained oxygen further")
		quit(1)
		return

	# Summary nests oxygen and round-trips.
	var summary: Dictionary = ls.get_summary()
	if typeof(summary.get("oxygen", null)) != TYPE_DICTIONARY:
		push_error("LIFE SUPPORT SYSTEM FAIL summary missing nested oxygen dict")
		quit(1)
		return
	# Drive a fresh instance to a different oxygen level, then restore.
	var fresh = LifeSupportScript.new("life_support", deps)
	fresh.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	fresh.advance(2.0, false)  # drain it to a different value
	if not fresh.apply_summary(summary):
		push_error("LIFE SUPPORT SYSTEM FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(fresh.get_oxygen_state().oxygen - ls.get_oxygen_state().oxygen) > 0.0001:
		push_error("LIFE SUPPORT SYSTEM FAIL round-trip oxygen mismatch (%f vs %f)" % [fresh.get_oxygen_state().oxygen, ls.get_oxygen_state().oxygen])
		quit(1)
		return

	print("LIFE SUPPORT SYSTEM PASS offline_drains=ok online_holds=ok oxygen_round_trip=ok")
	quit(0)
