extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var success_count: int = 0
	var total_count: int = 0

	for template_id in templates:
		for seed_val in range(1, 8):  # 7 seeds per template = 21 total
			total_count += 1
			var bp: ShipBlueprintScript = ShipBlueprintScript.new(
				ShipBlueprintScript.Size.MEDIUM,
				ShipBlueprintScript.Condition.PRISTINE,
				seed_val)
			var layout: Dictionary = generator.generate(bp, {"template": template_id})

			if layout.is_empty():
				push_error("INTEGRATION FAIL %s seed=%d empty layout" % [template_id, seed_val])
				quit(1)
				return

			# Validate structure
			var rooms: Array = layout.get("rooms", [])
			if rooms.size() < 3:
				push_error("INTEGRATION FAIL %s seed=%d only %d rooms" % [template_id, seed_val, rooms.size()])
				quit(1)
				return

			# Every room must have structural_placements with world_position arrays
			for room in rooms:
				var placements: Array = room.get("structural_placements", [])
				if placements.is_empty():
					push_error("INTEGRATION FAIL %s seed=%d room %s no placements" % [
						template_id, seed_val, str(room.get("id", "?"))])
					quit(1)
					return
				for p in placements:
					var wp: Variant = p.get("world_position", null)
					if not (wp is Array) or wp.size() < 3:
						push_error("INTEGRATION FAIL %s seed=%d bad world_position in room %s" % [
							template_id, seed_val, str(room.get("id", "?"))])
						quit(1)
						return

			# room_links must not be empty (need connections)
			var links: Array = layout.get("room_links", [])
			if links.is_empty():
				push_error("INTEGRATION FAIL %s seed=%d no room_links" % [template_id, seed_val])
				quit(1)
				return

			# Critical path must exist
			var cp: Array = layout.get("critical_path", [])
			if cp.size() < 2:
				push_error("INTEGRATION FAIL %s seed=%d critical_path too short" % [template_id, seed_val])
				quit(1)
				return

			# Verify JSON round-trip
			var json_text: String = JSON.stringify(layout, "  ")
			var reparsed: Variant = JSON.parse_string(json_text)
			if not (reparsed is Dictionary):
				push_error("INTEGRATION FAIL %s seed=%d JSON round-trip failed" % [template_id, seed_val])
				quit(1)
				return

			success_count += 1

	# Determinism check: same seed+template = same JSON
	var bp_det: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var layout_a: Dictionary = generator.generate(bp_det, {"template": "spine"})
	var layout_b: Dictionary = generator.generate(bp_det, {"template": "spine"})
	var json_a: String = JSON.stringify(layout_a)
	var json_b: String = JSON.stringify(layout_b)
	if json_a != json_b:
		push_error("INTEGRATION FAIL determinism mismatch")
		quit(1)
		return

	print("SHIP LAYOUT INTEGRATION PASS generated=%d/%d deterministic=true json_roundtrip=true" % [success_count, total_count])
	quit(0)
