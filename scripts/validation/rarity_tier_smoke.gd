extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/systems/rarity_tier.gd")
	if script == null:
		_fail("could not load rarity_tier.gd")
		return
	if script.normalize("LEGENDARY") != "legendary":
		_fail("normalize should lowercase valid tiers")
		return
	if script.normalize("unknown") != "common":
		_fail("unknown rarity should normalize to common")
		return
	if script.from_roll(0.98) != "legendary":
		_fail("0.98 should roll legendary")
		return
	if script.from_roll(0.86) != "epic":
		_fail("0.86 should roll epic")
		return
	if script.max_rarity("rare", "epic") != "epic":
		_fail("max_rarity should keep highest tier")
		return
	if script.hex("rare").is_empty():
		_fail("hex(rare) should not be empty")
		return
	var lines: PackedStringArray = script.get_status_lines()
	if lines.size() != 5:
		_fail("expected 5 status lines, got %d" % lines.size())
		return
	print("RARITY TIER PASS tiers=%d legendary=%s" % [lines.size(), script.label("legendary")])
	quit(0)

func _fail(reason: String) -> void:
	push_error("RARITY TIER FAIL reason=%s" % reason)
	quit(1)
