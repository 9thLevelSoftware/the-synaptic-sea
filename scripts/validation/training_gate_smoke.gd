extends SceneTree

## Domain 6 training-gate smoke: an advanced skill (surgery) gains no XP through
## the bus until its skill-tree node is unlocked; a base skill (scavenging) is
## always trainable; is_gated correctly partitions advanced vs base skills.
##
## Marker: `TRAINING GATE PASS`

const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var tree = SkillTreeStateScript.new()
	var tree_catalog: Dictionary = SkillTreeStateScript.load_skills_catalog()
	if tree_catalog.is_empty():
		_fail("skill tree catalog is empty")
		return
	tree.configure(tree_catalog, SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()

	# is_gated partitions advanced (in skill_tree.json) vs base skills.
	if not tree.is_gated("surgery"):
		_fail("surgery should be gated")
		return
	if tree.is_gated("scavenging"):
		_fail("scavenging (base) should NOT be gated")
		return

	# Build a progression on the engineer class so grant_xp works.
	var classes: Dictionary = ClassDefinitionScript.load_all()
	if classes.get("engineer", null) == null:
		_fail("engineer class missing")
		return
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())

	var bus = TrainingEventBusScript.new()
	if not bus.configure():
		_fail("bus.configure failed")
		return
	# Gate: a skill is trainable if it is not gated, or its node is unlocked.
	bus.skill_gate = func(skill_id: String) -> bool:
		if not tree.is_gated(skill_id):
			return true
		return tree.is_unlocked(skill_id)

	# perform_surgery -> surgery (+150) is DROPPED while surgery is locked.
	var before_surgery: int = prog.get_skill_xp("surgery")
	var r1: Variant = bus.emit("perform_surgery", "", prog)
	if r1 != null:
		_fail("locked surgery event should be dropped (returned non-null)")
		return
	if prog.get_skill_xp("surgery") != before_surgery:
		_fail("locked surgery should have gained no XP")
		return
	if bus.get_dropped_count() != 1:
		_fail("dropped count should be 1 after a gated drop, got %d" % bus.get_dropped_count())
		return

	# A base-skill event (scavenge_container -> scavenging) always grants.
	var r2: Variant = bus.emit("scavenge_container", "", prog)
	if r2 == null:
		_fail("base-skill event should NOT be dropped")
		return
	if prog.get_skill_xp("scavenging") <= 0:
		_fail("scavenging should have gained XP")
		return

	# After unlocking the surgery node the event grants normally.
	tree.unlock("surgery")
	var r3: Variant = bus.emit("perform_surgery", "", prog)
	if r3 == null:
		_fail("unlocked surgery event should grant (returned null)")
		return
	if prog.get_skill_xp("surgery") <= before_surgery:
		_fail("unlocked surgery should have gained XP")
		return

	print("TRAINING GATE PASS gated=true drop=1 unlock_grants=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("TRAINING GATE FAIL reason=%s" % reason)
	quit(1)
