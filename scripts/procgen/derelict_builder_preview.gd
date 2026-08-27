extends Node3D
class_name DerelictBuilderPreview

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const FireStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")
const DerelictObjectiveControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")

const RESULT_MARKER := "DERELICT_BUILDER_PREVIEW_RESULT"
# Navigation snapping is allowed to absorb tiny authoring/mesh quantization
# differences, but a distant point must not be treated as walkable.
const NAVIGATION_SNAP_TOLERANCE := 0.75
const PLAYER_SPAWN_HEIGHT := 0.2
const PREVIEW_INTERACTION_RADIUS := 2.2
const PREVIEW_HUD_HINT := "WASD / arrows: move    E / Enter / Space: interact"
const PREVIEW_ARC_COLLISION_SIZE := Vector3(2.6, 2.2, 1.6)
const PREVIEW_ARC_DISCHARGED_COLOR := Color(0.35, 0.85, 1.0, 0.35)
const PREVIEW_ARC_ARCING_COLOR := Color(0.95, 0.32, 1.0, 0.82)
const PREVIEW_INPUT_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER],
}
const REQUIRED_CHECKS: Array[String] = [
	"structural_collision", "navigation", "objectives", "props", "loot", "vertical_links",
	"fire", "arc", "electrical", "radiation", "breach", "atmosphere", "portal_interaction",
	"interactive_player",
]
const CANONICAL_MARKER_CHECKS: Array[String] = [
	"collision", "navigation", "verticals", "objectives", "props", "loot", "fire", "arc",
	"breach", "radiation", "atmosphere",
]

var loader
var manifest_path := ""
var result_path := ""
var _ship_summary: Dictionary = {}
var _source_hash := ""
var _kit_id := ""
var preview_player
var preview_camera_rig
var preview_inventory
var preview_loot_containers: Array = []
var preview_arc_state
var preview_arc_zones: Array[StaticBody3D] = []
var preview_objective_controller
var preview_objective_interactables: Array = []
var _interaction_status: Label
var _interactive_ready := false


func _ready() -> void:
	manifest_path = _argument("--manifest")
	if manifest_path.is_empty():
		manifest_path = OS.get_environment("DERELICT_BUILDER_MANIFEST")
	if manifest_path.is_empty():
		_finish(false, ["missing --manifest argument"])
		return
	manifest_path = _absolute_path(manifest_path, ProjectSettings.globalize_path("res://"))
	result_path = manifest_path.get_base_dir().path_join("preview_result.json")
	var manifest := _json_file(manifest_path)
	if manifest.is_empty():
		_finish(false, ["manifest is missing or invalid JSON"])
		return
	result_path = _absolute_path(str(manifest.get("result_path", result_path)), manifest_path.get_base_dir())
	_source_hash = str(manifest.get("source_hash", ""))
	_kit_id = str(manifest.get("kit_id", ""))
	var errors := _validate_manifest(manifest)
	if not errors.is_empty():
		_finish(false, errors)
		return
	var base := manifest_path.get_base_dir()
	var layout_path := _absolute_path(str(manifest.get("layout_path", "")), base)
	var gameplay_path := _absolute_path(str(manifest.get("gameplay_slice_path", "")), base)
	var kit_path := _absolute_path(str(manifest.get("kit_path", "")), base)
	loader = LoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(func(summary: Dictionary) -> void: _ship_summary = summary.duplicate(true))
	add_child(loader)
	if not loader.load_from_paths(layout_path, kit_path, gameplay_path, true):
		_finish(false, ["GeneratedShipLoader rejected the bundle"])
		return
	# Navigation maps synchronize asynchronously after regions and links enter
	# the tree. Do not let an unsynchronized map return empty/default points that
	# could make a path check pass accidentally.
	if not await _wait_for_navigation_sync():
		_finish(false, ["navigation map did not synchronize"])
		return
	var layout_doc := _json_file(layout_path)
	var gameplay_doc := _json_file(gameplay_path)
	_interactive_ready = _setup_interactive_runtime()
	var acceptance := _exercise_runtime(layout_doc, gameplay_doc)
	_finish(bool(acceptance.get("ok", false)), acceptance.get("errors", []), acceptance.get("checks", {}))


func _process(delta: float) -> void:
	# The builder preview is a real playable scene, so authored arcs continue
	# cycling while the user walks around instead of being represented only by
	# a one-shot acceptance model.
	if preview_arc_state == null or preview_arc_zones.is_empty():
		return
	preview_arc_state.tick(delta)
	_apply_preview_arc_state()


func _validate_manifest(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(manifest.get("document_kind", "")) != "derelict_builder_bundle":
		errors.append("manifest document_kind must be derelict_builder_bundle")
	if str(manifest.get("validation_result", "")) != "passed":
		errors.append("bundle does not record a passed validation")
	var base := manifest_path.get_base_dir()
	for key in ["source_path", "layout_path", "gameplay_slice_path", "kit_path"]:
		var resolved := _absolute_path(str(manifest.get(key, "")), base)
		if resolved.is_empty() or not FileAccess.file_exists(resolved):
			errors.append("missing %s: %s" % [key, resolved])
	if errors.is_empty():
		_validate_hash(errors, _absolute_path(str(manifest.get("source_path", "")), base), str(manifest.get("source_hash", "")), "source")
		_validate_hash(errors, _absolute_path(str(manifest.get("layout_path", "")), base), str(manifest.get("layout_hash", "")), "layout")
		_validate_hash(errors, _absolute_path(str(manifest.get("gameplay_slice_path", "")), base), str(manifest.get("gameplay_slice_hash", "")), "gameplay slice")
		var layout := _json_file(_absolute_path(str(manifest.get("layout_path", "")), base))
		var gameplay := _json_file(_absolute_path(str(manifest.get("gameplay_slice_path", "")), base))
		var kit := _json_file(_absolute_path(str(manifest.get("kit_path", "")), base))
		if str(layout.get("schema_version", "")) != str(manifest.get("layout_schema", "")):
			errors.append("layout schema does not match manifest")
		if str(gameplay.get("schema_version", "")) != str(manifest.get("gameplay_schema", "")):
			errors.append("gameplay schema does not match manifest")
		if str(layout.get("kit_id", "")) != str(manifest.get("kit_id", "")):
			errors.append("layout kit_id does not match manifest")
		var manifest_kit_id := str(manifest.get("kit_id", ""))
		var kit_file_id := str(kit.get("kit_id", ""))
		if kit_file_id != manifest_kit_id:
			errors.append("kit kit_id does not match manifest")
		if kit_file_id != str(layout.get("kit_id", "")):
			errors.append("kit kit_id does not match layout")
	return errors


func _validate_hash(errors: Array[String], path: String, expected: String, label: String) -> void:
	if expected.is_empty():
		errors.append("manifest has no %s hash" % label)
		return
	var content := FileAccess.get_file_as_string(path)
	if _sha256(content) != expected:
		errors.append("%s hash does not match manifest" % label)


func _exercise_runtime(layout: Dictionary, gameplay: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var checks := {
		"structural_collision": loader.structural_root != null and _structural_wrappers_have_collision(loader.structural_root),
		"navigation": _navigation_path_exists(loader.get_goal_position()),
		"objectives": _exercise_objectives(),
		"loot": _exercise_loot(gameplay),
		"props": loader.get_placed_prop_specs_copy().size() == _array(gameplay.get("placed_props", [])).size(),
		"vertical_links": _exercise_vertical_links(layout),
		"interactive_player": _interactive_ready and _interactive_runtime_ready(),
	}
	var hazard_materialization := _hazard_materialization_checks(layout)
	for hazard_name in hazard_materialization:
		checks[hazard_name] = bool(hazard_materialization[hazard_name])
		if not bool(checks[hazard_name]):
			errors.append("authored %s hazard was not fully materialized" % hazard_name)
	var fire_specs: Array = loader.get_fire_zone_specs()
	var fire_state = FireStateScript.new()
	if bool(checks["fire"]) and not fire_specs.is_empty():
		var fire_room := str(fire_specs[0].get("compartment_id", fire_specs[0].get("from_room", "authored_fire")))
		fire_state.configure({"compartments": [fire_room]})
		checks["fire"] = bool(checks["fire"]) and fire_state.ignite(fire_room, 1.0) and fire_state.is_burning(fire_room)

	var arc_ready: bool = _exercise_preview_arc_runtime()
	checks["arc"] = bool(checks["arc"]) and arc_ready
	# Retain the legacy key for existing automation while exposing the authored
	# hazard name used by the builder and the human-readable success marker.
	checks["electrical"] = checks["arc"]

	var radiation_specs: Array = loader.get_radiation_zone_specs()
	var radiation_state = RadiationStateScript.new()
	var radiation_spatially_ready := _radiation_spatial_query_ready(radiation_specs)
	radiation_state.configure({"in_radiation_zone": radiation_spatially_ready})
	radiation_state.tick(1.0)
	checks["radiation"] = bool(checks["radiation"]) and (radiation_specs.is_empty() or (radiation_spatially_ready and radiation_state.radiation > 0.0))

	var breach_specs: Array = loader.get_breach_zone_specs()
	var oxygen_state = OxygenStateScript.new()
	oxygen_state.configure({"zone_ids": _zone_ids(breach_specs), "drain_rate": 6.0})
	if not breach_specs.is_empty():
		oxygen_state.tick(1.0, {"player_in_breach_zone": true})
	checks["breach"] = bool(checks["breach"]) and (breach_specs.is_empty() or (
		breach_specs.size() == loader.get_breach_zone_markers().size()
		and oxygen_state.oxygen < oxygen_state.max_oxygen
	))

	checks["atmosphere"] = _exercise_atmosphere(layout)

	checks["portal_interaction"] = _exercise_portals(layout)
	for key in REQUIRED_CHECKS:
		if not bool(checks[key]):
			errors.append("runtime acceptance failed: %s" % key)
	return {"ok": errors.is_empty(), "errors": errors, "checks": checks}


func _hazard_materialization_checks(layout: Dictionary) -> Dictionary:
	return {
		"fire": _hazard_array_matches(layout.get("fire_zones", []), loader.get_fire_zone_specs()),
		"arc": _hazard_array_matches(layout.get("arc_zones", []), loader.get_arc_zone_specs()),
		"radiation": _hazard_array_matches(layout.get("radiation_zones", []), loader.get_radiation_zone_specs()),
		"breach": _hazard_array_matches(layout.get("breach_zones", []), loader.get_breach_zone_specs()),
	}


func _hazard_array_matches(authored_variant: Variant, materialized: Array) -> bool:
	if typeof(authored_variant) != TYPE_ARRAY:
		return false
	var authored: Array = authored_variant
	if authored.size() != materialized.size():
		return false
	var authored_ids := _hazard_id_counts(authored)
	var materialized_ids := _hazard_id_counts(materialized)
	return authored_ids == materialized_ids


func _hazard_id_counts(specs: Array) -> Dictionary:
	var counts: Dictionary = {}
	for spec_variant in specs:
		if not spec_variant is Dictionary:
			return {"<invalid>": 1}
		var spec: Dictionary = spec_variant
		var id := str(spec.get("id", spec.get("zone_id", "")))
		if not id.is_empty():
			counts[id] = int(counts.get(id, 0)) + 1
	return counts


func _structural_wrappers_have_collision(root: Node3D) -> bool:
	if root == null:
		return false
	var wrappers: Array[Node] = root.find_children("*", "Node3D", true, false)
	var required_count := 0
	for candidate in wrappers:
		if not candidate.has_meta("structural_kind"):
			continue
		required_count += 1
		if not _has_collision_shape(candidate):
			return false
	return required_count > 0


func _has_collision_shape(node: Node) -> bool:
	for candidate in node.find_children("*", "CollisionShape3D", true, false):
		if (candidate as CollisionShape3D).shape != null:
			return true
	return false


func _setup_interactive_runtime() -> bool:
	if not is_instance_valid(loader) or loader.structural_root == null:
		return false
	_ensure_preview_input_actions()
	preview_inventory = InventoryStateScript.new()
	preview_player = PlayerControllerScript.new()
	preview_player.name = "PreviewPlayerController"
	add_child(preview_player)
	preview_player.teleport_to(
		loader.to_global(loader.get_start_transform().origin) + Vector3.UP * PLAYER_SPAWN_HEIGHT)
	preview_player.interact_requested.connect(_on_preview_interact_requested)

	preview_camera_rig = IsoCameraRigScript.new()
	preview_camera_rig.name = "PreviewIsoCameraRig"
	add_child(preview_camera_rig)
	preview_camera_rig.set_follow_target(preview_player)
	preview_camera_rig.make_current()
	_build_preview_objective_runtime()
	_build_preview_arc_runtime()
	_build_interactive_loot()
	_build_interaction_status()
	return _interactive_runtime_ready()


func _build_preview_objective_runtime() -> void:
	for interactable in preview_objective_interactables:
		if is_instance_valid(interactable):
			var parent_node: Node = interactable.get_parent()
			if parent_node != null:
				parent_node.remove_child(interactable)
			interactable.free()
	preview_objective_interactables.clear()
	preview_objective_controller = DerelictObjectiveControllerScript.create()
	if not is_instance_valid(loader):
		return
	var specs: Array = loader.get_objective_specs_copy()
	preview_objective_controller.configure(specs)
	for spec_variant in specs:
		if not (spec_variant is Dictionary):
			continue
		var spec: Dictionary = spec_variant
		var steps_variant: Variant = spec.get("steps", [])
		var steps: Array = steps_variant if steps_variant is Array else []
		if str(spec.get("kind", "single")) == "repair_junction" and steps.size() > 1:
			for step_variant in steps:
				if not (step_variant is Dictionary):
					continue
				var step: Dictionary = step_variant
				var step_position: Variant = step.get("position", Vector3.INF)
				if not (step_position is Vector3):
					continue
				var step_interactable = InteractableScript.new()
				step_interactable.configure_from_step(spec, step, step_position, PREVIEW_INTERACTION_RADIUS)
				step_interactable.interaction_completed.connect(_on_preview_objective_completed)
				loader.add_child(step_interactable)
				preview_objective_interactables.append(step_interactable)
		else:
			var position_variant: Variant = spec.get("position", Vector3.INF)
			if not (position_variant is Vector3):
				continue
			var interactable = InteractableScript.new()
			interactable.configure_from_objective(spec, position_variant, PREVIEW_INTERACTION_RADIUS)
			interactable.interaction_completed.connect(_on_preview_objective_completed)
			loader.add_child(interactable)
			preview_objective_interactables.append(interactable)


func _on_preview_objective_completed(
		_interaction_id: String, _objective_id: String, sequence: int,
		_objective_type: String, _room_id: String, step_id: String) -> void:
	if preview_objective_controller != null:
		preview_objective_controller.complete(sequence, step_id)


func _build_preview_arc_runtime() -> void:
	preview_arc_zones.clear()
	preview_arc_state = null
	if not is_instance_valid(loader):
		return
	var specs: Array = loader.get_arc_zone_specs()
	var markers: Array[Vector3] = loader.get_arc_zone_markers()
	if specs.is_empty() or markers.size() != specs.size():
		return
	preview_arc_state = ArcStateScript.new()
	preview_arc_state.configure({"zone_ids": _zone_ids(specs)})
	for index in range(specs.size()):
		var spec: Dictionary = specs[index] if specs[index] is Dictionary else {}
		var zone_id := str(spec.get("id", spec.get("zone_id", "preview_arc_%d" % index)))
		var zone := StaticBody3D.new()
		zone.name = "BuilderPreviewElectricalArc_%s" % zone_id
		zone.position = markers[index]
		zone.collision_layer = 1
		zone.collision_mask = 1
		zone.set_meta("arc_zone_id", zone_id)
		zone.set_meta("arc_zone_kind", "electrical_arc")
		zone.set_meta("arc_zone_phase", "DISCHARGED")
		zone.set_meta("arc_zone_passability_blocked", false)

		var collision := CollisionShape3D.new()
		collision.name = "BuilderPreviewArcCollision"
		var box_shape := BoxShape3D.new()
		box_shape.size = PREVIEW_ARC_COLLISION_SIZE
		collision.shape = box_shape
		collision.position = Vector3(0.0, PREVIEW_ARC_COLLISION_SIZE.y * 0.5, 0.0)
		collision.disabled = true
		zone.add_child(collision)

		var visual := MeshInstance3D.new()
		visual.name = "BuilderPreviewArcVisual"
		var box_mesh := BoxMesh.new()
		box_mesh.size = PREVIEW_ARC_COLLISION_SIZE
		visual.mesh = box_mesh
		visual.position = collision.position
		visual.material_override = _preview_arc_material(false)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(visual)
		loader.add_child(zone)
		preview_arc_zones.append(zone)
	_apply_preview_arc_state()


func _preview_arc_material(is_arcing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = PREVIEW_ARC_ARCING_COLOR if is_arcing else PREVIEW_ARC_DISCHARGED_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _apply_preview_arc_state() -> void:
	if preview_arc_state == null:
		return
	var summary: Dictionary = preview_arc_state.get_summary()
	var arcing := bool(summary.get("arcing", false))
	var phase := str(summary.get("state", "DISCHARGED"))
	for zone in preview_arc_zones:
		if not is_instance_valid(zone):
			continue
		if str(zone.get_meta("arc_zone_phase", "")) == phase:
			continue
		zone.set_meta("arc_zone_phase", phase)
		zone.set_meta("arc_zone_passability_blocked", arcing)
		for child in zone.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not arcing
			elif child is MeshInstance3D and child.name == "BuilderPreviewArcVisual":
				var visual := child as MeshInstance3D
				var material := visual.material_override as StandardMaterial3D
				if material != null:
					material.albedo_color = PREVIEW_ARC_ARCING_COLOR if arcing else PREVIEW_ARC_DISCHARGED_COLOR


func _exercise_preview_arc_runtime() -> bool:
	var specs: Array = loader.get_arc_zone_specs()
	if specs.is_empty():
		return true
	if preview_arc_state == null or preview_arc_zones.size() != specs.size():
		return false
	# Drive the attached scene consumer into its dangerous phase and inspect the
	# actual collision/visual nodes. Restore the normal discharged-first cycle
	# before handing control to the interactive preview.
	preview_arc_state.configure({"zone_ids": _zone_ids(specs), "arcing_first": true})
	_apply_preview_arc_state()
	for zone in preview_arc_zones:
		if not is_instance_valid(zone) or str(zone.get_meta("arc_zone_phase", "")) != "ARCING":
			return false
		var collision_found := false
		var visual_found := false
		for child in zone.get_children():
			if child is CollisionShape3D:
				collision_found = (child as CollisionShape3D).shape != null and not (child as CollisionShape3D).disabled
			elif child is MeshInstance3D and child.name == "BuilderPreviewArcVisual":
				visual_found = (child as MeshInstance3D).mesh != null
		if not collision_found or not visual_found:
			return false
	preview_arc_state.configure({"zone_ids": _zone_ids(specs)})
	_apply_preview_arc_state()
	return true


func _ensure_preview_input_actions() -> void:
	for action_name_variant in PREVIEW_INPUT_BINDINGS:
		var action_name := str(action_name_variant)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var existing: Dictionary = {}
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey:
				existing[int((event as InputEventKey).keycode)] = true
		for keycode_variant in PREVIEW_INPUT_BINDINGS[action_name]:
			var keycode := int(keycode_variant)
			if existing.has(keycode):
				continue
			var input_event := InputEventKey.new()
			input_event.keycode = keycode
			InputMap.action_add_event(action_name, input_event)
			existing[keycode] = true


func _build_interactive_loot() -> void:
	preview_loot_containers.clear()
	var tables := LootRollerScript.load_tables()
	for spec_variant in loader.get_loot_container_specs_copy():
		if not spec_variant is Dictionary:
			continue
		var spec: Dictionary = spec_variant
		var container_id := str(spec.get("id", ""))
		var position_variant: Variant = spec.get("position", Vector3.INF)
		if container_id.is_empty() or not position_variant is Vector3:
			continue
		var container = LootContainerScript.new()
		container.configure(
			container_id,
			str(spec.get("loot_table", "generic_crate")),
			"derelict_builder_preview:%s" % container_id,
			preview_inventory,
			tables,
			position_variant,
			1.8,
			spec,
		)
		loader.add_child(container)
		preview_loot_containers.append(container)


func _build_interaction_status() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewInstructions"
	add_child(layer)
	_interaction_status = Label.new()
	_interaction_status.name = "InteractionStatus"
	_interaction_status.position = Vector2(18.0, 18.0)
	_interaction_status.text = PREVIEW_HUD_HINT
	_interaction_status.add_theme_color_override("font_color", Color.WHITE)
	_interaction_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_interaction_status.add_theme_constant_override("shadow_offset_x", 2)
	_interaction_status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_interaction_status)


func _on_preview_interact_requested(player_body) -> void:
	for portal in loader.get_authored_portal_nodes():
		if not is_instance_valid(portal) or not portal.has_method("try_interact"):
			continue
		var result: Dictionary = portal.try_interact({}, player_body)
		if bool(result.get("ok", false)):
			_set_interaction_status("Portal %s: %s" % [
				str(result.get("portal_id", "")),
				"open" if bool(result.get("open", false)) else str(result.get("reason", "closed")),
			])
			return
		if str(result.get("reason", "")) == "locked":
			_set_interaction_status("Locked portal: requires %s" % str(result.get("needs", "key")))
			return
	for container in preview_loot_containers:
		if is_instance_valid(container) and container.try_interact(player_body):
			_set_interaction_status("Searched loot container %s" % str(container.container_id))
			return
	var nearest_objective = null
	var nearest_distance := PREVIEW_INTERACTION_RADIUS
	for objective in preview_objective_interactables:
		if not is_instance_valid(objective) or bool(objective.get("completed")):
			continue
		var distance := (objective as Node3D).global_position.distance_to(player_body.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_objective = objective
	if nearest_objective != null:
		if nearest_objective.try_interact(player_body):
			var step_id := str(nearest_objective.get("step_id"))
			_set_interaction_status("Completed %s" % [
				"step %s" % step_id if not step_id.is_empty() \
				else "objective %s" % str(nearest_objective.get("objective_id")),
			])
			return
	_set_interaction_status("Nothing in interaction range")


func _set_interaction_status(message: String) -> void:
	if is_instance_valid(_interaction_status):
		_interaction_status.text = "%s\n%s" % [message, PREVIEW_HUD_HINT]


func _interactive_runtime_ready() -> bool:
	if not is_instance_valid(preview_player) or not preview_player is CharacterBody3D:
		return false
	if not is_instance_valid(preview_camera_rig) or preview_camera_rig.follow_target != preview_player:
		return false
	if preview_camera_rig.camera == null or not preview_camera_rig.camera.current:
		return false
	for action_name in PREVIEW_INPUT_BINDINGS:
		if not InputMap.has_action(str(action_name)) or InputMap.action_get_events(str(action_name)).is_empty():
			return false
	return true


func _radiation_spatial_query_ready(specs: Array) -> bool:
	if specs.is_empty():
		return true
	var markers: Array[Vector3] = loader.get_radiation_zone_markers()
	if markers.size() != specs.size():
		return false
	for index in range(specs.size()):
		if not specs[index] is Dictionary:
			return false
		var queried: Dictionary = loader.get_radiation_zone_at(markers[index])
		if queried.is_empty():
			return false
		var authored_id := str((specs[index] as Dictionary).get("id", (specs[index] as Dictionary).get("zone_id", "")))
		var queried_id := str(queried.get("id", queried.get("zone_id", "")))
		if authored_id.is_empty() or queried_id != authored_id:
			return false
	return true


func _navigation_path_exists(local_target: Vector3) -> bool:
	if loader.structural_root == null:
		return false
	var region := loader.structural_root.find_child("GameplayNavigationRegion", true, false) as NavigationRegion3D
	if region == null:
		return false
	var navigation_map: RID = region.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) <= 0:
		return false
	var start_world: Vector3 = loader.to_global(loader.get_start_transform().origin)
	var target_world: Vector3 = loader.to_global(local_target)
	return _navigation_path_between_world(navigation_map, start_world, target_world)


func _navigation_path_between_world(navigation_map: RID, start_world: Vector3, target_world: Vector3) -> bool:
	if not navigation_map.is_valid():
		return false
	var start_on_map := NavigationServer3D.map_get_closest_point(navigation_map, start_world)
	var target_on_map := NavigationServer3D.map_get_closest_point(navigation_map, target_world)
	if start_world.distance_to(start_on_map) > NAVIGATION_SNAP_TOLERANCE \
			or target_world.distance_to(target_on_map) > NAVIGATION_SNAP_TOLERANCE:
		return false
	var path := NavigationServer3D.map_get_path(navigation_map, start_on_map, target_on_map, true)
	if path.size() >= 2:
		return true
	# A one-room document may intentionally use the same start and goal. Only
	# that authored coincidence may accept a zero-length navigation path.
	return start_world.distance_to(target_world) <= 0.05


func _exercise_vertical_links(layout: Dictionary) -> bool:
	var authored_links := _array(layout.get("vertical_connections", []))
	var expected_count := authored_links.size()
	if loader.structural_root == null:
		return expected_count == 0 and int(_ship_summary.get("vertical_link_count", -1)) == 0
	var links: Array[Node] = loader.structural_root.find_children("VerticalLink_*", "NavigationLink3D", true, false)
	if int(_ship_summary.get("vertical_link_count", -1)) != expected_count or links.size() != expected_count:
		return false
	var region := loader.structural_root.find_child("GameplayNavigationRegion", true, false) as NavigationRegion3D
	if region == null:
		return expected_count == 0
	var navigation_map: RID = region.get_navigation_map()
	for link_variant in links:
		var link := link_variant as NavigationLink3D
		if link == null or not link.enabled or link.navigation_layers == 0 or link.get_navigation_map() != navigation_map:
			return false
		var saved_states: Array = []
		for other_variant in links:
			var other := other_variant as NavigationLink3D
			saved_states.append({"link": other, "enabled": other.enabled})
			if other != link:
				other.enabled = false
		NavigationServer3D.map_force_update(navigation_map)
		var start_world := link.to_global(link.start_position)
		var end_world := link.to_global(link.end_position)
		var link_ready := _navigation_path_between_world(navigation_map, start_world, end_world)
		for state in saved_states:
			(state["link"] as NavigationLink3D).enabled = bool(state["enabled"])
		NavigationServer3D.map_force_update(navigation_map)
		if not link_ready:
			return false
	return true


func _wait_for_navigation_sync() -> bool:
	if loader.structural_root == null:
		return false
	var region := loader.structural_root.find_child("GameplayNavigationRegion", true, false) as NavigationRegion3D
	if region == null:
		return false
	var navigation_map: RID = region.get_navigation_map()
	var vertices := region.navigation_mesh.get_vertices() if region.navigation_mesh != null else PackedVector3Array()
	if not navigation_map.is_valid() or vertices.is_empty():
		return false
	# The preview runs and exits much faster than a normal gameplay scene. Give
	# the active map one forced warm-up, then only poll for real server progress.
	var probe_world: Vector3 = region.to_global(vertices[0])
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(navigation_map)
	for _frame in range(120):
		if NavigationServer3D.map_get_iteration_id(navigation_map) > 0 \
				and NavigationServer3D.map_get_closest_point(navigation_map, probe_world).distance_to(probe_world) <= 1.0:
			return true
		await get_tree().physics_frame
	return false


func _exercise_objectives() -> bool:
	var specs: Array = loader.get_objective_specs_copy()
	if specs.is_empty() or preview_objective_controller == null \
			or preview_objective_interactables.is_empty():
		return false
	var expected_interactions := 0
	for spec_variant in specs:
		if not (spec_variant is Dictionary):
			continue
		var spec: Dictionary = spec_variant
		var steps: Variant = spec.get("steps", [])
		expected_interactions += (steps as Array).size() \
			if str(spec.get("kind", "single")) == "repair_junction" and steps is Array \
			else 1
	var accepted := preview_objective_interactables.size() == expected_interactions
	for interactable in preview_objective_interactables:
		if not is_instance_valid(interactable) or not (interactable is Node3D):
			accepted = false
			continue
		if not _navigation_path_exists(loader.to_local((interactable as Node3D).global_position)):
			accepted = false
		interactable.set_validation_player_in_range(preview_player)
		if not interactable.try_interact(preview_player):
			accepted = false
	for spec_variant in specs:
		if spec_variant is Dictionary and not preview_objective_controller.is_objective_complete(
				int((spec_variant as Dictionary).get("sequence", 0))):
			accepted = false
	# Acceptance must not consume the interactive preview. Rebuild the same
	# production interactable/controller flow in its pristine state for the user.
	_build_preview_objective_runtime()
	return accepted


func _exercise_loot(gameplay: Dictionary) -> bool:
	var specs: Array = loader.get_loot_container_specs_copy()
	if specs.is_empty() or specs.size() != _array(gameplay.get("loot_containers", [])).size():
		return false
	# PlayableGeneratedShip and the builder preview must resolve table-only loot
	# against the same shipped catalog. Passing an empty catalog lets a bad table
	# reference search successfully while granting nothing.
	var loot_tables: Dictionary = LootRollerScript.load_tables()
	if loot_tables.is_empty():
		return false
	for spec_variant in specs:
		if not (spec_variant is Dictionary):
			return false
		var spec: Dictionary = spec_variant
		var has_authored_contents: bool = spec.has("contents") and typeof(spec.get("contents")) == TYPE_ARRAY
		var table_id := str(spec.get("loot_table", ""))
		var seed_source := "derelict_builder_preview"
		var expected_contents: Array = LootContainerScript.normalized_contents(spec) if spec.has("contents") else []
		# Roll table-backed loot once here to establish the deterministic expected
		# grant. The container uses the same seed and catalog for the runtime roll.
		var expected_roll: Array = []
		if not has_authored_contents:
			expected_roll = LootDistributionScript.roll(table_id, seed_source, loot_tables, spec)
			# An unknown, empty, or invalid table is not a runnable authored branch.
			if expected_roll.is_empty():
				return false
		var inventory = InventoryStateScript.new()
		var inventory_before: Dictionary = {}
		if not has_authored_contents:
			for entry_variant in expected_roll:
				if entry_variant is Dictionary:
					var entry: Dictionary = entry_variant
					inventory_before[str(entry.get("item_id", ""))] = 0
		var container = LootContainerScript.new()
		var player := Node3D.new()
		add_child(container)
		add_child(player)
		container.configure(
			str(spec.get("id", "preview_loot")), table_id,
			seed_source, inventory, loot_tables, Vector3.ZERO, 1.8, spec
		)
		container.set_validation_player_in_range(player)
		var interacted: bool = container.try_interact(player)
		var accepted: bool = interacted and container.searched
		if not has_authored_contents:
			for entry_variant in expected_roll:
				if not (entry_variant is Dictionary):
					accepted = false
					continue
				var entry: Dictionary = entry_variant
				var item_id := str(entry.get("item_id", ""))
				if item_id.is_empty() or inventory.get_quantity(item_id) <= int(inventory_before.get(item_id, 0)):
					accepted = false
		for stack_variant in expected_contents:
			if not (stack_variant is Dictionary):
				accepted = false
				continue
			var stack: Dictionary = stack_variant
			var item_id := str(stack.get("item_id", ""))
			var quantity := int(stack.get("qty", stack.get("quantity", 0)))
			if item_id.is_empty() or quantity <= 0 or inventory.get_quantity(item_id) != quantity:
				accepted = false
		container.queue_free()
		player.queue_free()
		if not accepted:
			return false
	return true


func _exercise_portals(layout: Dictionary) -> bool:
	var nodes: Array[Area3D] = loader.get_authored_portal_nodes()
	if nodes.size() != _structural_portal_count(layout):
		return false
	for portal in nodes:
		if portal == null or not portal.has_method("try_interact"):
			return false
		var was_open: bool = portal.is_open
		var was_unsafe: bool = portal.is_unsafe
		portal.set_validation_player_in_range(true)
		var shape: CollisionShape3D = portal.get_blocker_collision_shape()
		if shape == null:
			_restore_portal_state(portal, was_open, was_unsafe)
			return false
		var portal_ready := true
		var exterior_result: Dictionary = {}
		var exit_signal := {"emitted": false}
		var exit_callback := func(_portal_id: String) -> void: exit_signal["emitted"] = true
		if portal.is_exterior and portal.has_signal("exterior_exit_triggered"):
			portal.connect("exterior_exit_triggered", exit_callback, CONNECT_ONE_SHOT)
		match str(portal.portal_kind):
			"LOCKED":
				var denied: Dictionary = portal.try_interact({})
				var flag := str(portal.required_flag())
				var flags := {}
				flags[flag] = true
				var opened: Dictionary = portal.try_interact(flags)
				exterior_result = opened
				if str(denied.get("reason", "")) != "locked" or not bool(opened.get("open", false)) or not shape.disabled:
					portal_ready = false
			"BREACH":
				if not shape.disabled or not bool(portal.try_interact({}).get("unsafe", false)):
					portal_ready = false
			_:
				var before := shape.disabled
				var opened: Dictionary = portal.try_interact({})
				exterior_result = opened
				if bool(opened.get("ok", false)) and not portal.is_exterior:
					if shape.disabled == before:
						portal_ready = false
		var requires_exit: bool = bool(portal.is_exterior) and str(portal.portal_kind) != "BREACH"
		if requires_exit and (
				not bool(exterior_result.get("exterior", false)) \
				or not bool(exit_signal.get("emitted", false)) \
				or not portal.is_open \
				or not shape.disabled):
			portal_ready = false
		_restore_portal_state(portal, was_open, was_unsafe)
		if not portal_ready:
			return false
	return true


func _restore_portal_state(portal: Area3D, was_open: bool, was_unsafe: bool) -> void:
	portal.is_open = was_open
	portal.is_unsafe = was_unsafe
	portal.set_validation_player_in_range(false)
	portal._apply_state()


func _exercise_atmosphere(layout: Dictionary) -> bool:
	var authored := false
	for room_variant in _array(layout.get("rooms", [])):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		if not _room_has_authored_atmosphere(room):
			continue
		authored = true
		var center: Vector3 = loader.get_room_center(str(room.get("id", "")))
		var atmosphere: Dictionary = loader.get_authored_atmosphere_at(center)
		if atmosphere.is_empty():
			return false
		var multiplier: float = float(loader.get_authored_atmosphere_drain_multiplier_at(center))
		var oxygen = OxygenStateScript.new()
		oxygen.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
		var before: float = oxygen.oxygen
		oxygen.tick(1.0, {
			"field_atmosphere": true,
			"field_atmosphere_multiplier": multiplier,
		})
		var should_drain := bool(atmosphere.get("depressurized", false)) or bool(atmosphere.get("vented", false)) or int(atmosphere.get("oxygen_bp", 10000)) < 10000
		if should_drain != (oxygen.oxygen < before):
			return false
		var radiation = RadiationStateScript.new()
		radiation.configure({"in_radiation_zone": int(atmosphere.get("radiation_bp", 0)) > 0})
		radiation.tick(1.0)
		if (int(atmosphere.get("radiation_bp", 0)) > 0) != (radiation.radiation > 0.0):
			return false
		var body_temperature = BodyTemperatureStateScript.new()
		body_temperature.configure({})
		var ambient_temperature: float = float(atmosphere.get("temperature_c", BodyTemperatureStateScript.DEFAULT_TEMPERATURE))
		var extreme_temperature: bool = ambient_temperature < body_temperature.safe_min or ambient_temperature > body_temperature.safe_max
		var temperature_before: float = body_temperature.temperature
		body_temperature.tick(30.0, {"ambient_temperature_c": ambient_temperature})
		if extreme_temperature and (body_temperature.temperature == temperature_before or body_temperature.is_safe()):
			return false
	return true if authored else not _has_authored_atmosphere(layout)


func _room_has_authored_atmosphere(room: Dictionary) -> bool:
	return room.has("atmosphere_bp") or room.has("oxygen_bp") or room.has("depressurized") or room.has("vented") or room.has("radiation_bp") or room.has("temperature_c")


func _structural_portal_count(layout: Dictionary) -> int:
	var plan: Variant = layout.get("structural_plan", {})
	if not (plan is Dictionary):
		return _array(layout.get("portals", layout.get("connections", []))).size()
	var edges: Variant = (plan as Dictionary).get("edges", {})
	if not (edges is Dictionary):
		return _array(layout.get("portals", layout.get("connections", []))).size()
	var count := 0
	for raw in (edges as Dictionary).values():
		if raw is Dictionary and bool((raw as Dictionary).get("portal", false)):
			count += 1
	return count


func _finish(ok: bool, errors: Array, checks: Dictionary = {}) -> void:
	var result_errors: Array = errors.duplicate()
	var result := {
		"ok": ok,
		"manifest_path": manifest_path,
		"source_hash": _source_hash,
		"kit_id": _kit_id,
		"errors": result_errors,
		"checks": checks,
		"completed_at_utc": Time.get_datetime_string_from_system(true, true),
	}
	if not result_path.is_empty() and not _write_result(result):
		ok = false
		result["ok"] = false
		result_errors.append("could not write preview result: %s" % result_path)
		result["errors"] = result_errors
	print("%s %s" % [RESULT_MARKER, JSON.stringify(result)])
	if ok:
		print(_canonical_success_marker(checks))
	if not ok:
		push_error("DERELICT BUILDER PREVIEW FAIL %s" % "; ".join(result_errors))
	if DisplayServer.get_name() == "headless" or not ok:
		get_tree().quit(0 if ok else 1)


func _write_result(result: Dictionary) -> bool:
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(result, "\t") + "\n")
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func _canonical_success_marker(checks: Dictionary) -> String:
	var marker_parts: Array[String] = []
	for key in CANONICAL_MARKER_CHECKS:
		var source_key := "structural_collision" if key == "collision" else ("vertical_links" if key == "verticals" else key)
		marker_parts.append("%s=%s" % [key, "true" if bool(checks.get(source_key, false)) else "false"])
	return "DERELICT BUILDER PREVIEW PASS %s" % " ".join(marker_parts)


func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return ""


func _absolute_path(path: String, base: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return base.path_join(path).simplify_path()


func _json_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _sha256(content: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(content.to_utf8_buffer())
	return context.finish().hex_encode()


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _zone_ids(specs: Array) -> Array[String]:
	var ids: Array[String] = []
	for index in range(specs.size()):
		if specs[index] is Dictionary:
			ids.append(str(specs[index].get("zone_id", specs[index].get("id", "zone_%d" % index))))
	return ids


func _has_authored_atmosphere(layout: Dictionary) -> bool:
	for room_variant in _array(layout.get("rooms", [])):
		if room_variant is Dictionary and _room_has_authored_atmosphere(room_variant as Dictionary):
			return true
	return false
