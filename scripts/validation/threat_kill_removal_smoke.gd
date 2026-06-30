extends SceneTree

## Domain 2 (BP3): killing a threat emits threat_killed exactly once with the
## archetype's loot_table, and removes the corpse from the active array.
##
## Pass marker:
##   THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true

const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

var _events: Array = []

func _initialize() -> void:
	var tm = ThreatManagerScript.new()
	tm._ready()
	tm.inject_validation_encounter(["stalker"], Vector3.ZERO)
	if tm.threats.size() != 1:
		_fail(tm, "expected 1 threat")
		return
	tm.threat_killed.connect(_on_killed)
	# Kill it.
	tm.threats[0].health = 0.0
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if _events.size() != 1:
		_fail(tm, "expected exactly one threat_killed event, got %d" % _events.size())
		return
	if tm.threats.size() != 0:
		_fail(tm, "dead threat should be removed from the active array")
		return
	if str(_events[0].get("loot_table", "")).is_empty():
		_fail(tm, "kill record should carry a loot_table")
		return
	# A second tick must not re-emit (idempotent).
	tm.tick_threats(0.1, null, null, {}, Vector3.ZERO)
	if _events.size() != 1:
		_fail(tm, "kill must not re-emit on a later tick")
		return
	print("THREAT KILL REMOVAL PASS emitted_once=true removed=true loot_table=true")
	tm.free()
	quit(0)

func _on_killed(record: Dictionary) -> void:
	_events.append(record)

func _fail(tm: Node, reason: String) -> void:
	push_error("THREAT KILL REMOVAL FAIL reason=%s" % reason)
	if tm != null and is_instance_valid(tm):
		tm.free()
	quit(1)
