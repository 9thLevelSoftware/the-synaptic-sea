extends SceneTree

## Domain 2 (BP3): the reward data exists and resolves — every archetype names a
## loot_table that exists in loot_tables.json, and the threat_killed training
## action maps to a real skill with positive XP.
##
## Pass marker: COMBAT REWARD DATA PASS archetypes=true table=true training=true

func _initialize() -> void:
	var arch: Dictionary = _json("res://data/combat/threat_archetypes.json")
	var tables: Dictionary = _json("res://data/items/loot_tables.json")
	if arch.is_empty() or tables.is_empty():
		_fail("could not load archetype/table data")
		return
	for aid in arch:
		var lt: String = str((arch[aid] as Dictionary).get("loot_table", ""))
		if lt.is_empty() or not tables.has(lt):
			_fail("archetype %s has no valid loot_table (%s)" % [aid, lt])
			return
	# Training action resolves.
	var TrainingBus := preload("res://scripts/systems/training_event_bus.gd")
	var bus = TrainingBus.new()
	bus.configure()
	var action: Dictionary = bus._actions_by_id.get("threat_killed", {})
	if action.is_empty():
		_fail("threat_killed training action missing")
		return
	if str(action.get("target_skill", "")).is_empty() or int(action.get("base_xp", 0)) <= 0:
		_fail("threat_killed action must map to a skill with positive base_xp")
		return
	print("COMBAT REWARD DATA PASS archetypes=true table=true training=true")
	quit(0)

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}

func _fail(reason: String) -> void:
	push_error("COMBAT REWARD DATA FAIL reason=%s" % reason)
	quit(1)
