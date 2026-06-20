extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var test_count: int = 0

	for template_id in templates:
		for seed_val in [42, 999, 7777]:
			test_count += 1
			var bp: ShipBlueprintScript = ShipBlueprintScript.new(
				ShipBlueprintScript.Size.MEDIUM,
				ShipBlueprintScript.Condition.DAMAGED,
				seed_val)
			var layout: Dictionary = generator.generate(bp, {"template": template_id})
			if layout.is_empty():
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d layout empty" % [template_id, seed_val])
				quit(1)
				return

			var slice: Dictionary = builder.build(layout)

			# Must have start_room and goal_room
			var start_room: String = str(slice.get("start_room", ""))
			var goal_room: String = str(slice.get("goal_room", ""))
			if start_room.is_empty():
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing start_room" % [template_id, seed_val])
				quit(1)
				return
			if goal_room.is_empty():
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing goal_room" % [template_id, seed_val])
				quit(1)
				return

			# start_room and goal_room must be different
			if start_room == goal_room:
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d start==goal '%s'" % [template_id, seed_val, start_room])
				quit(1)
				return

			# Must have at least one objective
			var objectives: Array = slice.get("objectives", [])
			if objectives.is_empty():
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d no objectives" % [template_id, seed_val])
				quit(1)
				return

			# Each objective must have id, sequence, type, room_id, approach_cell
			var expected_seq: int = 1
			for obj in objectives:
				if str(obj.get("id", "")).is_empty():
					push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective missing id" % [template_id, seed_val])
					quit(1)
					return
				if int(obj.get("sequence", 0)) != expected_seq:
					push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective seq expected=%d got=%d" % [template_id, seed_val, expected_seq, int(obj.get("sequence", 0))])
					quit(1)
					return
				expected_seq += 1
				var room_id: String = str(obj.get("room_id", ""))
				if room_id.is_empty():
					push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective missing room_id" % [template_id, seed_val])
					quit(1)
					return
				var approach: Array = obj.get("approach_cell", [])
				if approach.size() < 3:
					push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d objective approach_cell incomplete" % [template_id, seed_val])
					quit(1)
					return

			# Must have zone arrays (can be empty)
			for key in ["fire_zones", "arc_zones", "breach_zones"]:
				if typeof(slice.get(key, null)) != TYPE_ARRAY:
					push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d missing %s array" % [template_id, seed_val, key])
					quit(1)
					return

			# start_room and goal_room must exist in layout rooms
			var room_ids: Array[String] = []
			for room in layout.get("rooms", []):
				room_ids.append(str(room.get("id", "")))
			if start_room not in room_ids:
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d start_room '%s' not in layout" % [template_id, seed_val, start_room])
				quit(1)
				return
			if goal_room not in room_ids:
				push_error("GAMEPLAY_SLICE_BUILDER FAIL %s seed=%d goal_room '%s' not in layout" % [template_id, seed_val, goal_room])
				quit(1)
				return

	print("GAMEPLAY_SLICE_BUILDER PASS all %d layouts produced valid slices" % test_count)
	quit(0)
