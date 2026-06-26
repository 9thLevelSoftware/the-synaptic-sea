extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var total: int = 0
	var passed: int = 0
	var min_rooms: int = 999
	var max_rooms: int = 0

	# Generate 20 ships: ~7 per template
	for seed_val in range(1, 21):
		for template_id in templates:
			total += 1
			var bp: ShipBlueprintScript = ShipBlueprintScript.new(
				ShipBlueprintScript.Size.MEDIUM,
				ShipBlueprintScript.Condition.PRISTINE,
				seed_val)
			var layout: Dictionary = generator.generate(bp, {"template": template_id})

			if layout.is_empty():
				push_error("STRESS FAIL %s seed=%d empty" % [template_id, seed_val])
				quit(1)
				return

			var rooms: Array = layout.get("rooms", [])
			if rooms.size() < 3:
				push_error("STRESS FAIL %s seed=%d only %d rooms" % [template_id, seed_val, rooms.size()])
				quit(1)
				return

			# Check no zero-placement rooms
			for room in rooms:
				if room.get("structural_placements", []).is_empty():
					push_error("STRESS FAIL %s seed=%d room %s no placements" % [
						template_id, seed_val, str(room.get("id", "?"))])
					quit(1)
					return

			if rooms.size() < min_rooms:
				min_rooms = rooms.size()
			if rooms.size() > max_rooms:
				max_rooms = rooms.size()

			passed += 1

	# Golden comparison: same seed = same layout
	var golden_bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 12345)

	for template_id in templates:
		var a: String = JSON.stringify(generator.generate(golden_bp, {"template": template_id}))
		var b: String = JSON.stringify(generator.generate(golden_bp, {"template": template_id}))
		if a != b:
			push_error("STRESS FAIL golden comparison mismatch template=%s" % template_id)
			quit(1)
			return

	print("PROCGEN LAYOUT STRESS PASS total=%d/%d rooms=[%d,%d] golden=deterministic" % [
		passed, total, min_rooms, max_rooms])
	quit(0)
