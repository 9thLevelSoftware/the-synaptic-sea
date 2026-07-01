extends SceneTree

## Domain 6 (WI-5): repair objective XP flows through the bus ONCE (120), not a
## direct grant (50) PLUS the bus (120) = 170. Asserts the bus resolves
## repair_full_system to 120 and that a single emit delivers exactly 120 XP
## total.
##
## Both assertions below (`record.base_xp` and `get_total_xp_delivered()`)
## read the bus's own raw catalog counters, which are computed BEFORE any
## class XP multiplier is applied to the underlying grant_xp call — so this
## smoke is deliberately class-multiplier-independent and does not need to
## special-case any particular player class.
##
## Marker: `REPAIR INGEST PASS`

const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var bus = TrainingEventBusScript.new()
	if not bus.configure():
		_fail("bus failed to load training_actions.json")
		return

	var classes: Dictionary = ClassDefinitionScript.load_all()
	var sec = classes.get("security", null)
	if sec == null:
		_fail("expected 'security' class to exist in classes.json")
		return

	var prog = PlayerProgressionScript.new()
	prog.configure(sec, PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())

	var r: Variant = bus.emit("repair_full_system", "seq", prog)
	if r == null:
		_fail("repair_full_system should resolve through the bus")
		return
	if int((r as Dictionary).get("base_xp", 0)) != 120:
		_fail("repair_full_system base_xp=%d expected 120" % int((r as Dictionary).get("base_xp", 0)))
		return
	# Single grant only — the bus's own delivered-XP counter is the
	# multiplier-independent, level-up-independent proof that exactly one
	# 120 XP grant occurred (not a direct grant_xp(50) plus this bus grant,
	# which would be 170).
	if bus.get_total_xp_delivered() != 120:
		_fail("bus delivered %d XP, expected a single 120 grant" % bus.get_total_xp_delivered())
		return

	print("REPAIR INGEST PASS bus_xp=120 single_grant=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("REPAIR INGEST FAIL reason=%s" % reason)
	quit(1)
