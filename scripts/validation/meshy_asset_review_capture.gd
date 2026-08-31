extends SceneTree
## Headless, locked-isometric capture for one temporary Meshy review overlay.
## The host runner supplies --seed, --lighting, and --output. The staged GLB
## is always loaded from res://assets/_review/meshy/<asset_id>/cleaned.glb.

const HARNESS_SCENE: String = "res://scenes/validation/meshy_asset_review_harness.tscn"
const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript: GDScript = preload("res://scripts/procgen/ship_generator.gd")
const ThreatPlaceholderRendererScript: GDScript = preload("res://scripts/tools/threat_placeholder_renderer.gd")
const GameplayPropFactoryScript: GDScript = preload("res://scripts/placement/gameplay_prop_factory.gd")

const IMAGE_SIZE: Vector2i = Vector2i(1600, 900)
const REVIEW_ROOT: String = "res://assets/_review/meshy/"
const SEEDS: Array[int] = [42, 777]
const LIGHTING_MODES: Array[String] = ["normal", "emergency", "dark"]

var review_camera: Camera3D
var key_light: DirectionalLight3D
var fill_light: OmniLight3D
var review_environment: WorldEnvironment
var generated_root: Node3D
var harness: Node3D
var capture_viewport: SubViewport

var seed_value: int = 42
var lighting_mode: String = "normal"
var output_path: String = ""
var asset_id: String = ""
var asset_category: String = ""
var generated_derelict: Node3D


func _initialize() -> void:
	capture_viewport = SubViewport.new()
	capture_viewport.size = IMAGE_SIZE
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.own_world_3d = true
	root.add_child(capture_viewport)
	var harness_scene: PackedScene = load(HARNESS_SCENE) as PackedScene
	if harness_scene == null:
		_fail("review harness scene is missing")
		return
	harness = harness_scene.instantiate() as Node3D
	if harness == null:
		_fail("review harness scene root is not Node3D")
		return
	capture_viewport.add_child(harness)
	review_camera = harness.get_node_or_null("ReviewCamera") as Camera3D
	key_light = harness.get_node_or_null("ReviewKeyLight") as DirectionalLight3D
	fill_light = harness.get_node_or_null("ReviewFillLight") as OmniLight3D
	review_environment = harness.get_node_or_null("ReviewEnvironment") as WorldEnvironment
	generated_root = harness.get_node_or_null("GeneratedDerelictRoot") as Node3D
	if review_camera == null or key_light == null or fill_light == null or review_environment == null or generated_root == null:
		_fail("review harness scene is missing required nodes")
		return

	var parsed: Dictionary = _parse_user_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	seed_value = int(parsed["seed"])
	lighting_mode = str(parsed["lighting"])
	output_path = _resolve_output_path(str(parsed["output"]))
	asset_id = OS.get_environment("MESHY_REVIEW_ASSET_ID").strip_edges()
	asset_category = OS.get_environment("MESHY_REVIEW_ASSET_CATEGORY").strip_edges()
	if asset_id.is_empty():
		_fail("MESHY_REVIEW_ASSET_ID is required")
		return
	if not SEEDS.has(seed_value):
		_fail("seed must be 42 or 777")
		return
	if not LIGHTING_MODES.has(lighting_mode):
		_fail("lighting must be normal, emergency, or dark")
		return
	if output_path.is_empty():
		_fail("output path is required")
		return

	capture_viewport.size = IMAGE_SIZE
	_configure_lighting()
	seed(seed_value)
	if not _load_derelict():
		return
	if not _mount_staged_asset():
		return
	_fit_locked_isometric_camera()
	call_deferred("_capture_after_frames")


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"seed": 42, "lighting": "normal", "output": ""}
	var seen: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if token != "--seed" and token != "--lighting" and token != "--output":
			return {"error": "unknown argument %s" % token}
		if seen.has(token):
			return {"error": "duplicate argument %s" % token}
		seen[token] = true
		if index + 1 >= args.size():
			return {"error": "missing value for %s" % token}
		var value: String = str(args[index + 1]).strip_edges()
		if value.is_empty() or value.begins_with("--"):
			return {"error": "missing value for %s" % token}
		if token == "--seed":
			if not value.is_valid_int():
				return {"error": "seed must be an integer"}
			result["seed"] = int(value)
		elif token == "--lighting":
			result["lighting"] = value
		else:
			result["output"] = value
		index += 2
	if not seen.has("--seed") or not seen.has("--lighting") or not seen.has("--output"):
		return {"error": "--seed, --lighting, and --output are required"}
	return result


func _resolve_output_path(raw_path: String) -> String:
	var candidate: String = raw_path.strip_edges()
	if candidate.begins_with("res://"):
		return ProjectSettings.globalize_path(candidate).simplify_path()
	if not candidate.is_absolute_path():
		return ProjectSettings.globalize_path("res://" + candidate.trim_prefix("./")).simplify_path()
	return candidate.simplify_path()


func _configure_lighting() -> void:
	var environment: Environment = review_environment.environment
	if environment == null:
		_fail("review environment is missing")
		return
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.004, 0.010, 0.035, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	match lighting_mode:
		"normal":
			key_light.light_color = Color(0.72, 0.84, 1.0)
			key_light.light_energy = 1.5
			fill_light.light_color = Color(0.16, 0.36, 0.90)
			fill_light.light_energy = 4.0
			environment.ambient_light_color = Color(0.12, 0.20, 0.40)
			environment.ambient_light_energy = 0.72
		"emergency":
			key_light.light_color = Color(1.0, 0.22, 0.10)
			key_light.light_energy = 0.65
			fill_light.light_color = Color(0.95, 0.04, 0.015)
			fill_light.light_energy = 5.0
			environment.ambient_light_color = Color(0.22, 0.035, 0.02)
			environment.ambient_light_energy = 0.38
		"dark":
			key_light.light_color = Color(0.18, 0.28, 0.55)
			key_light.light_energy = 0.18
			fill_light.light_color = Color(0.04, 0.18, 0.45)
			fill_light.light_energy = 1.1
			environment.ambient_light_color = Color(0.025, 0.045, 0.10)
			environment.ambient_light_energy = 0.16


func _load_derelict() -> bool:
	var archetype: Dictionary = {}
	var archetype_path: String = "res://data/procgen/archetypes/derelict.json"
	if FileAccess.file_exists(archetype_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(archetype_path))
		if parsed is Dictionary:
			archetype = (parsed as Dictionary).duplicate(true)
	if archetype.is_empty():
		archetype = {
			"name": "Derelict",
			"type": "derelict",
			"role_weights": {"cargo": 4, "corridor": 3, "bridge": 3, "dock": 1},
			"guaranteed_roles": [],
			"max_duplicates": 3,
		}
	# The production environment is still used; this avoids an optional dock
	# guarantee warning on templates which cannot host the dock role.
	archetype["guaranteed_roles"] = []
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.WRECKED,
		seed_value,
	)
	blueprint.room_count_range = Vector2i(5, 10)
	var generator = ShipGeneratorScript.new()
	generator.configure_run_context("breach_field", "standard")
	generated_derelict = generator.generate(blueprint, archetype)
	if generated_derelict == null:
		_fail("ShipGenerator returned null for breach_field")
		return false
	generated_derelict.name = "GeneratedDerelict"
	generated_root.add_child(generated_derelict)
	return true


func _mount_staged_asset() -> bool:
	var staged_path: String = REVIEW_ROOT + asset_id + "/cleaned.glb"
	if not FileAccess.file_exists(staged_path):
		_fail("staged GLB is missing: %s" % staged_path)
		return false
	var visual: Node3D = _load_glb(staged_path)
	if visual == null:
		return false
	var mount_position: Vector3 = _mount_position()
	var mount: Node3D
	if asset_category.begins_with("threat"):
		mount = ThreatPlaceholderRendererScript.build_placeholder(asset_id, [], mount_position)
		mount.name = "StagedThreat_%s" % asset_id
	elif asset_category == "gameplay_prop" or asset_category.begins_with("prop"):
		mount = GameplayPropFactoryScript.build(asset_id, mount_position)
		mount.name = "StagedVisualOnlyProp_%s" % asset_id
	else:
		mount = Node3D.new()
		mount.position = mount_position
		mount.name = "StagedVisualOnlyAsset_%s" % asset_id
	if mount == null:
		_fail("could not create asset mount seam")
		visual.free()
		return false
	generated_root.add_child(mount)
	visual.position = Vector3.ZERO
	mount.add_child(visual)
	return true


func _load_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error: Error = document.append_from_file(ProjectSettings.globalize_path(path), state)
	if append_error != OK:
		_fail("could not load staged GLB error=%d" % append_error)
		return null
	var generated: Node = document.generate_scene(state)
	if generated == null or not (generated is Node3D):
		if generated != null:
			generated.free()
		_fail("staged GLB did not generate a Node3D")
		return null
	return generated as Node3D


func _mount_position() -> Vector3:
	var center: Vector3 = Vector3.ZERO
	if generated_derelict != null and generated_derelict.has_method("get_layout_copy"):
		var layout: Dictionary = generated_derelict.get_layout_copy()
		var plan_variant: Variant = layout.get("structural_plan", {})
		if plan_variant is Dictionary:
			var positions: Array[Vector3] = []
			var plan: Dictionary = plan_variant
			var occupancy: Variant = plan.get("occupancy", {})
			if occupancy is Dictionary:
				for record_variant in (occupancy as Dictionary).values():
					var position: Vector3 = _read_position(record_variant.get("position", null) if record_variant is Dictionary else null)
					if position != Vector3.INF:
						positions.append(position)
			if not positions.is_empty():
					for position in positions:
						center += position
					center /= float(positions.size())
	return center + Vector3(0.0, 0.9, 0.0)


func _read_position(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	if raw is String:
		var text: String = str(raw).strip_edges()
		text = text.trim_prefix("Vector3(").trim_suffix(")")
		var parts: PackedStringArray = text.split(",")
		if parts.size() >= 3 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float() and parts[2].strip_edges().is_valid_float():
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.INF


func _fit_locked_isometric_camera() -> void:
	var target: Vector3 = generated_derelict.position if generated_derelict != null else Vector3.ZERO
	review_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	review_camera.size = 18.0
	var camera_position := target + Vector3(16.0, 14.0, 16.0)
	review_camera.look_at_from_position(camera_position, target, Vector3.UP)
	review_camera.current = true


func _capture_after_frames() -> void:
	for _frame_index in 6:
		await process_frame
	var image: Image = capture_viewport.get_texture().get_image()
	if image == null or image.get_size() != IMAGE_SIZE:
		_fail("viewport capture was not 1600x900")
		return
	var output_parent: String = output_path.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_parent)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create capture output directory")
		return
	var save_error: Error = image.save_png(output_path)
	if save_error != OK:
		_fail("PNG capture failed error=%d" % save_error)
		return
	print("MESHY RUNTIME CAPTURE PASS seed=%d lighting=%s camera_transform=locked-isometric output=%s" % [seed_value, lighting_mode, output_path])
	quit(0)


func _fail(reason: String) -> void:
	push_error("MESHY RUNTIME CAPTURE FAIL: " + reason)
	quit(1)
