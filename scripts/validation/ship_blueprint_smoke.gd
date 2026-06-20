extends SceneTree

# ShipBlueprint smoke. Exercises all 3 sizes, all 3 conditions, and a
# to_dict/from_dict round-trip. Prints a single PASS line on success so
# automated verification can grep for it; push_error + quit(1) on any
# failure path so a regression blocks the gate rather than silently
# passing.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

func _initialize() -> void:
	var size_results: Array = []
	for s in [ShipBlueprintScript.Size.LIFE_BOAT, ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Size.MEDIUM]:
		var bp: ShipBlueprintScript = ShipBlueprintScript.new(s, ShipBlueprintScript.Condition.PRISTINE, 1)
		var r: Vector2i = bp._get_room_count_range()
		if r.x < 1 or r.y < r.x:
			push_error("SHIP BLUEPRINT FAIL size=%d range=%s" % [s, str(r)])
			quit(1)
			return
		size_results.append(r)

	var condition_results: Array = []
	for c in [ShipBlueprintScript.Condition.PRISTINE, ShipBlueprintScript.Condition.DAMAGED, ShipBlueprintScript.Condition.WRECKED]:
		var bp2: ShipBlueprintScript = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, c, 2)
		var chance: float = bp2.get_system_online_chance()
		if chance < 0.0 or chance > 1.0:
			push_error("SHIP BLUEPRINT FAIL condition=%d chance=%f" % [c, chance])
			quit(1)
			return
		condition_results.append(chance)

	# Sanity-check the exact spec values so a silent numeric drift in the
	# class shows up here rather than downstream.
	var pristine_chance: float = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.PRISTINE,
			3).get_system_online_chance()
	if not is_equal_approx(pristine_chance, 0.9):
		push_error("SHIP BLUEPRINT FAIL pristine chance=%f expected=0.9" % pristine_chance)
		quit(1)
		return
	var wrecked_chance: float = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.WRECKED,
			4).get_system_online_chance()
	if not is_equal_approx(wrecked_chance, 0.2):
		push_error("SHIP BLUEPRINT FAIL wrecked chance=%f expected=0.2" % wrecked_chance)
		quit(1)
		return
	var lifeboat_range: Vector2i = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.LIFE_BOAT,
			ShipBlueprintScript.Condition.PRISTINE,
			5)._get_room_count_range()
	if lifeboat_range != Vector2i(2, 4):
		push_error("SHIP BLUEPRINT FAIL lifeboat range=%s expected=(2,4)" % str(lifeboat_range))
		quit(1)
		return

	# Serialisation round-trip: to_dict then from_dict must reproduce the
	# original fields exactly.
	var original: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.SMALL,
			ShipBlueprintScript.Condition.DAMAGED,
			42)
	var payload: Dictionary = original.to_dict()
	var rebuilt: ShipBlueprintScript = ShipBlueprintScript.from_dict(payload)
	if rebuilt.size != original.size:
		push_error("SHIP BLUEPRINT FAIL round-trip size %d -> %d" % [original.size, rebuilt.size])
		quit(1)
		return
	if rebuilt.condition != original.condition:
		push_error("SHIP BLUEPRINT FAIL round-trip condition %d -> %d" % [original.condition, rebuilt.condition])
		quit(1)
		return
	if rebuilt.seed_value != original.seed_value:
		push_error("SHIP BLUEPRINT FAIL round-trip seed %d -> %d" % [original.seed_value, rebuilt.seed_value])
		quit(1)
		return
	if rebuilt.room_count_range != original.room_count_range:
		push_error("SHIP BLUEPRINT FAIL round-trip range %s -> %s" % [str(original.room_count_range), str(rebuilt.room_count_range)])
		quit(1)
		return

	print("SHIP BLUEPRINT PASS sizes=3 conditions=3 serialization=true")
	quit(0)