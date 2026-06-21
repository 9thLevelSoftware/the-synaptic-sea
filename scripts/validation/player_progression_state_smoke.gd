extends SceneTree

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ProgressionScript := preload("res://scripts/systems/player_progression_state.gd")

func _initialize() -> void:
	var catalog: Dictionary = ProgressionScript.load_skills_catalog()
	if catalog.get("repair", {}).get("category", "") != "technical":
		_fail("repair category should be technical")
		return

	var eng = ClassDefinitionScript.load_all()["engineer"]
	var prog = ProgressionScript.new()
	prog.configure(eng, catalog)

	if prog.get_class_id() != "engineer":
		_fail("class_id=%s" % prog.get_class_id())
		return
	if prog.get_skill_level("repair") != 3:
		_fail("seeded repair=%d expected 3" % prog.get_skill_level("repair"))
		return
	# Unseeded skill defaults to 0.
	if prog.get_skill_level("surgery") != 0:
		_fail("unseeded surgery should be 0")
		return

	# XP curve: level L -> L+1 needs (L+1)*100.
	if ProgressionScript.xp_for_next_level(3) != 400:
		_fail("xp_for_next_level(3)=%d expected 400" % ProgressionScript.xp_for_next_level(3))
		return

	# Engineer technical multiplier 1.5: granting 100 raw -> 150 effective.
	# repair is level 3 (needs 400 to reach 4); 150 < 400 so no level change yet.
	if prog.grant_xp("repair", 100):
		_fail("grant_xp 100 should not have leveled repair from 3")
		return
	if prog.get_skill_level("repair") != 3:
		_fail("repair changed unexpectedly")
		return
	# Grant enough to cross: 150 already banked; +250 raw *1.5 = 375 -> 525 total >= 400 -> level 4.
	if not prog.grant_xp("repair", 250):
		_fail("grant_xp 250 should have leveled repair to 4")
		return
	if prog.get_skill_level("repair") != 4:
		_fail("repair=%d expected 4 after level up" % prog.get_skill_level("repair"))
		return

	# Unknown skill -> false, no crash.
	if prog.grant_xp("not_a_skill", 100):
		_fail("grant_xp on unknown skill should return false")
		return

	# Round-trip.
	var summary: Dictionary = prog.get_summary()
	var prog2 = ProgressionScript.new()
	prog2.configure(eng, catalog)
	if not prog2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if prog2.get_skill_level("repair") != 4:
		_fail("round-trip repair=%d expected 4" % prog2.get_skill_level("repair"))
		return

	print("PLAYER PROGRESSION PASS class=engineer repair_start=3 leveled=4 round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER PROGRESSION FAIL reason=%s" % reason)
	quit(1)
