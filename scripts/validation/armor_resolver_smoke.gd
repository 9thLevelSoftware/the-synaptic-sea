extends SceneTree

const ArmorResolverScript := preload("res://scripts/systems/armor_resolver.gd")

func _initialize() -> void:
	var armor = ArmorResolverScript.new()
	armor.configure({
		"flat_reduction": {"physical": 2.0},
		"resistance": {"physical": 0.25, "fire": -0.10},
		"durability": 20.0,
		"max_durability": 20.0,
		"wear_factor": 0.5,
	})
	var result: Dictionary = armor.resolve_damage({"damage_type": "physical", "amount": 10.0})
	if absf(float(result.get("final_damage", 0.0)) - 6.0) > 0.01:
		_fail("expected final_damage 6.0 got %.2f" % float(result.get("final_damage", 0.0)))
		return
	if absf(float(result.get("durability", 0.0)) - 18.0) > 0.01:
		_fail("expected durability 18.0 got %.2f" % float(result.get("durability", 0.0)))
		return
	var fire_result: Dictionary = armor.resolve_damage({"damage_type": "fire", "amount": 10.0})
	if float(fire_result.get("final_damage", 0.0)) <= 10.0:
		_fail("expected fire weakness to amplify damage, got %.2f" % float(fire_result.get("final_damage", 0.0)))
		return
	print("ARMOR RESOLVER PASS final=%.1f durability=%.1f fire=%.1f" % [
		float(result.get("final_damage", 0.0)),
		float(result.get("durability", 0.0)),
		float(fire_result.get("final_damage", 0.0)),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("ARMOR RESOLVER FAIL reason=%s" % reason)
	quit(1)
