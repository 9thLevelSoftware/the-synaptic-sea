extends SceneTree

const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")

func _initialize() -> void:
	var state = StatusEffectsStateScript.new()
	state.configure({})
	if not state.add_effect("bleed", 5.0, 1):
		_fail("could not add bleed")
		return
	if not state.add_effect("burn", 3.0, 2):
		_fail("could not add burn")
		return
	if state.get_stacks("burn") != 2:
		_fail("expected burn stacks=2 got %d" % state.get_stacks("burn"))
		return
	state.tick(1.5)
	var summary: Dictionary = state.get_summary()
	if int(summary.get("count", 0)) != 2:
		_fail("expected 2 active effects got %d" % int(summary.get("count", 0)))
		return
	if not state.remove_effect("burn", 1):
		_fail("expected burn removal to succeed")
		return
	if state.get_stacks("burn") != 1:
		_fail("expected burn stacks=1 after removal got %d" % state.get_stacks("burn"))
		return
	state.tick(4.0)
	if state.has_effect("bleed") or state.has_effect("burn"):
		_fail("expected all effects to expire")
		return
	print("STATUS EFFECTS PASS count=2 expired=true modifier=%.2f" % state.get_modifier("stamina_recovery"))
	quit(0)

func _fail(reason: String) -> void:
	push_error("STATUS EFFECTS FAIL reason=%s" % reason)
	quit(1)
