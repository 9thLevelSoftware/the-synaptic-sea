extends SceneTree

## REQ-PM-005 / ADR-0033 cross-training smoke.
##
## Asserts that:
##   - Off-category events accumulate a cross_training counter.
##   - In-category events do NOT.
##   - The counter is preserved across apply_summary.
##   - get_cross_training_total() returns the sum across all skills.
##   - The cross-training penalty is applied multiplicatively with the
##     class multiplier (engineer 0.7x medical * 0.5 cross = 0.35).

const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var catalog: Dictionary = PlayerProgressionScript.load_skills_catalog()
	var books: Dictionary = PlayerProgressionScript.load_books_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	# Engineer: technical=1.5, medical=0.7. Repair event is technical
	# (primary). First aid event is medical (cross-training).
	var prog = PlayerProgressionScript.new()
	prog.configure(classes["engineer"], catalog, books)

	# Three repairs (in-category). Cross-training counter for repair must
	# stay at 0.
	for i in 3:
		prog.grant_xp("repair", 50, false)
	if int(prog.get_cross_training("repair")) != 0:
		_fail("in-category grant_xp should NOT add to cross_training; got %d" % int(prog.get_cross_training("repair")))
		return

	# Two first_aid events (cross-training). Counter must rise by 60
	# (30 each).
	prog.grant_xp("first_aid", 30, true)
	prog.grant_xp("first_aid", 30, true)
	if int(prog.get_cross_training("first_aid")) != 60:
		_fail("first_aid cross_training should be 60, got %d" % int(prog.get_cross_training("first_aid")))
		return

	# get_cross_training_total sums across skills.
	prog.grant_xp("cooking", 40, true)  # cook class is survival-primary; for engineer it's social-adjacent → cross.
	if int(prog.get_cross_training_total()) != 60 + 40:
		_fail("cross_training_total=%d expected 100" % int(prog.get_cross_training_total()))
		return

	# The grant_xp multiplier compounds: engineer medical 0.7 * cross
	# 0.5 = 0.35. So 100 raw grant = 35 effective XP banked on first_aid.
	# We seeded first_aid XP via 30+30 cross-training. The banked XP
	# should be 30 * 0.35 + 30 * 0.35 = 21.
	var first_aid_xp: int = int(prog.get_skill_xp("first_aid"))
	if first_aid_xp != 21:
		_fail("first_aid xp=%d expected 21 (30*0.7*0.5 + 30*0.7*0.5)" % first_aid_xp)
		return

	# Round-trip preserves cross_training.
	var summary: Dictionary = prog.get_summary()
	var prog2 = PlayerProgressionScript.new()
	prog2.configure(classes["engineer"], catalog, books)
	prog2.apply_summary(summary)
	if int(prog2.get_cross_training("first_aid")) != 60:
		_fail("round-trip first_aid cross=%d expected 60" % int(prog2.get_cross_training("first_aid")))
		return
	if int(prog2.get_cross_training_total()) != 100:
		_fail("round-trip total=%d expected 100" % int(prog2.get_cross_training_total()))
		return

	# A fresh progression with no cross-training events has total 0.
	var prog3 = PlayerProgressionScript.new()
	prog3.configure(classes["engineer"], catalog, books)
	if int(prog3.get_cross_training_total()) != 0:
		_fail("fresh progression cross_training_total should be 0")
		return

	print("CROSS TRAINING PASS in_category=0 cross_counters=ok round_trip=true total=100")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CROSS TRAINING FAIL reason=%s" % reason)
	quit(1)