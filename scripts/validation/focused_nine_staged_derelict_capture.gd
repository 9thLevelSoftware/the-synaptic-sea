extends Node3D

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")

const STAGED_IMPORT_PREFIX := "res://assets/imported/structural/ship_structural_v0/"
const STAGED_WRAPPER_PREFIX := "res://scenes/wrappers/structural/ship_structural_v0/"
const STAGED_INPUT_COUNT := 17
const IMAGE_SIZE := Vector2i(1600, 900)
const DEFAULT_SEED := 17
const IMAGE_NAME := "focused-nine-staged-derelict.png"

@onready var ship_camera: Camera3D = $DerelictCamera

var seed_value: int = DEFAULT_SEED
var output_dir: String = "artifacts/validation-previews/focused-nine"
var staged_input_count: int = STAGED_INPUT_COUNT
var generated_root: Node3D


func _ready() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("non-headless capture is required")
		return
	_parse_user_arguments()
	get_window().size = IMAGE_SIZE
	var layout_blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.WRECKED, seed_value)
	layout_blueprint.room_count_range = Vector2i(5, 8)

	# Exercise the current production ShipGenerator layout path first. This is
	# deliberately a real deterministic layout generation, not a hand-written
	# room list. The small visual shell below uses StructuralPlacer because the
	# focused-nine staged contract covers its derelict module vocabulary.
	var ship_generator = ShipGeneratorScript.new()
	var runtime_archetype := {
		"name": "Derelict",
		"type": "derelict",
		"guaranteed_roles": [],
	}
	var production_layout: Dictionary = ship_generator.generate_layout(layout_blueprint, runtime_archetype)
	if production_layout.is_empty() or not production_layout.has("rooms"):
		_fail("ShipGenerator returned no derelict layout")
		return

	# Derelict mode is intentionally constrained to the staged focused-nine
	# structural vocabulary. StructuralPlacer still owns the room graph,
	# connectivity, placement, and wrapper instantiation.
	var derelict_archetype := {
		"name": "Derelict",
		"type": "derelict",
		"role_weights": {
			"compartment": 100,
			"corridor": 0,
			"bay": 0,
			"quarters": 0,
			"hangar": 0,
		},
		"guaranteed_roles": ["dock"],
		"max_duplicates": 8,
	}
	var graph_generator = RoomGraphGeneratorScript.new()
	var graph = graph_generator.generate(layout_blueprint, derelict_archetype)
	if graph == null or graph.rooms.size() < 5 or graph.rooms.size() > 8:
		_fail("deterministic derelict graph was not 5-8 rooms")
		return
	if not _graph_has_role(graph, "dock"):
		_fail("derelict graph did not contain the required dock")
		return

	var placer = StructuralPlacerScript.new()
	generated_root = placer.place_structure(graph, seed_value, "")
	if generated_root == null:
		_fail("StructuralPlacer returned no generated root")
		return
	generated_root.name = "GeneratedDerelict"
	$GeneratedShipRoot.add_child(generated_root)
	_decorate_from_generated_rooms(generated_root)
	_add_generated_labels(graph, generated_root)
	_fit_camera(generated_root)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(graph.rooms.size())


func _parse_user_arguments() -> void:
	var user_args := OS.get_cmdline_user_args()
	var index := 0
	while index < user_args.size():
		var argument := str(user_args[index])
		if argument == "--seed" and index + 1 < user_args.size():
			seed_value = int(user_args[index + 1])
			index += 2
			continue
		if argument == "--output-dir" and index + 1 < user_args.size():
			output_dir = str(user_args[index + 1]).trim_suffix("/")
			index += 2
			continue
		if argument == "--staged-input-count" and index + 1 < user_args.size():
			staged_input_count = int(user_args[index + 1])
			index += 2
			continue
		index += 1


func _graph_has_role(graph, wanted: String) -> bool:
	for room in graph.rooms:
		if str(room.get("role", "")) == wanted:
			return true
	return false


func _decorate_from_generated_rooms(root: Node3D) -> void:
	var wall_scene := load(STAGED_WRAPPER_PREFIX + "wall_straight_1x1.tscn") as PackedScene
	var pillar_scene := load(STAGED_WRAPPER_PREFIX + "pillar_support_1x1.tscn") as PackedScene
	var pressure_scene := load(STAGED_WRAPPER_PREFIX + "pressure_door_1x1.tscn") as PackedScene
	if wall_scene == null or pillar_scene == null or pressure_scene == null:
		_fail("staged focused-nine production wrapper load failed")
		return

	for room_variant in root.get_children():
		if not (room_variant is Node3D):
			continue
		var room := room_variant as Node3D
		var floor_nodes: Array[Node3D] = []
		for child_variant in room.get_children():
			if child_variant is Node3D and str(child_variant.name).begins_with("floor_1x1"):
				floor_nodes.append(child_variant as Node3D)
		if floor_nodes.is_empty():
			continue

		# Decoration follows the generated floor instances; it does not encode
		# room coordinates or a fixed layout. The staged wall/pillar identities
		# therefore remain visibly tied to the actual runtime graph.
		for floor_node in floor_nodes:
			var z := floor_node.position.z
			var north := wall_scene.instantiate() as Node3D
			north.position = Vector3(0.0, 1.55, z - 2.0)
			room.add_child(north)
			var south := wall_scene.instantiate() as Node3D
			south.position = Vector3(0.0, 1.55, z + 2.0)
			south.rotation.y = PI
			room.add_child(south)
			var pillar := pillar_scene.instantiate() as Node3D
			pillar.position = Vector3(-1.55, 1.35, z - 1.55)
			room.add_child(pillar)

		if str(room.name).begins_with("dock"):
			var pressure := pressure_scene.instantiate() as Node3D
			pressure.position = Vector3(0.0, 0.0, -2.05)
			room.add_child(pressure)


func _add_generated_labels(graph, root: Node3D) -> void:
	var room_index := 0
	for room_variant in root.get_children():
		if not (room_variant is Node3D) or room_index >= graph.rooms.size():
			continue
		var room := room_variant as Node3D
		var label := Label3D.new()
		label.name = "GeneratedRoomLabel_%02d" % room_index
		label.text = "%s  %s" % [str(graph.rooms[room_index].get("role", "")), str(graph.rooms[room_index].get("id", ""))]
		label.position = Vector3(0.0, 4.2, 0.0)
		label.font_size = 32
		label.outline_size = 8
		label.modulate = Color(0.50, 0.86, 1.0, 1.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		room.add_child(label)
		room_index += 1

	var title := Label3D.new()
	title.name = "StagedFocusedNineTitle"
	title.text = "STAGED FOCUSED-NINE  //  DERELICT"
	title.font_size = 42
	title.outline_size = 10
	title.modulate = Color(0.72, 0.90, 1.0, 1.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(0.0, 7.0, 0.0)
	root.add_child(title)


func _fit_camera(root: Node3D) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for room_variant in root.get_children():
		if not (room_variant is Node3D):
			continue
		var room := room_variant as Node3D
		min_x = min(min_x, room.position.x - 3.0)
		max_x = max(max_x, room.position.x + 3.0)
		min_z = min(min_z, room.position.z - 3.0)
		max_z = max(max_z, room.position.z + 11.0)
	if min_x == INF:
		_fail("generated derelict has no room bounds")
		return
	var center := Vector3((min_x + max_x) * 0.5, 1.0, (min_z + max_z) * 0.5)
	var span: float = maxf(max_x - min_x, max_z - min_z)
	ship_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	ship_camera.size = max(16.0, span * 0.94)
	ship_camera.position = center + Vector3(span * 0.74, span * 0.92, span * 0.74)
	ship_camera.look_at(center, Vector3.UP)


func _capture(room_count: int) -> void:
	var output_path := ProjectSettings.globalize_path("res://" + output_dir.trim_prefix("res://") + "/" + IMAGE_NAME)
	var output_parent := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(output_parent)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_size() != IMAGE_SIZE:
		_fail("viewport capture was not 1600x900")
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		_fail("PNG capture failed with error %s" % save_error)
		return

	var inspection := _inspect_tree(generated_root)
	if int(inspection["wrapper_count"]) <= 0:
		_fail("tree inspection found no generated staged wrappers")
		return
	if int(inspection["staged_glb_count"]) <= 0:
		_fail("tree inspection found no staged GLB identities")
		return
	if int(inspection["live_reference_count"]) != 0:
		_fail("tree inspection found live imported visual references")
		return
	print(
		"%sseed=%d rooms=%d wrappers=%d staged=%d output=res://%s/%s" % [
			"FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS ",
			seed_value,
			room_count,
			int(inspection["wrapper_count"]),
			staged_input_count,
			output_dir.trim_prefix("res://"),
			IMAGE_NAME,
		]
	)
	get_tree().quit(0)


func _inspect_tree(node: Node) -> Dictionary:
	var result := {"wrapper_count": 0, "staged_glb_count": 0, "live_reference_count": 0}
	var scene_path := node.get_scene_file_path()
	if scene_path.begins_with(STAGED_WRAPPER_PREFIX):
		result["wrapper_count"] = int(result["wrapper_count"]) + 1
	if scene_path.ends_with(".glb"):
		if scene_path.begins_with(STAGED_IMPORT_PREFIX):
			result["staged_glb_count"] = int(result["staged_glb_count"]) + 1
		else:
			result["live_reference_count"] = int(result["live_reference_count"]) + 1
	for child in node.get_children():
		var child_result := _inspect_tree(child)
		for key in result.keys():
			result[key] = int(result[key]) + int(child_result[key])
	return result


func _fail(message: String) -> void:
	push_error("FOCUSED_NINE_STAGED_DERELICT_CAPTURE FAIL: " + message)
	get_tree().quit(1)
