extends SceneTree

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var classes: Dictionary = ClassDefinitionScript.load_all()
	if classes.size() != 8:
		_fail("expected 8 classes, got %d" % classes.size())
		return
	for cid in ["engineer", "mechanic", "medic", "pilot", "scientist", "cook", "security", "communications"]:
		if not classes.has(cid):
			_fail("missing class %s" % cid)
			return

	var eng = classes["engineer"]
	if eng.display_name != "Engineer":
		_fail("engineer display_name=%s" % eng.display_name)
		return
	if int(eng.starting_skills.get("repair", -1)) != 3:
		_fail("engineer starting repair=%d expected 3" % int(eng.starting_skills.get("repair", -1)))
		return
	if absf(eng.xp_multiplier("technical") - 1.5) > 0.0001:
		_fail("engineer technical mult=%f expected 1.5" % eng.xp_multiplier("technical"))
		return
	# Unlisted category defaults to 1.0.
	if absf(eng.xp_multiplier("nonexistent_category") - 1.0) > 0.0001:
		_fail("unlisted category should default to 1.0")
		return

	print("CLASS DEFINITIONS PASS classes=8 engineer_repair=3 technical=1.5 default=1.0")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CLASS DEFINITIONS FAIL reason=%s" % reason)
	quit(1)
