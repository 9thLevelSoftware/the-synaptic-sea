extends SceneTree
const V := preload("res://scripts/systems/vitals_state.gd")
func _initialize():
	var v = V.new()
	v.configure({})
	v.health = 72.0
	print("v.health before get_summary=" + str(v.health))
	var s = v.get_summary()
	print("summary health=" + str(s.get("health")))
	var v2 = V.new()
	v2.configure({})
	print("v2.health before apply=" + str(v2.health))
	var ok = v2.apply_summary(s)
	print("apply_summary returned=" + str(ok))
	print("v2.health after apply=" + str(v2.health))
	quit(0)
