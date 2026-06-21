extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ProgressionScript := preload("res://scripts/systems/player_progression_state.gd")

const PARTS := ["power_cell"]
const TOOLS := ["welder"]

func _break(mgr) -> void:
	mgr.get_system("power").get_subcomponent("power_distribution").health = 0.0

func _initialize() -> void:
	var catalog: Dictionary = ProgressionScript.load_skills_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	# Cook starts repair 0 -> below power_distribution.min_skill (2): rejected.
	var prog_low = ProgressionScript.new()
	prog_low.configure(classes["cook"], catalog)
	var mgr = ManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 1)  # PRISTINE so only our break matters
	_break(mgr)
	var r_low: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_low.get_skill_level("repair"))
	if bool(r_low.get("success", true)) or str(r_low.get("reason", "")) != "insufficient_skill":
		_fail("low skill should be insufficient_skill, got %s" % str(r_low))
		return

	# Engineer starts repair 3 (>= min_skill 2): success.
	var prog_hi = ProgressionScript.new()
	prog_hi.configure(classes["engineer"], catalog)
	_break(mgr)
	var r_hi: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_hi.get_skill_level("repair"))
	if not bool(r_hi.get("success", false)):
		_fail("engineer repair should succeed, got %s" % str(r_hi))
		return
	# NOTE on the two "seconds" defaults below: they are intentionally
	# asymmetric so a missing key fails LOUD, not silent. The baseline (slower)
	# time defaults to 0.0 so that if it were absent, `faster >= 0.0` trips the
	# failure; the faster time (line below) defaults to a large 999.0 so that if
	# IT were absent, `999.0 >= baseline` also trips the failure. Do not "fix"
	# this to match — making the baseline large would let a missing key pass.
	var seconds_skill3: float = float(r_hi.get("seconds", 0.0))

	# Raise engineer repair to a higher level via grant_xp, repair again: faster.
	while prog_hi.get_skill_level("repair") < 6:
		prog_hi.grant_xp("repair", 1000)
	_break(mgr)
	var r_faster: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_hi.get_skill_level("repair"))
	if not bool(r_faster.get("success", false)):
		_fail("higher-skill repair should succeed, got %s" % str(r_faster))
		return
	if float(r_faster.get("seconds", 999.0)) >= seconds_skill3:
		_fail("higher skill should repair faster: %f !< %f" % [float(r_faster.get("seconds", 999.0)), seconds_skill3])
		return

	print("PROGRESSION REPAIR INTEGRATION PASS rejected_low=true success_hi=true faster_at_higher_skill=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PROGRESSION REPAIR INTEGRATION FAIL reason=%s" % reason)
	quit(1)
