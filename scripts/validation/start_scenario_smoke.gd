extends SceneTree

const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

func _initialize() -> void:
	# Test 1: Derelict layout generation through pipeline
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var slice_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()

	var archetype_path: String = "res://data/procgen/archetypes/derelict.json"
	var archetype_text: String = FileAccess.get_file_as_string(archetype_path)
	var archetype: Variant = JSON.parse_string(archetype_text)
	if typeof(archetype) != TYPE_DICTIONARY:
		push_error("START_SCENARIO FAIL cannot load derelict archetype")
		quit(1)
		return

	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.WRECKED,
		42)
	var layout: Dictionary = generator.generate(bp, archetype)
	if layout.is_empty():
		push_error("START_SCENARIO FAIL derelict layout empty")
		quit(1)
		return

	var rooms: Array = layout.get("rooms", [])
	if rooms.size() < 3:
		push_error("START_SCENARIO FAIL derelict has only %d rooms" % rooms.size())
		quit(1)
		return

	# Verify all rooms have structural placements
	for room in rooms:
		var placements: Array = room.get("structural_placements", [])
		if placements.is_empty():
			push_error("START_SCENARIO FAIL room '%s' has no placements" % str(room.get("id", "")))
			quit(1)
			return

	# Test 2: Gameplay slice builds from layout
	var gameplay: Dictionary = slice_builder.build(layout)
	if str(gameplay.get("start_room", "")).is_empty():
		push_error("START_SCENARIO FAIL gameplay slice missing start_room")
		quit(1)
		return
	if str(gameplay.get("goal_room", "")).is_empty():
		push_error("START_SCENARIO FAIL gameplay slice missing goal_room")
		quit(1)
		return
	if gameplay.get("objectives", []).is_empty():
		push_error("START_SCENARIO FAIL gameplay slice has no objectives")
		quit(1)
		return

	# Test 3: Layout can be loaded by GeneratedShipLoader
	var temp_dir: String = "user://start_scenario_smoke_temp"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_absolute(temp_dir)

	var layout_path: String = temp_dir + "/layout.json"
	var gameplay_path: String = temp_dir + "/gameplay_slice.json"
	var kit_path: String = "res://data/kits/ship_structural_v0.json"

	var lf: FileAccess = FileAccess.open(layout_path, FileAccess.WRITE)
	lf.store_string(JSON.stringify(layout, "  "))
	lf.close()
	var gf: FileAccess = FileAccess.open(gameplay_path, FileAccess.WRITE)
	gf.store_string(JSON.stringify(gameplay, "  "))
	gf.close()

	var LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
	var loader: Node3D = LoaderScript.new()
	var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path)
	if not success:
		loader.free()
		push_error("START_SCENARIO FAIL GeneratedShipLoader.load_from_paths returned false")
		quit(1)
		return
	# Loader instantiated the full ship into a detached Node3D (never added to the
	# tree). Free it now so its geometry/physics/nav RIDs don't leak at quit().
	loader.free()

	# Test 4: Navigation mesh can be baked from floor cells
	var floor_count: int = 0
	for room in rooms:
		for placement in room.get("structural_placements", []):
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id in FLOOR_MODULES:
				floor_count += 1
	if floor_count < 3:
		push_error("START_SCENARIO FAIL only %d floor cells, need >=3" % floor_count)
		quit(1)
		return

	var nav_source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	for room in rooms:
		for placement in room.get("structural_placements", []):
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in FLOOR_MODULES:
				continue
			var pos: Array = placement.get("world_position", placement.get("position", [0, 0, 0]))
			if pos.size() < 3:
				continue
			var center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
			var half: float = CELL_SIZE * 0.5
			nav_source.add_faces(PackedVector3Array([
				center + Vector3(-half, 0, -half),
				center + Vector3(half, 0, -half),
				center + Vector3(half, 0, half),
				center + Vector3(-half, 0, -half),
				center + Vector3(half, 0, half),
				center + Vector3(-half, 0, half),
			]), Transform3D())

	var nav_mesh: NavigationMesh = NavigationMesh.new()
	NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, nav_source)
	if nav_mesh.get_polygon_count() == 0:
		push_error("START_SCENARIO FAIL nav mesh baked 0 polygons from %d floor cells" % floor_count)
		quit(1)
		return

	# Test 5: Life boat layout generation
	var LifeBoatScript := preload("res://scripts/procgen/life_boat.gd")
	var lb_builder := LifeBoatScript.new()
	var lb_layout: Dictionary = lb_builder.build_layout()
	var lb_rooms: Array = lb_layout.get("rooms", [])
	if lb_rooms.size() != 3:
		push_error("START_SCENARIO FAIL life boat expected 3 rooms, got %d" % lb_rooms.size())
		quit(1)
		return

	# Clean up temp files
	DirAccess.remove_absolute(layout_path)
	DirAccess.remove_absolute(gameplay_path)

	print("START_SCENARIO PASS derelict=%d_rooms life_boat=3_rooms floor_cells=%d nav_polys=%d objectives=%d" % [
		rooms.size(), floor_count, nav_mesh.get_polygon_count(), gameplay.get("objectives", []).size()
	])
	quit(0)
