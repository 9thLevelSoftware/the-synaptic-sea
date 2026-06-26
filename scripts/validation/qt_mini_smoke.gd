extends SceneTree

func _initialize() -> void:
	var resolver = load("res://scripts/systems/quality_tier_resolver.gd").new()
	print("QT MINI PASS mult=%s" % str(resolver.multiplier_for_tier("standard")))
	quit()
