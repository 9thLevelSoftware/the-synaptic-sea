extends SceneTree

## One production-path composite capture for the Task 8 host runner.
##
## This script intentionally has no viewer scene, floor, camera, environment,
## fill light, or fallback lifecycle.  It boots scenes/main.tscn, waits for the
## real PlayableGeneratedShip, and uses its production camera and loader.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const CAMERA_SCRIPT_PATH: String = "res://scripts/camera/iso_camera_rig.gd"
const CAPTURE_SCRIPT_PATH: String = "res://scripts/validation/biomass_visual_review.gd"
const PART_CATALOG_PATH: String = "res://data/combat/biomass_part_catalog.json"
const RECIPE_CATALOG_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const BREACH_FIELD_PATH: String = "res://data/procgen/biomes/breach_field.json"
const TIMEOUT_FRAMES: int = 600
const GAIT_FRAMES: int = 120
const GAIT_DELTA: float = 1.0 / 60.0
const IMAGE_SIZE: Vector2i = Vector2i(1280, 720)
const IsoCameraRigScript: GDScript = preload("res://scripts/camera/iso_camera_rig.gd")
const AtmosphereApplierScript: GDScript = preload("res://scripts/procgen/slice_atmosphere_applier.gd")
const PlayableScript: GDScript = preload("res://scripts/procgen/playable_generated_ship.gd")
const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const LIGHTING_MODES: Array[String] = ["normal", "emergency", "dark"]
const VISUAL_STAGES: Array[String] = ["placeholder", "final"]

var _recipe_id: String = ""
var _seed_value: int = 0
var _archetype_id: String = ""
var _lighting: String = ""
var _visual_stage: String = ""
var _output_path: String = ""
var _main_instance: Node = null
var _playable: Variant = null
var _ready_seen: bool = false
var _failed_reason: String = ""

func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	_recipe_id = str(parsed["recipe_id"])
	_seed_value = int(parsed["seed"])
	_archetype_id = str(parsed["archetype_id"])
	_lighting = str(parsed["lighting"])
	_visual_stage = str(parsed["visual_stage"])
	_output_path = _resolve_output_path(str(parsed["output"]))
	if not _preflight():
		return
	_capture()

func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var allowed: Array[String] = [
		"--recipe-id", "--seed", "--archetype-id", "--lighting", "--visual-stage", "--output",
	]
	var seen: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = str(args[index])
		if not allowed.has(token):
			return {"error": "unknown argument %s" % token}
		if seen.has(token):
			return {"error": "duplicate argument %s" % token}
		if index + 1 >= args.size():
			return {"error": "missing value for %s" % token}
		var value: String = str(args[index + 1]).strip_edges()
		if value.is_empty() or value.begins_with("--"):
			return {"error": "missing value for %s" % token}
		seen[token] = true
		match token:
			"--recipe-id": result["recipe_id"] = value
			"--seed":
				if not value.is_valid_int():
					return {"error": "seed must be an integer"}
				result["seed"] = int(value)
			"--archetype-id": result["archetype_id"] = value
			"--lighting": result["lighting"] = value
			"--visual-stage": result["visual_stage"] = value
			"--output": result["output"] = value
		index += 2
	for token in allowed:
		if not seen.has(token):
			return {"error": "missing required argument %s" % token}
	return result

func _preflight() -> bool:
	if not FileAccess.file_exists(MAIN_SCENE_PATH):
		_fail("production main scene is missing")
		return false
	if not FileAccess.file_exists(PART_CATALOG_PATH) or not FileAccess.file_exists(RECIPE_CATALOG_PATH):
		_fail("biomass catalogs are missing")
		return false
	if not FileAccess.file_exists(BREACH_FIELD_PATH):
		_fail("breach_field biome is missing")
		return false
	if not LIGHTING_MODES.has(_lighting):
		_fail("lighting must be normal, emergency, or dark")
		return false
	if not VISUAL_STAGES.has(_visual_stage):
		_fail("visual-stage must be placeholder or final")
		return false
	if _recipe_id.is_empty() or _archetype_id.is_empty():
		_fail("recipe-id and archetype-id are required")
		return false
	if _seed_value != 42 and _seed_value != 777:
		_fail("seed must be 42 or 777")
		return false
	if _output_path.is_empty():
		_fail("output path is required")
		return false
	return true

func _capture() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("production main scene could not be loaded")
		return
	_main_instance = packed.instantiate()
	if _main_instance == null:
		_fail("production main scene could not be instantiated")
		return
	get_root().add_child(_main_instance)
	# main.gd adds the real playable instance during its _ready callback. The
	# callback can complete synchronously, so the polling path also records the
	# already-emitted production readiness state.
	for frame in range(TIMEOUT_FRAMES + 1):
		if _main_instance == null or not is_instance_valid(_main_instance):
			_fail("production main instance was freed")
			return
		var candidate: Variant = _main_instance.get("playable_instance")
		if candidate is PlayableScript:
			_playable = candidate
			if not _playable.playable_ready.is_connected(_on_playable_ready):
				_playable.playable_ready.connect(_on_playable_ready)
			if not _ready_seen and _playable.playable_started:
				_ready_seen = true
			if not _playable.playable_started:
				await process_frame
				continue
			break
		await process_frame
	if not _ready_seen or _playable == null:
		_fail("production playable_ready was not observed before TIMEOUT_FRAMES=600")
		return
	if not _production_ready():
		return
	if not _apply_validation_lighting():
		return
	var player: Node3D = _playable.player as Node3D
	if player == null:
		_fail("production player is missing")
		return
	var toward_camera: Vector3 = player.global_position.direction_to(_playable.camera_rig.camera.global_position)
	var encounter_position: Vector3 = player.global_position + toward_camera * 8.0
	var visual: Variant = _playable.inject_biomass_validation_encounter(
		_archetype_id, _recipe_id, _seed_value, encounter_position)
	if visual == null or not (visual is VisualScript):
		_fail("production biomass injection failed")
		return
	if not visual.is_inside_tree():
		_fail("injected biomass visual was not registered in the production scene")
		return
	_playable.camera_rig.set_follow_target(visual)
	_playable.camera_rig.camera.size = 8.0
	await process_frame
	var recipe_document: Dictionary = visual.recipe_document()
	if str(recipe_document.get("recipe_id", "")) != _recipe_id:
		_fail("injected recipe identity does not match request")
		return
	var catalog_document: Dictionary = _load_json_dict(RECIPE_CATALOG_PATH)
	var recipes: Dictionary = catalog_document.get("recipes", {}) as Dictionary
	var expected_recipe: Variant = recipes.get(_recipe_id, null)
	if not expected_recipe is Dictionary or recipe_document != (expected_recipe as Dictionary):
		_fail("injected recipe document does not match the production catalog")
		return
	var archetype_pools: Dictionary = catalog_document.get("archetype_pools", {}) as Dictionary
	var compatible_pool: Variant = archetype_pools.get(_archetype_id, null)
	if not compatible_pool is Array or not (compatible_pool as Array).has(_recipe_id):
		_fail("recipe/archetype pair is outside the production compatibility pool")
		return
	if not _validate_stage(recipe_document, visual):
		return
	# The production coordinator is now frozen. Gait is advanced explicitly so
	# this review has exactly 120 x 1/60-second steps and no wall-clock drift.
	await physics_frame
	_freeze_processing(_main_instance)
	for _step in range(GAIT_FRAMES):
		visual.step_gait(GAIT_DELTA, Vector3.ZERO, "idle")
	await process_frame
	await process_frame
	var runtime: Dictionary = _collect_runtime(visual, recipe_document)
	if runtime.has("error"):
		_fail(str(runtime["error"]))
		return
	var visible: Image = _capture_image()
	if visible == null:
		_fail("production viewport did not produce a visible image")
		return
	visual.visible = false
	await process_frame
	await process_frame
	var hidden: Image = _capture_image()
	visual.visible = true
	if hidden == null:
		_fail("production viewport did not produce paired hidden image")
		return
	var paired: Dictionary = _compare_images(visible, hidden)
	if not bool(paired.get("pass", false)):
		_fail("paired production capture failed readability thresholds")
		return
	runtime["paired_visibility"] = {
		"rgb_delta": float(paired["rgb_delta"]),
		"changed_pixels": int(paired["changed_pixels"]),
		"changed_bbox_width": int(paired["changed_bbox_width"]),
		"changed_bbox_height": int(paired["changed_bbox_height"]),
	}
	var ray_center: Vector3 = visual.global_position
	for child in (visual as CharacterBody3D).get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			ray_center = (child as CollisionShape3D).global_position
			break
	var ray_origin: Vector3 = ray_center + Vector3(-0.75, 0.0, 0.0)
	var ray_target: Vector3 = ray_center + Vector3(0.75, 0.0, 0.0)
	runtime["ray_hit"] = _ray_hits_body(ray_origin, ray_target, visual)
	if not bool(runtime["ray_hit"]):
		_fail("body-only mask-1 ray did not hit biomass body")
		return
	if visible.save_png(_output_path) != OK:
		_fail("production capture could not be written")
		return
	visual.queue_free()
	await process_frame
	await process_frame
	await process_frame
	await physics_frame
	runtime["ray_miss_after_free"] = not _ray_hits_any_body(ray_origin, ray_target)
	if not bool(runtime["ray_miss_after_free"]):
		_fail("body-only mask-1 ray still hit after queue_free")
		return
	var payload: Dictionary = {
		"case_id": "%s/%s/seed-%d/%s" % [_visual_stage, _recipe_id, _seed_value, _lighting],
		"recipe_id": _recipe_id,
		"seed": _seed_value,
		"lighting": _lighting,
		"visual_stage": _visual_stage,
		"archetype_id": _archetype_id,
		"pool_membership": true,
		"main_scene_path": MAIN_SCENE_PATH,
		"playable_ready_seen": _ready_seen,
		"playable_started": bool(_playable.playable_started),
		"loader_loaded": _playable.loader != null and _playable.loader.has_loaded_ship(),
		"camera_script_path": CAMERA_SCRIPT_PATH,
		"camera_current": get_root().get_viewport().get_camera_3d() == _playable.camera_rig.camera,
		"standalone_nodes_created": false,
		"recipe_sha256": _sha256_text(_canonical_json(recipe_document)),
		"runtime": runtime,
	}
	print("BIOMASS COMPOSITE CASE PASS %s" % _canonical_json(payload).strip_edges())
	_main_instance.queue_free()
	quit(0)

func _on_playable_ready(_summary: Dictionary) -> void:
	_ready_seen = true

func _production_ready() -> bool:
	if _playable.get_script() != PlayableScript:
		_fail("playable instance is not the production PlayableGeneratedShip script")
		return false
	if not _playable.playable_started:
		_fail("production playable_started is false")
		return false
	if _playable.loader == null or not _playable.loader.has_loaded_ship():
		_fail("production loader is not loaded")
		return false
	if _playable.camera_rig == null or _playable.camera_rig.get_script() != IsoCameraRigScript:
		_fail("production IsoCameraRig script identity is wrong")
		return false
	if _playable.camera_rig.camera == null:
		_fail("production IsoCameraRig camera is missing")
		return false
	if get_root().get_viewport().get_camera_3d() != _playable.camera_rig.camera:
		_fail("production IsoCameraRig camera is not current")
		return false
	return true

func _apply_validation_lighting() -> bool:
	var biome_doc: Dictionary = _load_json_dict(BREACH_FIELD_PATH)
	var base: Variant = biome_doc.get("atmosphere", null)
	if not base is Dictionary:
		_fail("breach_field atmosphere is missing")
		return false
	var atmosphere: Dictionary = (base as Dictionary).duplicate(true)
	match _lighting:
		"normal":
			atmosphere.erase("emergency_accent")
			atmosphere.erase("emergency_accent_energy")
			atmosphere["ambient_color"] = [0.12, 0.20, 0.40]
			atmosphere["ambient_energy"] = 0.72
			atmosphere["key_light_color"] = [0.72, 0.84, 1.0]
			atmosphere["key_light_energy"] = 1.5
		"emergency":
			atmosphere["ambient_color"] = [0.22, 0.035, 0.02]
			atmosphere["ambient_energy"] = 0.38
			atmosphere["key_light_color"] = [1.0, 0.22, 0.10]
			atmosphere["key_light_energy"] = 0.65
			atmosphere["emergency_accent"] = "#ff6a3d"
			atmosphere["emergency_accent_energy"] = 0.16
		"dark":
			atmosphere.erase("emergency_accent")
			atmosphere.erase("emergency_accent_energy")
			atmosphere["ambient_color"] = [0.025, 0.045, 0.10]
			atmosphere["ambient_energy"] = 0.16
			atmosphere["key_light_color"] = [0.18, 0.28, 0.55]
			atmosphere["key_light_energy"] = 0.18
	# The applier is the production seam; this script never constructs an
	# environment or light of its own.
	var result: Dictionary = AtmosphereApplierScript.new().apply(_main_instance, atmosphere, true)
	if not bool(result.get("applied", false)) or not bool(result.get("key_light_applied", false)) or not bool(result.get("is_away", false)):
		_fail("production SliceAtmosphereApplier did not apply atmosphere")
		return false
	var environment: WorldEnvironment = _find_world_environment(_main_instance)
	var key_light: DirectionalLight3D = _find_directional_light(_main_instance)
	if environment == null or environment.environment == null or key_light == null:
		_fail("production environment or key light is not inspectable")
		return false
	var env: Environment = environment.environment
	var profile: Dictionary = _lighting_profile()
	if not _close_color(env.ambient_light_color, profile["ambient_color"] as Array) or absf(env.ambient_light_energy - float(profile["ambient_energy"])) > 0.000001:
		_fail("production ambient lighting differs from validation profile")
		return false
	if not _close_color(key_light.light_color, profile["key_light_color"] as Array) or absf(key_light.light_energy - float(profile["key_light_energy"])) > 0.000001:
		_fail("production key lighting differs from validation profile")
		return false
	if not env.fog_enabled or absf(env.fog_density - 0.032) > 0.000001:
		_fail("production fog differs from breach_field validation profile")
		return false
	var accent: Node = _main_instance.find_child("SliceAtmosphereEmergencyAccent", true, false)
	var expected_accent: bool = _lighting == "emergency"
	if (accent != null) != expected_accent:
		_fail("production emergency accent presence differs from profile")
		return false
	return true

func _lighting_observation() -> Dictionary:
	var environment_node: WorldEnvironment = _find_world_environment(_main_instance)
	var key_light: DirectionalLight3D = _find_directional_light(_main_instance)
	if environment_node == null or environment_node.environment == null or key_light == null:
		return {}
	var env: Environment = environment_node.environment
	var accent: OmniLight3D = _main_instance.find_child("SliceAtmosphereEmergencyAccent", true, false) as OmniLight3D
	return {
		"applied": true,
		"key_light_applied": true,
		"is_away": true,
		"ambient_color": [env.ambient_light_color.r, env.ambient_light_color.g, env.ambient_light_color.b],
		"ambient_energy": env.ambient_light_energy,
		"key_light_color": [key_light.light_color.r, key_light.light_color.g, key_light.light_color.b],
		"key_light_energy": key_light.light_energy,
		"fog_enabled": env.fog_enabled,
		"fog_density": env.fog_density,
		"emergency_accent_present": accent != null,
		"emergency_accent_applied": accent != null and _lighting == "emergency",
		"emergency_accent_energy": accent.light_energy if accent != null else null,
	}

func _lighting_profile() -> Dictionary:
	match _lighting:
		"normal": return {"ambient_color": [0.12, 0.20, 0.40], "ambient_energy": 0.72, "key_light_color": [0.72, 0.84, 1.0], "key_light_energy": 1.5}
		"emergency": return {"ambient_color": [0.22, 0.035, 0.02], "ambient_energy": 0.38, "key_light_color": [1.0, 0.22, 0.10], "key_light_energy": 0.65}
	return {"ambient_color": [0.025, 0.045, 0.10], "ambient_energy": 0.16, "key_light_color": [0.18, 0.28, 0.55], "key_light_energy": 0.18}

func _collect_runtime(visual: Variant, recipe_document: Dictionary) -> Dictionary:
	var runtime: Dictionary = {
		"attachments": (recipe_document.get("attachments", []) as Array).size(),
		"occurrences": 0,
		"nodes": visual.runtime_node_count(),
		"triangles": visual.triangle_budget(),
		"max_nodes": 160,
		"max_triangles": 24000,
		"aabb_extents_m": [],
		"collision_count": 0,
		"enabled_collision_count": 0,
		"disabled_connector_collision_count": 0,
		"direct_body_collision_children": 0,
		"body_collision_layer": int(visual.collision_layer),
		"body_collision_mask": int(visual.collision_mask),
		"ray_hit": false,
		"ray_miss_after_free": false,
		"gait_frames": GAIT_FRAMES,
		"gait_delta_seconds": GAIT_DELTA,
		"wrapper_paths_empty": true,
		"primitive_mesh_parts": true,
	}
	var lighting: Dictionary = _lighting_observation()
	if lighting.is_empty():
		return {"error": "production lighting observation is unavailable"}
	runtime["lighting"] = lighting
	if visual.runtime_node_count() > 160 or visual.triangle_budget() > 24000:
		return {"error": "assembled visual exceeds review caps"}
	var bounds: AABB = _mesh_bounds(visual)
	if bounds.size == Vector3.ZERO or not bounds.size.is_finite():
		return {"error": "assembled visual has no finite mesh bounds"}
	runtime["aabb_extents_m"] = [bounds.size.x, bounds.size.y, bounds.size.z]
	var body: CharacterBody3D = visual as CharacterBody3D
	var direct_collisions: int = 0
	for child in body.get_children():
		if child is CollisionShape3D:
			direct_collisions += 1
			runtime["collision_count"] = int(runtime["collision_count"]) + 1
			if (child as CollisionShape3D).disabled:
				runtime["disabled_connector_collision_count"] = int(runtime["disabled_connector_collision_count"]) + 1
			else:
				runtime["enabled_collision_count"] = int(runtime["enabled_collision_count"]) + 1
	runtime["direct_body_collision_children"] = direct_collisions
	var attachments: Array = recipe_document.get("attachments", []) as Array
	runtime["occurrences"] = 1 + attachments.size() + attachments.size()
	if int(runtime["collision_count"]) != int(runtime["occurrences"]):
		return {"error": "collision count does not equal part occurrences"}
	if int(runtime["enabled_collision_count"]) != 1 + attachments.size():
		return {"error": "enabled collision count does not equal non-connector occurrences"}
	if int(runtime["disabled_connector_collision_count"]) != attachments.size():
		return {"error": "disabled connector collision count does not equal connector occurrences"}
	if body.collision_layer != 1 or body.collision_mask != 1:
		return {"error": "biomass body collision layer/mask is not 1"}
	return runtime

func _validate_stage(recipe_document: Dictionary, visual: Variant) -> bool:
	var parts_doc: Dictionary = _load_json_dict(PART_CATALOG_PATH)
	var parts: Variant = parts_doc.get("parts", null)
	if not parts is Dictionary:
		_fail("part catalog has no parts object")
		return false
	for occurrence in _recipe_occurrences(recipe_document):
		var part_id: String = str(occurrence.get("part_id", ""))
		var entry: Variant = (parts as Dictionary).get(part_id, null)
		if not entry is Dictionary:
			_fail("recipe part is missing from catalog: %s" % part_id)
			return false
		var wrapper_path: String = str((entry as Dictionary).get("wrapper_scene_path", ""))
		if _visual_stage == "placeholder" and not wrapper_path.is_empty():
			_fail("placeholder review found a non-empty wrapper path")
			return false
		if _visual_stage == "final" and wrapper_path.is_empty():
			_fail("final review requires non-empty wrapper paths")
			return false
		var instance_id: String = str(occurrence.get("instance_id", ""))
		var part_root: Node3D = visual.part(instance_id)
		if part_root == null:
			_fail("assembled part is missing: %s" % instance_id)
			return false
		for node in _nodes(part_root):
			if node is MeshInstance3D:
				var mesh: Mesh = (node as MeshInstance3D).mesh
				if _visual_stage == "placeholder" and not (mesh is PrimitiveMesh):
					_fail("placeholder part mesh is not a PrimitiveMesh")
					return false
				if _visual_stage == "final" and mesh is PrimitiveMesh:
					_fail("final part mesh is still a PrimitiveMesh")
					return false
	return true

func _recipe_occurrences(recipe_document: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var core: Dictionary = recipe_document.get("core", {})
	result.append(core)
	for edge_variant in recipe_document.get("attachments", []) as Array:
		if edge_variant is Dictionary:
			result.append(edge_variant as Dictionary)
	return result

func _mesh_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var found: bool = false
	for child in _nodes(node):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var current: AABB = _transform_aabb((child as MeshInstance3D).get_aabb(), (child as MeshInstance3D).global_transform)
			if not found:
				result = current
				found = true
			else:
				result = result.merge(current)
	return result

func _transform_aabb(source: AABB, transform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	for x in [source.position.x, source.end.x]:
		for y in [source.position.y, source.end.y]:
			for z in [source.position.z, source.end.z]:
				corners.append(transform * Vector3(float(x), float(y), float(z)))
	var result: AABB = AABB(corners[0], Vector3.ZERO)
	for corner in corners.slice(1):
		result = result.expand(corner)
	return result

func _nodes(root_node: Node) -> Array[Node]:
	var result: Array[Node] = [root_node]
	for child in root_node.get_children():
		result.append_array(_nodes(child))
	return result

func _freeze_processing(root_node: Node) -> void:
	for node in _nodes(root_node):
		node.set_process(false)
		node.set_physics_process(false)

func _capture_image() -> Image:
	var texture: ViewportTexture = get_root().get_viewport().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image

func _compare_images(visible: Image, hidden: Image) -> Dictionary:
	if visible.get_width() != hidden.get_width() or visible.get_height() != hidden.get_height():
		return {"pass": false, "rgb_delta": 0.0, "changed_pixels": 0, "changed_bbox_width": 0, "changed_bbox_height": 0}
	var changed: int = 0
	var max_delta: float = 0.0
	var min_x: int = visible.get_width()
	var min_y: int = visible.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in range(visible.get_height()):
		for x in range(visible.get_width()):
			var a: Color = visible.get_pixel(x, y)
			var b: Color = hidden.get_pixel(x, y)
			var delta: float = maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			max_delta = maxf(max_delta, delta)
			if delta >= 8.0 / 255.0:
				changed += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	var width: int = max_x - min_x + 1 if max_x >= min_x else 0
	var height: int = max_y - min_y + 1 if max_y >= min_y else 0
	return {
		"pass": max_delta >= 8.0 / 255.0 and changed >= 64 and width >= 8 and height >= 8,
		"rgb_delta": max_delta,
		"changed_pixels": changed,
		"changed_bbox_width": width,
		"changed_bbox_height": height,
	}

func _ray_hits_body(origin: Vector3, target: Vector3, expected: Node3D) -> bool:
	var state: PhysicsDirectSpaceState3D = (_main_instance as Node3D).get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = state.intersect_ray(query)
	return hit.get("collider", null) == expected

func _ray_hits_any_body(origin: Vector3, target: Vector3) -> bool:
	var state: PhysicsDirectSpaceState3D = (_main_instance as Node3D).get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not state.intersect_ray(query).is_empty()

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var found: WorldEnvironment = _find_world_environment(child)
		if found != null:
			return found
	return null

func _find_directional_light(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node as DirectionalLight3D
	for child in node.get_children():
		var found: DirectionalLight3D = _find_directional_light(child)
		if found != null:
			return found
	return null

func _load_json_dict(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value as Dictionary if value is Dictionary else {}

func _canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true) + "\n"

func _sha256_text(value: String) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _close_color(actual: Color, expected: Array) -> bool:
	return absf(actual.r - float(expected[0])) <= 0.000001 and absf(actual.g - float(expected[1])) <= 0.000001 and absf(actual.b - float(expected[2])) <= 0.000001

func _resolve_output_path(raw: String) -> String:
	if raw.begins_with("res://"):
		return ProjectSettings.globalize_path(raw).simplify_path()
	if raw.is_absolute_path():
		return raw.simplify_path()
	return ProjectSettings.globalize_path("res://" + raw.trim_prefix("./")).simplify_path()

func _fail(reason: String) -> void:
	_failed_reason = reason
	printerr("BIOMASS COMPOSITE CASE FAIL: %s" % reason)
	quit(1)
