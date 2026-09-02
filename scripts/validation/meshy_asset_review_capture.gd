extends SceneTree
## Headless, locked-isometric capture for one temporary Meshy review overlay.
## The host runner supplies every identity and output argument explicitly. The
## staged GLB is always loaded from res://assets/_review/meshy/<asset_id>/cleaned.glb.

const HARNESS_SCENE: String = "res://scenes/validation/meshy_asset_review_harness.tscn"
const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript: GDScript = preload("res://scripts/procgen/ship_generator.gd")
const ThreatPlaceholderRendererScript: GDScript = preload("res://scripts/tools/threat_placeholder_renderer.gd")
const GameplayPropFactoryScript: GDScript = preload("res://scripts/placement/gameplay_prop_factory.gd")

const IMAGE_SIZE: Vector2i = Vector2i(1600, 900)
const REVIEW_ROOT: String = "res://assets/_review/meshy/"
const SEEDS: Array[int] = [42, 777]
const LIGHTING_MODES: Array[String] = ["normal", "emergency", "dark"]
const STAGED_SAMPLE_STEP_X: int = 25
const STAGED_SAMPLE_STEP_Y: int = 25
const STAGED_SAMPLE_MAX: int = 2304
const CONTEXTUAL_REFERENCE_MIN: int = 2
const CONTEXTUAL_CHANGED_MIN: int = 2
const CONTEXTUAL_CHANGED_FRACTION_MIN: float = 0.5
const CONTEXTUAL_RGB_DELTA_MIN: float = 0.02
const CONTEXTUAL_RGB_DELTA_MAX: float = 1.0

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
var staged_visual_root: Node3D
var staged_silhouette_image: Image
var staged_camera_target: Vector3 = Vector3.ZERO
var staged_camera_size: float = 0.0


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
		_fail("review harness is missing required nodes")
		return

	var parsed: Dictionary = _parse_user_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	seed_value = int(parsed["seed"])
	lighting_mode = str(parsed["lighting"])
	asset_id = str(parsed["asset_id"])
	asset_category = str(parsed["category"])
	output_path = _resolve_output_path(str(parsed["output"]))
	if asset_id.is_empty() or asset_id.find("/") >= 0 or asset_id.find("\\") >= 0 or asset_id.find("..") >= 0:
		_fail("asset-id must be a single safe identifier")
		return
	if asset_category.is_empty() or asset_category.find("/") >= 0 or asset_category.find("\\") >= 0 or asset_category.find("..") >= 0:
		_fail("category must be a single value")
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
	capture_viewport.transparent_bg = true
	_configure_lighting()
	seed(seed_value)
	if not _load_derelict():
		return
	if not _mount_staged_asset():
		return
	_apply_local_cutaway()
	if not _fit_locked_isometric_camera():
		return
	call_deferred("_capture_after_frames")


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"seed": 42, "lighting": "normal", "asset_id": "", "category": "", "output": ""}
	var seen: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if token != "--seed" and token != "--lighting" and token != "--asset-id" and token != "--category" and token != "--output":
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
		elif token == "--asset-id":
			result["asset_id"] = value
		elif token == "--category":
			result["category"] = value
		else:
			result["output"] = value
		index += 2
	if not seen.has("--seed") or not seen.has("--lighting") or not seen.has("--asset-id") or not seen.has("--category") or not seen.has("--output"):
		return {"error": "--asset-id, --category, --seed, --lighting, and --output are required"}
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
	if not mount_position.is_finite():
		_fail("no valid occupied cell exists")
		return false
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
	_hide_existing_mount_visuals(mount)
	visual.position = Vector3.ZERO
	mount.add_child(visual)
	staged_visual_root = visual
	return true


func _hide_existing_mount_visuals(mount: Node3D) -> void:
	# Keep the wrapper/factory seam (collision, metadata, node path) but hide
	# catalog fallback Mesh / CatalogMesh children so promotion-gating captures
	# show only the staged candidate.
	for child in mount.get_children():
		if child is Node3D:
			(child as Node3D).visible = false


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
	var selected_position: Vector3 = Vector3.INF
	var selected_score: float = -INF
	if generated_derelict != null and generated_derelict.has_method("get_layout_copy"):
		var layout: Dictionary = generated_derelict.get_layout_copy()
		var plan_variant: Variant = layout.get("structural_plan", {})
		if plan_variant is Dictionary:
			var plan: Dictionary = plan_variant
			var occupancy: Variant = plan.get("occupancy", {})
			if occupancy is Dictionary:
				for record_variant in (occupancy as Dictionary).values():
					var position: Vector3 = _read_position(record_variant.get("position", null) if record_variant is Dictionary else null)
					if position == Vector3.INF:
						continue
					var score: float = position.x + position.z
					if selected_position == Vector3.INF or score > selected_score or (score == selected_score and _mount_position_precedes(position, selected_position)):
						selected_position = position
						selected_score = score
		if selected_position != Vector3.INF:
			return selected_position + Vector3(0.0, 0.9, 0.0)
	return Vector3.INF


func _mount_position_precedes(candidate: Vector3, current: Vector3) -> bool:
	if not is_equal_approx(candidate.x, current.x):
		return candidate.x > current.x
	if not is_equal_approx(candidate.z, current.z):
		return candidate.z > current.z
	return candidate.y > current.y


func _read_position(raw: Variant) -> Vector3:
	if raw is Vector3:
		var vector: Vector3 = raw
		return vector if vector.is_finite() else Vector3.INF
	if raw is Array and (raw as Array).size() == 3:
		var values: Array = raw
		var components: Array[float] = []
		for value in values:
			if value is bool or (not value is int and not value is float):
				return Vector3.INF
			var component: float = float(value)
			if not is_finite(component):
				return Vector3.INF
			components.append(component)
		return Vector3(components[0], components[1], components[2])
	if raw is String:
		var text: String = str(raw).strip_edges()
		if text.begins_with("Vector3(") and text.ends_with(")"):
			text = text.trim_prefix("Vector3(").trim_suffix(")")
		elif text.begins_with("(") and text.ends_with(")"):
			text = text.trim_prefix("(").trim_suffix(")")
		else:
			return Vector3.INF
		var parts: PackedStringArray = text.split(",")
		if parts.size() != 3:
			return Vector3.INF
		var parsed_components: Array[float] = []
		for part in parts:
			var component_text: String = part.strip_edges()
			if not component_text.is_valid_float():
				return Vector3.INF
			var component: float = float(component_text)
			if not is_finite(component):
				return Vector3.INF
			parsed_components.append(component)
		return Vector3(parsed_components[0], parsed_components[1], parsed_components[2])
	return Vector3.INF


func _apply_local_cutaway() -> void:
	if generated_derelict == null or staged_visual_root == null:
		return
	var staged_mount: Node3D = staged_visual_root.get_parent_node_3d()
	if staged_mount == null:
		return
	var mount_position: Vector3 = staged_mount.position
	_apply_local_cutaway_recursive(
		generated_derelict,
		mount_position,
		Transform3D.IDENTITY,
	)


func _apply_local_cutaway_recursive(
	node: Node,
	mount_position: Vector3,
	parent_transform: Transform3D,
) -> void:
	var node_transform: Transform3D = parent_transform
	if node is Node3D:
		var wrapper: Node3D = node as Node3D
		node_transform = parent_transform * wrapper.transform
		var wrapper_position: Vector3 = node_transform.origin
		var horizontal: Vector2 = Vector2(
			wrapper_position.x - mount_position.x,
			wrapper_position.z - mount_position.z,
		)
		var distance: float = horizontal.length()
		var name: String = wrapper.name
		if name.begins_with("Ceiling_") and distance <= 2.0:
			wrapper.visible = false
		elif name.begins_with("StructuralEdge_") and distance <= 3.0 and horizontal.dot(Vector2(1.0, 1.0).normalized()) > 0.0:
			wrapper.visible = false
	for child in node.get_children():
		_apply_local_cutaway_recursive(child as Node, mount_position, node_transform)


func _expand_visual_bounds(node: Node, bounds: Array, parent_transform: Transform3D) -> void:
	var world_transform: Transform3D = parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var local_bounds: AABB = mesh_instance.get_aabb()
		var corners: Array[Vector3] = [
			local_bounds.position,
			local_bounds.position + Vector3(local_bounds.size.x, 0.0, 0.0),
			local_bounds.position + Vector3(0.0, local_bounds.size.y, 0.0),
			local_bounds.position + Vector3(0.0, 0.0, local_bounds.size.z),
			local_bounds.position + Vector3(local_bounds.size.x, local_bounds.size.y, 0.0),
			local_bounds.position + Vector3(local_bounds.size.x, 0.0, local_bounds.size.z),
			local_bounds.position + Vector3(0.0, local_bounds.size.y, local_bounds.size.z),
			local_bounds.end,
		]
		for corner in corners:
			var world_point: Vector3 = world_transform * corner
			if not bounds[0]:
				bounds[1] = AABB(world_point, Vector3.ZERO)
				bounds[0] = true
			else:
				bounds[1] = (bounds[1] as AABB).expand(world_point)
	for child in node.get_children():
		_expand_visual_bounds(child as Node, bounds, world_transform)


func _harness_transform(node: Node) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != capture_viewport:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _fit_locked_isometric_camera() -> bool:
	if staged_visual_root == null:
		_fail("staged visual root is missing")
		return false
	var bounds: Array = [false, AABB()]
	var visual_parent: Node3D = staged_visual_root.get_parent_node_3d()
	var parent_transform: Transform3D = _harness_transform(visual_parent) if visual_parent != null else Transform3D.IDENTITY
	_expand_visual_bounds(staged_visual_root, bounds, parent_transform)
	if not bounds[0]:
		_fail("staged visual has no mesh geometry")
		return false
	var visual_bounds: AABB = bounds[1]
	if visual_bounds.size.length() <= 0.0001:
		_fail("staged visual bounds are empty")
		return false
	staged_camera_target = visual_bounds.position + visual_bounds.size * 0.5
	var locked_direction: Vector3 = Vector3(16.0, 14.0, 16.0).normalized()
	var camera_distance: float = max(visual_bounds.size.length() * 2.5, 4.0)
	if camera_distance <= 4.0:
		camera_distance = 4.00001
	var camera_position: Vector3 = staged_camera_target + locked_direction * camera_distance
	var camera_parent: Node3D = review_camera.get_parent_node_3d()
	var camera_parent_transform: Transform3D = _harness_transform(camera_parent) if camera_parent != null else Transform3D.IDENTITY
	var camera_parent_inverse: Transform3D = camera_parent_transform.affine_inverse()
	review_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	review_camera.look_at_from_position(camera_parent_inverse * camera_position, camera_parent_inverse * staged_camera_target, Vector3.UP)
	var camera_inverse: Transform3D = review_camera.transform.affine_inverse() * camera_parent_inverse
	var projected_horizontal: float = 0.0
	var projected_vertical: float = 0.0
	var corners: Array[Vector3] = [
		visual_bounds.position,
		visual_bounds.position + Vector3(visual_bounds.size.x, 0.0, 0.0),
		visual_bounds.position + Vector3(0.0, visual_bounds.size.y, 0.0),
		visual_bounds.position + Vector3(0.0, 0.0, visual_bounds.size.z),
		visual_bounds.position + Vector3(visual_bounds.size.x, visual_bounds.size.y, 0.0),
		visual_bounds.position + Vector3(visual_bounds.size.x, 0.0, visual_bounds.size.z),
		visual_bounds.position + Vector3(0.0, visual_bounds.size.y, visual_bounds.size.z),
		visual_bounds.end,
	]
	for corner in corners:
		var camera_point: Vector3 = camera_inverse * corner
		projected_horizontal = max(projected_horizontal, abs(camera_point.x))
		projected_vertical = max(projected_vertical, abs(camera_point.y))
	var aspect_ratio: float = float(IMAGE_SIZE.x) / float(IMAGE_SIZE.y)
	var required_vertical_size: float = projected_vertical * 2.0
	var required_horizontal_size: float = projected_horizontal * 2.0 / aspect_ratio
	staged_camera_size = max(max(required_vertical_size, required_horizontal_size) * 1.15, 1.5)
	review_camera.size = staged_camera_size
	review_camera.current = true
	return true


func _has_visible_variance(image: Image) -> bool:
	var minimum: float = 1.0
	var maximum: float = 0.0
	var opaque_count: int = 0
	var sample_count: int = 0
	for y in range(0, IMAGE_SIZE.y, max(1, IMAGE_SIZE.y / 18)):
		for x in range(0, IMAGE_SIZE.x, max(1, IMAGE_SIZE.x / 32)):
			var pixel: Color = image.get_pixel(x, y)
			var alpha: float = pixel.a
			if alpha >= 0.05:
				opaque_count += 1
			var luminance: float = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
			minimum = min(minimum, luminance)
			maximum = max(maximum, luminance)
			sample_count += 1
	return opaque_count >= max(2, sample_count / 8) and maximum - minimum >= 0.004


func _staged_visibility_evidence(image: Image) -> Dictionary:
	if image == null or image.get_size() != IMAGE_SIZE:
		return {"pass": false, "opaque_pixels": 0, "luma_range": 0.0}
	var minimum: float = 1.0
	var maximum: float = 0.0
	var opaque_count: int = 0
	var sample_count: int = 0
	var step_x: int = STAGED_SAMPLE_STEP_X
	var step_y: int = STAGED_SAMPLE_STEP_Y
	for y in range(0, IMAGE_SIZE.y, step_y):
		for x in range(0, IMAGE_SIZE.x, step_x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= 0.05:
				opaque_count += 1
			var luminance: float = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
			minimum = min(minimum, luminance)
			maximum = max(maximum, luminance)
			sample_count += 1
	var luma_range: float = maximum - minimum
	return {
		"pass": opaque_count >= 2 and sample_count > 0 and luma_range >= 0.004,
		"opaque_pixels": opaque_count,
		"luma_range": luma_range,
	}


func _capture_staged_visibility() -> Dictionary:
	staged_silhouette_image = null
	var staged_mount: Node3D = staged_visual_root.get_parent_node_3d() if staged_visual_root != null else null
	var hidden_nodes: Array = []
	for child in generated_root.get_children():
		if child is Node3D and child != staged_mount:
			var node: Node3D = child as Node3D
			hidden_nodes.append({"node": node, "visible": node.visible})
			node.visible = false
	var hidden_mount_children: Array = []
	if staged_mount != null:
		for child in staged_mount.get_children():
			if child is Node3D and child != staged_visual_root:
				var node: Node3D = child as Node3D
				hidden_mount_children.append({"node": node, "visible": node.visible})
				node.visible = false
	var previous_environment: Environment = review_environment.environment
	review_environment.environment = null
	for _frame_index in 6:
		await process_frame
	var staged_image: Image = capture_viewport.get_texture().get_image()
	staged_silhouette_image = staged_image
	var evidence: Dictionary = _staged_visibility_evidence(staged_image)
	for item in hidden_mount_children:
		var mount_child: Node3D = item["node"] as Node3D
		mount_child.visible = bool(item["visible"])
	for item in hidden_nodes:
		var hidden_node: Node3D = item["node"] as Node3D
		hidden_node.visible = bool(item["visible"])
	review_environment.environment = previous_environment
	return evidence


func _contextual_visibility_evidence(reference_image: Image, final_image: Image) -> Dictionary:
	if staged_silhouette_image == null or reference_image == null or final_image == null:
		return {"pass": false, "reference_pixels": 0, "changed_pixels": 0, "max_delta": 0.0}
	if staged_silhouette_image.get_size() != IMAGE_SIZE or reference_image.get_size() != IMAGE_SIZE or final_image.get_size() != IMAGE_SIZE:
		return {"pass": false, "reference_pixels": 0, "changed_pixels": 0, "max_delta": 0.0}
	var reference_pixels: int = 0
	var changed_pixels: int = 0
	var max_delta: float = 0.0
	for y in range(0, IMAGE_SIZE.y, STAGED_SAMPLE_STEP_Y):
		for x in range(0, IMAGE_SIZE.x, STAGED_SAMPLE_STEP_X):
			if staged_silhouette_image.get_pixel(x, y).a < 0.05:
				continue
			reference_pixels += 1
			var reference_pixel: Color = reference_image.get_pixel(x, y)
			var final_pixel: Color = final_image.get_pixel(x, y)
			var delta: float = max(
				max(abs(final_pixel.r - reference_pixel.r), abs(final_pixel.g - reference_pixel.g)),
				abs(final_pixel.b - reference_pixel.b),
			)
			max_delta = max(max_delta, delta)
			if delta >= CONTEXTUAL_RGB_DELTA_MIN:
				changed_pixels += 1
	var pass_gate: bool = (
			reference_pixels >= CONTEXTUAL_REFERENCE_MIN
			and reference_pixels <= STAGED_SAMPLE_MAX
			and changed_pixels >= CONTEXTUAL_CHANGED_MIN
			and changed_pixels <= reference_pixels
			and float(changed_pixels) / float(reference_pixels) >= CONTEXTUAL_CHANGED_FRACTION_MIN
			and max_delta >= CONTEXTUAL_RGB_DELTA_MIN
			and max_delta <= CONTEXTUAL_RGB_DELTA_MAX
	)
	return {
		"pass": pass_gate,
		"reference_pixels": reference_pixels,
		"changed_pixels": changed_pixels,
		"max_delta": max_delta,
	}


func _capture_contextual_visibility() -> Dictionary:
	var staged_mount: Node3D = staged_visual_root.get_parent_node_3d() if staged_visual_root != null else null
	if staged_mount == null:
		return {"evidence": {"pass": false, "reference_pixels": 0, "changed_pixels": 0, "max_delta": 0.0}, "image": null}
	var previous_visibility: bool = staged_mount.visible
	staged_mount.visible = false
	for _frame_index in 6:
		await process_frame
	var reference_image: Image = capture_viewport.get_texture().get_image()
	staged_mount.visible = previous_visibility
	for _frame_index in 6:
		await process_frame
	var final_image: Image = capture_viewport.get_texture().get_image()
	return {
		"evidence": _contextual_visibility_evidence(reference_image, final_image),
		"reference_image": reference_image,
		"image": final_image,
	}


func _format_vector(value: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [value.x, value.y, value.z]


func _capture_after_frames() -> void:
	var staged_visibility: Dictionary = await _capture_staged_visibility()
	if staged_visibility.get("pass") != true:
		_fail("staged visual visibility evidence failed")
		return
	var contextual_capture: Dictionary = await _capture_contextual_visibility()
	var contextual_visibility: Dictionary = contextual_capture.get("evidence", {})
	if contextual_visibility.get("pass") != true:
		_fail("contextual visual visibility evidence failed")
		return
	var image: Image = contextual_capture.get("image", null)
	var reference_image: Image = contextual_capture.get("reference_image", null)
	var staged_image: Image = staged_silhouette_image
	if image == null or reference_image == null or staged_image == null:
		_fail("pixel evidence images are missing")
		return
	if image.get_size() != IMAGE_SIZE or reference_image.get_size() != IMAGE_SIZE or staged_image.get_size() != IMAGE_SIZE:
		_fail("viewport capture was not 1600x900")
		return
	if not _has_visible_variance(image):
		_fail("viewport capture was blank or near-uniform")
		return
	var output_parent: String = output_path.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_parent)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create capture output directory")
		return
	var staged_output_path: String = output_path.get_basename() + "-staged.png"
	var reference_output_path: String = output_path.get_basename() + "-reference.png"
	var staged_save_error: Error = staged_image.save_png(staged_output_path)
	if staged_save_error != OK:
		_fail("staged PNG capture failed error=%d" % staged_save_error)
		return
	var reference_save_error: Error = reference_image.save_png(reference_output_path)
	if reference_save_error != OK:
		_fail("reference PNG capture failed error=%d" % reference_save_error)
		return
	var save_error: Error = image.save_png(output_path)
	if save_error != OK:
		_fail("PNG capture failed error=%d" % save_error)
		return
	print("MESHY RUNTIME CAPTURE PASS seed=%d lighting=%s camera_position=%s camera_target=%s camera_size=%.9f staged_visibility=pass staged_opaque_pixels=%d staged_luma_range=%.9f contextual_visibility=pass contextual_reference_pixels=%d contextual_changed_pixels=%d contextual_max_delta=%.9f output=%s" % [seed_value, lighting_mode, _format_vector(review_camera.global_position), _format_vector(staged_camera_target), staged_camera_size, int(staged_visibility["opaque_pixels"]), float(staged_visibility["luma_range"]), int(contextual_visibility["reference_pixels"]), int(contextual_visibility["changed_pixels"]), float(contextual_visibility["max_delta"]), output_path])
	quit(0)


func _fail(reason: String) -> void:
	push_error("MESHY RUNTIME CAPTURE FAIL: " + reason)
	quit(1)
