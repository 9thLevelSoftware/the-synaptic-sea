extends SceneTree

const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")


func _initialize() -> void:
	var all_data: Dictionary = {}

	# Derelict + life boat start scenes. StartSceneBuilder consumes one complete
	# Rust bundle in memory for each seed.
	for seed_val: int in [42, 999, 7777]:
		var scene: Node3D = StartSceneBuilderScript.build(seed_val)
		if scene == null:
			push_error("SHIP DATA EXPORT FAIL seed=%d" % seed_val)
			quit(1)
			return
		var derelict: Node3D = scene.get_child(0) as Node3D
		var life_boat: Node3D = scene.get_child(1) as Node3D
		var rooms: Array[Dictionary] = []
		_append_layout_rows(rooms, derelict.layout_doc, Vector3.ZERO, "derelict")
		_append_layout_rows(rooms, life_boat.layout_doc, life_boat.position, "life_boat")
		all_data["start_seed_%d" % seed_val] = rooms
		scene.free()

	# Standalone fixed authored life boat.
	var life_boat_rooms: Array[Dictionary] = []
	_append_layout_rows(
		life_boat_rooms, LifeBoatBuilderScript.build_layout(), Vector3.ZERO, "life_boat")
	all_data["life_boat_standalone"] = life_boat_rooms

	var file: FileAccess = FileAccess.open("res://scenes/generated/ship_data.json", FileAccess.WRITE)
	if file == null:
		push_error("SHIP DATA EXPORT FAIL cannot open output")
		quit(1)
		return
	file.store_string(JSON.stringify(all_data, "  "))
	file.close()
	print("SHIP DATA SAVED bundle=true seeds=3")
	quit(0)


func _append_layout_rows(
		rows: Array[Dictionary],
		layout: Dictionary,
		offset: Vector3,
		ship_kind: String) -> void:
	for room_variant: Variant in layout.get("rooms", []):
		if not room_variant is Dictionary:
			continue
		var room: Dictionary = room_variant
		var placements: Array = room.get("structural_placements", [])
		var position_sum: Vector3 = Vector3.ZERO
		var position_count: int = 0
		for placement_variant: Variant in placements:
			if not placement_variant is Dictionary:
				continue
			var placement: Dictionary = placement_variant
			var raw_position: Variant = placement.get(
				"world_position", placement.get("position", []))
			if not raw_position is Array or (raw_position as Array).size() < 3:
				continue
			var values: Array = raw_position
			position_sum += Vector3(float(values[0]), float(values[1]), float(values[2]))
			position_count += 1
		var center: Vector3 = offset
		if position_count > 0:
			center += position_sum / float(position_count)
		rows.append({
			"name": str(room.get("id", room.get("room_id", "room"))),
			"x": center.x,
			"z": center.z,
			"modules": placements.size(),
			"ship": ship_kind,
		})
