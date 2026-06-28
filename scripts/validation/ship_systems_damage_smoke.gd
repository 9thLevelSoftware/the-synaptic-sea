extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

## Pass marker: SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true

func _initialize() -> void:
	var mgr = ManagerScript.new()
	var defs = mgr.load_definitions()
	mgr.configure(defs, ManagerScript.CONDITION_PRISTINE, 1)
	var before: float = mgr.get_system("power").health()
	if before < 0.99:
		_fail("pristine power should start healthy"); return
	if not mgr.damage_system("power", 0.6):
		_fail("damage_system(power) should return true"); return
	var after: float = mgr.get_system("power").health()
	if after >= before:
		_fail("power health should drop after damage (%.2f -> %.2f)" % [before, after]); return
	if mgr.is_operational("power"):
		_fail("power should be non-operational after 0.6 damage (below threshold)"); return
	if mgr.damage_system("does_not_exist", 0.5):
		_fail("damage_system on unknown system should return false"); return
	print("SHIP SYSTEMS DAMAGE PASS damaged=true unknown_rejected=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS DAMAGE FAIL reason=%s" % reason)
	quit(1)
