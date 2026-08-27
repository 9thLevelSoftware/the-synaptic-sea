extends Node3D
class_name GeneratedShipLoader

const GameplayObjectiveVolumeScript := preload("res://scripts/procgen/gameplay_objective_volume.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const SliceAtmosphereApplierScript := preload("res://scripts/procgen/slice_atmosphere_applier.gd")
const IntegrityVisualResolverScript := preload("res://scripts/systems/integrity_visual_resolver.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const GameplayPropFactoryScript := preload("res://scripts/placement/gameplay_prop_factory.gd")
const PropVisualBindingCatalogScript := preload("res://scripts/systems/prop_visual_binding_catalog.gd")
const RuntimePropVisualBinderScript := preload("res://scripts/procgen/runtime_prop_visual_binder.gd")
const AuthoredPortalRuntimeScript := preload("res://scripts/interaction/authored_portal_runtime.gd")

const DRESSING_PROP_KINDS: Array[String] = ["crate", "pipe", "growth"]

signal ship_loaded(summary: Dictionary)
signal load_failed(reason: String)

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const ATMOSPHERE_VOLUME_HALF_WIDTH: float = CELL_SIZE * 0.5
const ATMOSPHERE_VOLUME_HEIGHT: float = 2.5
const OBJECTIVE_TRIGGER_RADIUS: float = 1.5
const RADIATION_VOLUME_HALF_WIDTH: float = 1.25
const RADIATION_VOLUME_AXIAL_END_PADDING: float = 1.0
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]

var layout_doc: Dictionary = {}
var kit_doc: Dictionary = {}
var gameplay_doc: Dictionary = {}
var objective_specs: Array = []
var loot_container_specs: Array = []
var objective_volumes: Array = []
var landmark_nodes: Array[Node3D] = []
var blocked_route_nodes: Array[Node3D] = []
var visible_vertical_transition_nodes: Array[Node3D] = []
var breach_zone_markers: Array[Vector3] = []
var breach_zone_specs: Array = []
var fire_zone_markers: Array[Vector3] = []
var fire_zone_specs: Array = []
var arc_zone_markers: Array[Vector3] = []
var arc_zone_specs: Array = []
var radiation_zone_markers: Array[Vector3] = []
var radiation_zone_specs: Array = []
var radiation_zone_segments: Array = []
var authored_atmosphere_specs: Array = []
var authored_atmosphere_volumes: Array[Area3D] = []
var placed_prop_specs: Array = []
var placed_prop_nodes: Array[Node3D] = []
var placed_prop_errors: Array[String] = []
var authored_portal_specs: Array = []
var authored_portal_nodes: Array[Area3D] = []
var start_position: Vector3 = Vector3.INF
var goal_position: Vector3 = Vector3.INF
var structural_root: Node3D
var objective_root: Node3D
var room_variant_descriptors: Dictionary = {}  # room_id -> {"variant": String, "dressing": String}
const RoomVariantSelectorDressScript := preload("res://scripts/procgen/room_variant_selector.gd")


func clear_loaded_ship() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	layout_doc = {}
	kit_doc = {}
	gameplay_doc = {}
	objective_specs = []
	loot_container_specs = []
	objective_volumes = []
	landmark_nodes = []
	blocked_route_nodes = []
	visible_vertical_transition_nodes = []
	breach_zone_markers = []
	breach_zone_specs = []
	fire_zone_markers = []
	fire_zone_specs = []
	arc_zone_markers = []
	arc_zone_specs = []
	radiation_zone_markers = []
	radiation_zone_specs = []
	radiation_zone_segments = []
	authored_atmosphere_specs = []
	authored_atmosphere_volumes = []
	placed_prop_specs = []
	placed_prop_nodes = []
	placed_prop_errors = []
	authored_portal_specs = []
	authored_portal_nodes = []
	start_position = Vector3.INF
	goal_position = Vector3.INF
	structural_root = null
	objective_root = null
	room_variant_descriptors = {}


func load_from_paths(layout_path: String, kit_path: String, gameplay_slice_path: String, is_away: bool = false) -> bool:
	clear_loaded_ship()

	var layout_abs: String = _resolve_path(layout_path)
	var kit_abs: String = _resolve_path(kit_path)
	var gameplay_slice_abs: String = _resolve_path(gameplay_slice_path)

	if not FileAccess.file_exists(layout_abs):
		return _fail_load("layout not found: %s" % layout_abs)
	if not FileAccess.file_exists(kit_abs):
		return _fail_load("kit not found: %s" % kit_abs)
	if not FileAccess.file_exists(gameplay_slice_abs):
		return _fail_load("gameplay slice not found: %s" % gameplay_slice_abs)

	layout_doc = _load_json_dict(layout_abs, "layout")
	if layout_doc.is_empty():
		return _fail_load("layout JSON is invalid: %s" % layout_abs)
	_build_room_variant_descriptors()
	kit_doc = _load_json_dict(kit_abs, "kit")
	if kit_doc.is_empty():
		return _fail_load("kit JSON is invalid: %s" % kit_abs)
	gameplay_doc = _load_json_dict(gameplay_slice_abs, "gameplay slice")
	if gameplay_doc.is_empty():
		return _fail_load("gameplay slice JSON is invalid: %s" % gameplay_slice_abs)

	return load_from_documents(
		layout_doc,
		kit_doc,
		gameplay_doc,
		is_away,
		{
			"layout": layout_abs,
			"kit": kit_abs,
			"gameplay_slice": gameplay_slice_abs,
		}
	)


func load_from_documents(
		layout: Dictionary,
		kit: Dictionary,
		gameplay_slice: Dictionary,
		apply_atmosphere: bool,
		source_paths: Dictionary = {}) -> bool:
	clear_loaded_ship()
	layout_doc = layout
	kit_doc = kit
	gameplay_doc = gameplay_slice
	_build_room_variant_descriptors()

	var layout_abs: String = str(source_paths.get("layout", ""))
	var kit_abs: String = str(source_paths.get("kit", ""))
	var gameplay_slice_abs: String = str(source_paths.get("gameplay_slice", ""))

	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return _fail_load("layout missing rooms array: %s" % layout_abs)
	var rooms: Array = rooms_variant

	var prototype_variant: Variant = layout_doc.get("prototype", {})
	if typeof(prototype_variant) != TYPE_DICTIONARY:
		return _fail_load("layout missing prototype object: %s" % layout_abs)
	var prototype: Dictionary = prototype_variant

	var start_room_id: String = str(gameplay_doc.get("start_room", prototype.get("start_room", "")))
	var goal_room_id: String = str(gameplay_doc.get("goal_room", prototype.get("goal_room", "")))
	if start_room_id.is_empty():
		return _fail_load("gameplay slice missing start_room: %s" % gameplay_slice_abs)
	if goal_room_id.is_empty():
		return _fail_load("gameplay slice missing goal_room: %s" % gameplay_slice_abs)

	var module_to_scene: Dictionary = _build_module_scene_map(kit_doc, kit_abs)
	if module_to_scene.is_empty():
		return _fail_load("kit contains no usable module wrapper scenes: %s" % kit_abs)

	var structural_verdict: Dictionary = _validate_structural_plan_for_loading()
	if not bool(structural_verdict.get("ok", false)):
		return _fail_load("layout structural plan validation failed: %s" % str(structural_verdict.get("errors", [])))
	if not _preflight_structural_wrappers(module_to_scene, layout_doc.get("structural_plan", {})):
		return _fail_load("structural wrapper preflight failed")

	objective_specs = _build_objective_specs(layout_doc, gameplay_doc, gameplay_slice_abs)
	if objective_specs.is_empty():
		return _fail_load("gameplay slice contains no valid objectives: %s" % gameplay_slice_abs)

	loot_container_specs = _build_loot_container_specs(layout_doc, gameplay_doc)

	start_position = _room_center(rooms, start_room_id)
	goal_position = _room_center(rooms, goal_room_id)
	if start_position == Vector3.INF:
		return _fail_load("start room not found in layout: %s" % start_room_id)
	if goal_position == Vector3.INF:
		return _fail_load("goal room not found in layout: %s" % goal_room_id)

	structural_root = Node3D.new()
	structural_root.name = "StructuralRoot"
	add_child(structural_root)

	objective_root = Node3D.new()
	objective_root.name = "ObjectiveRoot"
	add_child(objective_root)

	var instantiated_count: int = _instance_structural_wrappers(layout_doc, module_to_scene, structural_root)
	if instantiated_count < 0:
		clear_loaded_ship()
		return _fail_load("failed to instantiate structural wrapper scenes")
	_apply_module_damage_visuals(layout_doc, structural_root)

	var nav_region: NavigationRegion3D = _build_navigation_region(rooms, structural_root)
	if nav_region == null:
		clear_loaded_ship()
		return _fail_load("no floor/corridor floor placements found for navigation mesh")

	var vertical_link_count: int = _add_vertical_links(layout_doc, structural_root)

	_add_coherence_runtime_nodes(layout_doc, structural_root)
	_add_authored_placed_props(layout_doc, gameplay_doc, structural_root)
	_add_authored_portal_runtime_nodes(layout_doc, structural_root)
	# PKG-B5.1: apply dressing fog/tint/light meta per room variant descriptors.
	_apply_dressing_visuals(layout_doc, structural_root)
	_apply_slice_atmosphere(layout_doc, apply_atmosphere)

	objective_volumes = []
	for objective_variant in objective_specs:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var world_position_variant: Variant = objective.get("position", Vector3.ZERO)
		var world_position: Vector3 = Vector3.ZERO
		if typeof(world_position_variant) == TYPE_VECTOR3:
			world_position = world_position_variant
		var volume = GameplayObjectiveVolumeScript.new()
		volume.configure(objective, world_position, OBJECTIVE_TRIGGER_RADIUS)
		objective_root.add_child(volume)
		objective_volumes.append(volume)

	emit_signal(
		"ship_loaded",
		{
			"layout_path": layout_abs,
			"kit_path": kit_abs,
			"gameplay_slice_path": gameplay_slice_abs,
			"instantiated_count": instantiated_count,
			"vertical_link_count": vertical_link_count,
			"objective_count": objective_specs.size(),
			"start_position": start_position,
			"goal_position": goal_position,
		}
	)
	return true


func _apply_slice_atmosphere(source_layout: Dictionary, is_away: bool) -> void:
	var biome_id: String = str(source_layout.get("biome_id", ""))
	if biome_id.is_empty():
		return
	var biome_path: String = "res://data/procgen/biomes/%s.json" % biome_id
	if not FileAccess.file_exists(biome_path):
		push_warning("GeneratedShipLoader: atmosphere biome file missing: %s" % biome_path)
		return
	var biome_doc: Dictionary = _load_json_dict(biome_path, "biome")
	var atmosphere_variant: Variant = biome_doc.get("atmosphere", {})
	if typeof(atmosphere_variant) != TYPE_DICTIONARY:
		return
	var applier = SliceAtmosphereApplierScript.new()
	applier.apply(self, atmosphere_variant as Dictionary, is_away)


func _fail_load(reason: String) -> bool:
	push_error(reason)
	emit_signal("load_failed", reason)
	return false


func has_loaded_ship() -> bool:
	return structural_root != null and not objective_specs.is_empty() and start_position != Vector3.INF and goal_position != Vector3.INF


func get_layout_copy() -> Dictionary:
	return layout_doc.duplicate(true)


func get_start_transform() -> Transform3D:
	var spawn_position: Vector3 = start_position
	if spawn_position == Vector3.INF:
		spawn_position = Vector3.ZERO
	return Transform3D(Basis.IDENTITY, spawn_position)


func get_goal_position() -> Vector3:
	return goal_position


func get_objective_specs_copy() -> Array:
	return objective_specs.duplicate(true)


func get_loot_container_specs_copy() -> Array:
	return loot_container_specs.duplicate(true)


func get_placed_prop_specs_copy() -> Array:
	return placed_prop_specs.duplicate(true)


func get_placed_prop_nodes() -> Array[Node3D]:
	return placed_prop_nodes.duplicate()


func get_placed_prop_errors() -> Array[String]:
	return placed_prop_errors.duplicate()

func get_authored_portal_specs_copy() -> Array:
	return authored_portal_specs.duplicate(true)

func get_authored_portal_nodes() -> Array[Area3D]:
	return authored_portal_nodes.duplicate()


func count_collision_shapes() -> int:
	if structural_root == null:
		return 0
	# Only structural wrapper collisions represent the generated ship's
	# collision contract.  Portal blockers, hazard volumes, and marker shapes
	# are also children of StructuralRoot but are runtime overlays.
	return _count_collision_shapes_recursive(structural_root, false)


func _count_collision_shapes_recursive(node: Node, in_structural_wrapper: bool) -> int:
	var count: int = 0
	var structural_context := in_structural_wrapper or node.has_meta("structural_kind")
	if structural_context and node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node
		if collision_shape.shape != null:
			count += 1
	for child in node.get_children():
		count += _count_collision_shapes_recursive(child, structural_context)
	return count


func _resolve_path(raw_path: String) -> String:
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return ProjectSettings.globalize_path(raw_path)
	if raw_path.is_absolute_path():
		return raw_path
	if FileAccess.file_exists(raw_path) or DirAccess.open(raw_path) != null:
		return raw_path
	var cwd: String = OS.get_environment("PWD")
	if not cwd.is_empty():
		var cwd_path: String = cwd.path_join(raw_path)
		if FileAccess.file_exists(cwd_path) or DirAccess.open(cwd_path) != null:
			return cwd_path
	return ProjectSettings.globalize_path("res://%s" % raw_path)


func _load_json_dict(path: String, label: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s JSON is not an object: %s" % [label, path])
		return {}
	return parsed


func _build_module_scene_map(kit_doc: Dictionary, kit_path: String) -> Dictionary:
	var modules_variant: Variant = kit_doc.get("modules", [])
	if typeof(modules_variant) != TYPE_ARRAY:
		push_error("kit missing modules array: %s" % kit_path)
		return {}

	var module_to_scene: Dictionary = {}
	for module_variant in modules_variant:
		if typeof(module_variant) != TYPE_DICTIONARY:
			continue
		var module: Dictionary = module_variant
		var module_id: String = str(module.get("module_id", ""))
		var scene_path: String = str(module.get("godot_wrapper_scene", ""))
		if module_id.is_empty() or scene_path.is_empty():
			continue
		module_to_scene[module_id] = scene_path
	return module_to_scene


func _validate_structural_plan_for_loading() -> Dictionary:
	var structural_plan_variant: Variant = layout_doc.get("structural_plan", null)
	if typeof(structural_plan_variant) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["layout missing validated structural_plan"]}
	var structural_plan: Dictionary = structural_plan_variant
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout_doc)
	return verdict


func _preflight_structural_wrappers(module_to_scene: Dictionary, structural_plan: Dictionary) -> bool:
	var edge_variant: Variant = structural_plan.get("placements", null)
	var floor_variant: Variant = structural_plan.get("floor_placements", null)
	if typeof(edge_variant) != TYPE_ARRAY or typeof(floor_variant) != TYPE_ARRAY:
		push_error("structural plan wrapper preflight requires edge and floor placement arrays")
		return false
	var all_records: Array = []
	all_records.append_array(edge_variant as Array)
	all_records.append_array(floor_variant as Array)
	var ceiling_variant: Variant = structural_plan.get("ceiling_placements", [])
	if typeof(ceiling_variant) == TYPE_ARRAY:
		all_records.append_array(ceiling_variant as Array)
	var probed_modules: Dictionary = {}
	for record_variant in all_records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			push_error("structural plan wrapper preflight found non-object placement")
			return false
		var record: Dictionary = record_variant
		var module_id: String = str(record.get("module_id", ""))
		if probed_modules.has(module_id):
			continue
		var scene_path: String = str(module_to_scene.get(module_id, ""))
		if module_id.is_empty() or scene_path.is_empty():
			push_error("structural plan wrapper preflight missing wrapper for module %s" % module_id)
			return false
		if not ResourceLoader.exists(scene_path):
			push_error("structural plan wrapper preflight missing scene %s" % scene_path)
			return false
		var scene: Resource = ResourceLoader.load(scene_path)
		if scene == null or not (scene is PackedScene):
			push_error("structural plan wrapper preflight scene is not PackedScene: %s" % scene_path)
			return false
		var probe: Node = (scene as PackedScene).instantiate()
		if probe == null or not (probe is Node3D):
			if probe != null:
				probe.free()
			push_error("structural plan wrapper preflight instance is not Node3D: %s" % module_id)
			return false
		probe.free()
		probed_modules[module_id] = true
	return true


func _build_objective_specs(layout_doc: Dictionary, gameplay_doc: Dictionary, gameplay_slice_path: String) -> Array:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		push_error("layout missing rooms array: %s" % gameplay_slice_path)
		return []
	var rooms: Array = rooms_variant

	var objectives_variant: Variant = gameplay_doc.get("objectives", [])
	if typeof(objectives_variant) != TYPE_ARRAY:
		push_error("gameplay slice missing objectives array: %s" % gameplay_slice_path)
		return []
	var objectives: Array = objectives_variant
	if objectives.is_empty():
		push_error("gameplay slice contains no objectives: %s" % gameplay_slice_path)
		return []

	var expected_sequence: int = 1
	var objective_specs: Array = []
	for objective_variant in objectives:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			push_error("gameplay slice objective is not an object: %s" % gameplay_slice_path)
			return []
		var objective: Dictionary = objective_variant
		var objective_id: String = str(objective.get("id", ""))
		if objective_id.is_empty():
			push_error("gameplay slice objective missing id: %s" % gameplay_slice_path)
			return []
		var sequence: int = int(objective.get("sequence", 0))
		if sequence != expected_sequence:
			push_error(
				"gameplay slice objective sequence mismatch: expected=%d got=%d objective=%s"
				% [expected_sequence, sequence, objective_id]
			)
			return []
		expected_sequence += 1

		var room_id: String = str(objective.get("room_id", ""))
		if room_id.is_empty():
			push_error("gameplay slice objective missing room_id: %s" % objective_id)
			return []
		var room: Dictionary = _find_room(rooms, room_id)
		if room.is_empty():
			push_error("objective room not found in layout: %s" % room_id)
			return []

		var approach_variant: Variant = objective.get("approach_cell", [])
		if typeof(approach_variant) != TYPE_ARRAY:
			push_error("objective missing approach_cell: %s" % objective_id)
			return []
		var approach_cell: Array = approach_variant
		if approach_cell.size() < 3:
			push_error("objective approach_cell is incomplete: %s" % objective_id)
			return []

		var target_position: Vector3 = _room_cell_world(room, approach_cell)
		if target_position == Vector3.INF:
			push_error(
				"no floor position for approach cell objective=%s room=%s cell=%s"
				% [objective_id, room_id, str(approach_cell)]
			)
			return []

		var kind: String = str(objective.get("kind", "single"))
		var step_specs: Array = []
		if kind == "repair_junction":
			var steps_variant: Variant = objective.get("steps", [])
			if typeof(steps_variant) != TYPE_ARRAY or steps_variant.size() < 2:
				push_error("repair_junction objective requires at least 2 steps: %s" % objective_id)
				return []
			var seen_step_ids: Dictionary = {}
			for step_variant in steps_variant:
				if typeof(step_variant) != TYPE_DICTIONARY:
					push_error("repair_junction step is not an object: %s" % objective_id)
					return []
				var step: Dictionary = step_variant
				var step_id: String = str(step.get("step_id", ""))
				if step_id.is_empty():
					push_error("repair_junction step missing step_id: %s" % objective_id)
					return []
				if seen_step_ids.has(step_id):
					push_error("repair_junction duplicate step_id '%s' in objective %s" % [step_id, objective_id])
					return []
				seen_step_ids[step_id] = true
				var step_approach: Array = approach_cell.duplicate()
				var step_approach_variant: Variant = step.get("approach_cell", [])
				if typeof(step_approach_variant) == TYPE_ARRAY and step_approach_variant.size() >= 3:
					step_approach = step_approach_variant
				var step_position: Vector3 = _room_cell_world(room, step_approach)
				if step_position == Vector3.INF:
					push_error(
						"no floor position for step approach cell objective=%s step=%s cell=%s"
						% [objective_id, step_id, str(step_approach)]
					)
					return []
				step_specs.append({
					"step_id": step_id,
					"approach_cell": step_approach,
					"position": step_position,
				})

		var spec: Dictionary = {
			"id": objective_id,
			"sequence": sequence,
			"type": str(objective.get("type", "unknown")),
			"kind": kind,
			"room_id": room_id,
			"approach_cell": approach_cell.duplicate(),
			"position": target_position,
			"radius": OBJECTIVE_TRIGGER_RADIUS,
			"steps": step_specs,
		}
		if objective.has("loot_table"):
			spec["loot_table"] = str(objective.get("loot_table", ""))
		objective_specs.append(spec)

	return objective_specs


func _build_loot_container_specs(layout_doc: Dictionary, gameplay_doc: Dictionary) -> Array:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return []
	var rooms: Array = rooms_variant
	var containers_variant: Variant = gameplay_doc.get("loot_containers", [])
	if typeof(containers_variant) != TYPE_ARRAY:
		return []
	var out: Array = []
	for c_variant in (containers_variant as Array):
		if typeof(c_variant) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_variant
		var cid: String = str(c.get("id", ""))
		var room_id: String = str(c.get("room_id", ""))
		if cid.is_empty() or room_id.is_empty():
			continue
		var room: Dictionary = _find_room(rooms, room_id)
		if room.is_empty():
			continue
		var approach_variant: Variant = c.get("approach_cell", [])
		if typeof(approach_variant) != TYPE_ARRAY or (approach_variant as Array).size() < 3:
			continue
		var pos: Vector3 = _room_cell_world(room, approach_variant as Array)
		if pos == Vector3.INF:
			continue
		var loot_spec: Dictionary = {
			"id": cid,
			"kind": str(c.get("kind", "generic_crate")),
			"room_id": room_id,
			"loot_table": str(c.get("loot_table", "generic_crate")),
			"position": pos,
			"approach_cell": (approach_variant as Array).duplicate(),
		}
		if c.has("slot_kind"):
			loot_spec["slot_kind"] = str(c.get("slot_kind", ""))
			loot_spec["slot_index"] = int(c.get("slot_index", 0))
		# Explicit authored stacks must survive into the coordinator; omitting
		# this key is why golden/builder contents never reached in-game loot.
		if c.has("contents") and typeof(c.get("contents")) == TYPE_ARRAY:
			loot_spec["contents"] = (c.get("contents") as Array).duplicate(true)
		out.append(loot_spec)
	return out


func _find_room(rooms: Array, room_id: String) -> Dictionary:
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) == room_id:
			return room
	return {}


func _cell_name_candidates(cell: Array) -> Array:
	if cell.size() < 3:
		return []
	var x: int = int(cell[0])
	var z: int = int(cell[1])
	var deck: int = int(cell[2])
	var candidates: Array = []
	if deck == 0:
		candidates.append("floor_cell_x%d_z%d" % [x, z])
		candidates.append("floor_cell_d0_x%d_z%d" % [x, z])
	else:
		candidates.append("floor_cell_d%d_x%d_z%d" % [deck, x, z])
	return candidates


func _room_cell_world(room: Dictionary, cell: Array) -> Vector3:
	if cell.size() < 2:
		return Vector3.INF
	var room_id: String = str(room.get("id", ""))
	var deck: int = int(room.get("deck", -1))
	if cell.size() >= 3:
		deck = int(cell[2])
	var cell_key_value: String = "%d|%d|%d" % [deck, int(cell[0]), int(cell[1])]
	var structural_plan: Dictionary = layout_doc.get("structural_plan", {})
	var floors_variant: Variant = structural_plan.get("floor_placements", [])
	if typeof(floors_variant) != TYPE_ARRAY:
		return Vector3.INF
	for floor_variant in (floors_variant as Array):
		if typeof(floor_variant) != TYPE_DICTIONARY:
			continue
		var floor: Dictionary = floor_variant
		if str(floor.get("cell_key", "")) != cell_key_value or str(floor.get("room_id", "")) != room_id:
			continue
		var pos: Array = _read_placement_position(floor)
		if pos.size() < 3:
			return Vector3.INF
		return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
	return Vector3.INF


func _instance_structural_wrappers(layout_doc: Dictionary, module_to_scene: Dictionary, ship_root: Node3D) -> int:
	var structural_plan_variant: Variant = layout_doc.get("structural_plan", null)
	if typeof(structural_plan_variant) != TYPE_DICTIONARY:
		return -1
	var structural_plan: Dictionary = structural_plan_variant
	var edge_variant: Variant = structural_plan.get("placements", null)
	var floor_variant: Variant = structural_plan.get("floor_placements", null)
	if typeof(edge_variant) != TYPE_ARRAY or typeof(floor_variant) != TYPE_ARRAY:
		return -1
	var ceiling_variant: Variant = structural_plan.get("ceiling_placements", [])
	var ceilings: Array = ceiling_variant if typeof(ceiling_variant) == TYPE_ARRAY else []

	# Instantiate detached first. No partial structural tree is published if a
	# record is malformed or a wrapper fails; the caller can then discard the
	# empty root atomically.
	var pending: Array[Node3D] = []
	var scene_cache: Dictionary = {}
	for record_variant in (edge_variant as Array):
		var wrapper: Node3D = _instantiate_structural_record(record_variant, module_to_scene, "edge", scene_cache)
		if wrapper == null:
			for previous in pending:
				previous.free()
			_free_cached_prototypes(scene_cache)
			return -1
		pending.append(wrapper)
	for record_variant in (floor_variant as Array):
		var wrapper: Node3D = _instantiate_structural_record(record_variant, module_to_scene, "floor", scene_cache)
		if wrapper == null:
			for previous in pending:
				previous.free()
			_free_cached_prototypes(scene_cache)
			return -1
		pending.append(wrapper)
	for record_variant in ceilings:
		var wrapper: Node3D = _instantiate_structural_record(record_variant, module_to_scene, "ceiling", scene_cache)
		if wrapper == null:
			for previous in pending:
				previous.free()
			_free_cached_prototypes(scene_cache)
			return -1
		pending.append(wrapper)
	for wrapper in pending:
		ship_root.add_child(wrapper)
	_free_cached_prototypes(scene_cache)
	return pending.size()


func _free_cached_prototypes(scene_cache: Dictionary) -> void:
	for key_variant in scene_cache.keys():
		var key: String = str(key_variant)
		if not key.ends_with("::proto"):
			continue
		var proto_variant: Variant = scene_cache[key_variant]
		if proto_variant is Node:
			(proto_variant as Node).free()
		scene_cache.erase(key_variant)


func _instantiate_structural_record(
		record_variant: Variant,
		module_to_scene: Dictionary,
		layer: String,
		scene_cache: Dictionary) -> Node3D:
	if typeof(record_variant) != TYPE_DICTIONARY:
		return null
	var record: Dictionary = record_variant
	var module_id: String = str(record.get("module_id", ""))
	var scene_path: String = str(module_to_scene.get(module_id, ""))
	if module_id.is_empty() or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return null
	var scene: Resource = null
	if scene_cache.has(scene_path):
		scene = scene_cache[scene_path]
	else:
		scene = ResourceLoader.load(scene_path)
		if scene != null and scene is PackedScene:
			scene_cache[scene_path] = scene
	if scene == null or not (scene is PackedScene):
		return null
	var proto_key: String = "%s::proto" % scene_path
	var instance: Node = null
	if scene_cache.has(proto_key):
		instance = (scene_cache[proto_key] as Node3D).duplicate()
	else:
		instance = (scene as PackedScene).instantiate()
		if instance != null and instance is Node3D:
			scene_cache[proto_key] = instance
			instance = (instance as Node3D).duplicate()
	if instance == null or not (instance is Node3D):
		if instance != null:
			instance.free()
		return null
	var wrapper: Node3D = instance as Node3D
	var placement_pos: Array = _read_placement_position(record)
	if placement_pos.size() < 3:
		wrapper.free()
		return null
	wrapper.position = Vector3(float(placement_pos[0]), float(placement_pos[1]), float(placement_pos[2]))
	wrapper.rotation_degrees.y = float(record.get("yaw_degrees", 0.0))
	var placement_id: String = str(record.get("placement_id", record.get("id", "")))
	if layer == "floor":
		var cell_key_value: String = str(record.get("cell_key", ""))
		wrapper.name = "Floor_%s" % cell_key_value.replace("|", "_")
		wrapper.set_meta("structural_floor_placement_id", placement_id)
		wrapper.set_meta("structural_cell_key", cell_key_value)
		wrapper.set_meta("structural_room_id", str(record.get("room_id", "")))
		wrapper.set_meta("structural_kind", "FLOOR")
		wrapper.set_meta("module_kind", module_id)
		wrapper.set_meta("module_key", "floor/%s" % cell_key_value)
		wrapper.set_meta("room_id", str(record.get("room_id", "")))
	elif layer == "ceiling":
		var ceiling_key: String = str(record.get("cell_key", ""))
		wrapper.name = "Ceiling_%s" % ceiling_key.replace("|", "_")
		wrapper.set_meta("structural_ceiling_placement_id", placement_id)
		wrapper.set_meta("structural_ceiling_cell_key", ceiling_key)
		wrapper.set_meta("structural_room_id", str(record.get("room_id", "")))
		wrapper.set_meta("structural_kind", "CEILING")
		wrapper.set_meta("module_kind", module_id)
		wrapper.set_meta("module_key", "ceiling/%s" % ceiling_key)
		wrapper.set_meta("room_id", str(record.get("room_id", "")))
	else:
		var edge_key_value: String = str(record.get("edge_key", ""))
		wrapper.name = "StructuralEdge_%s" % edge_key_value.replace("|", "_")
		wrapper.set_meta("structural_edge_key", edge_key_value)
		wrapper.set_meta("structural_kind", str(record.get("kind", "")))
		wrapper.set_meta("structural_placement_id", placement_id)
		wrapper.set_meta("structural_room_ids", (record.get("room_ids", []) as Array).duplicate(true))
		wrapper.set_meta("module_kind", module_id)
		wrapper.set_meta("module_key", "edge/%s" % edge_key_value)
		var room_ids: Array = record.get("room_ids", []) if typeof(record.get("room_ids", [])) == TYPE_ARRAY else []
		wrapper.set_meta("room_id", str(room_ids[0]) if not room_ids.is_empty() else "")
	wrapper.set_meta("integrity_state", "intact")
	return wrapper


func _apply_module_damage_visuals(layout: Dictionary, ship_root: Node3D) -> void:
	if ship_root == null:
		return
	var lookup: Dictionary = _module_damage_lookup(layout)
	if lookup.is_empty():
		return
	_apply_module_damage_visuals_in_tree(ship_root, lookup)


func _module_damage_lookup(layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var md_v: Variant = layout.get("module_damage", [])
	if typeof(md_v) != TYPE_ARRAY:
		return out
	for row_v in (md_v as Array):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var key: String = str(row.get("module_key", row.get("module_id", "")))
		if not key.is_empty():
			out[key] = row
		var placement_id: String = str(row.get("placement_id", ""))
		if not placement_id.is_empty():
			out[placement_id] = row
	return out


func _apply_module_damage_visuals_in_tree(node: Node, lookup: Dictionary) -> void:
	if node is Node3D and node.has_meta("module_key"):
		var module_key: String = str(node.get_meta("module_key"))
		var placement_id: String = ""
		if node.has_meta("structural_placement_id"):
			placement_id = str(node.get_meta("structural_placement_id"))
		elif node.has_meta("structural_floor_placement_id"):
			placement_id = str(node.get_meta("structural_floor_placement_id"))
		elif node.has_meta("structural_ceiling_placement_id"):
			placement_id = str(node.get_meta("structural_ceiling_placement_id"))
		var row_v: Variant = lookup.get(module_key, lookup.get(placement_id, {}))
		if row_v is Dictionary and not (row_v as Dictionary).is_empty():
			var state: String = str((row_v as Dictionary).get("state", "intact"))
			if state.is_empty():
				state = "intact"
			(node as Node3D).set_meta("integrity_state", state)
			if state != "intact":
				IntegrityVisualResolverScript.apply_visual_state(node as Node3D, state)
	for child in node.get_children():
		_apply_module_damage_visuals_in_tree(child, lookup)


func _parse_prefixed_int(value: String, prefix: String) -> int:
	if not value.begins_with(prefix):
		return -2147483648
	var number_text: String = value.substr(prefix.length())
	if not number_text.is_valid_int():
		return -2147483648
	return int(number_text)


func _cell_signature_from_placement_name(placement_name: String) -> Array:
	var parts: PackedStringArray = placement_name.split("_")
	if parts.size() < 4:
		return []
	if parts[0] != "floor":
		return []
	var index: int = 2
	var deck: int = 0
	if index < parts.size() and String(parts[index]).begins_with("d"):
		deck = _parse_prefixed_int(String(parts[index]), "d")
		if deck == -2147483648:
			return []
		index += 1
	if index + 1 >= parts.size():
		return []
	var x: int = _parse_prefixed_int(String(parts[index]), "x")
	var z: int = _parse_prefixed_int(String(parts[index + 1]), "z")
	if x == -2147483648 or z == -2147483648:
		return []
	return [x, z, deck]


func _placement_matches_endpoint_cell(placement: Dictionary, endpoint: Array) -> bool:
	if endpoint.size() < 2:
		return false
	var module_id: String = str(placement.get("module_id", placement.get("module", "")))
	if not FLOOR_MODULES.has(module_id):
		return false
	var signature: Array = _cell_signature_from_placement_name(str(placement.get("name", "")))
	if signature.size() != 3:
		return false
	var endpoint_deck: int = 0
	if endpoint.size() >= 3:
		endpoint_deck = int(endpoint[2])
	return int(signature[0]) == int(endpoint[0]) and int(signature[1]) == int(endpoint[1]) and int(signature[2]) == endpoint_deck


func _cell_world_from_link_endpoint(link_doc: Dictionary, cell_key: String, room_key: String, source_layout: Dictionary) -> Vector3:
	var endpoint_variant: Variant = link_doc.get(cell_key, [])
	if typeof(endpoint_variant) != TYPE_ARRAY:
		return Vector3.INF
	var endpoint: Array = endpoint_variant
	if endpoint.size() < 2:
		return Vector3.INF
	var room_id: String = str(link_doc.get(room_key, ""))
	if room_id.is_empty():
		return Vector3.INF
	var saved_layout: Dictionary = layout_doc
	if not source_layout.is_empty():
		layout_doc = source_layout
	var room: Dictionary = _find_room_in_layout(room_id)
	var resolved: Vector3 = Vector3.INF
	if not room.is_empty():
		resolved = _room_cell_world(room, endpoint)
	layout_doc = saved_layout
	return resolved


func _add_vertical_links(layout_doc: Dictionary, ship_root: Node3D) -> int:
	var links_variant: Variant = layout_doc.get("vertical_connections", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return 0
	var count: int = 0
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link_doc: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			push_warning("Skipping unresolved vertical link %s" % str(link_doc.get("id", count)))
			continue
		var nav_link: NavigationLink3D = NavigationLink3D.new()
		nav_link.name = "VerticalLink_%s" % str(link_doc.get("id", count))
		nav_link.bidirectional = true
		nav_link.start_position = from_pos
		nav_link.end_position = to_pos
		ship_root.add_child(nav_link)
		count += 1
	return count


func _build_navigation_region(_rooms: Array, ship_root: Node3D) -> NavigationRegion3D:
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	var floor_cell_count: int = 0
	var structural_plan: Dictionary = layout_doc.get("structural_plan", {})
	var floors_variant: Variant = structural_plan.get("floor_placements", [])
	if typeof(floors_variant) != TYPE_ARRAY:
		return null
	for floor_variant in (floors_variant as Array):
		if typeof(floor_variant) != TYPE_DICTIONARY:
			continue
		var floor: Dictionary = floor_variant
		var module_id: String = str(floor.get("module_id", ""))
		if not FLOOR_MODULES.has(module_id):
			continue
		var pos: Array = _read_placement_position(floor)
		if pos.size() < 3:
			continue
		var cell_center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
		var half: float = CELL_SIZE * 0.5
		var faces: PackedVector3Array = PackedVector3Array([
			cell_center + Vector3(-half, 0.0, -half),
			cell_center + Vector3(half, 0.0, -half),
			cell_center + Vector3(half, 0.0, half),
			cell_center + Vector3(-half, 0.0, -half),
			cell_center + Vector3(half, 0.0, half),
			cell_center + Vector3(-half, 0.0, half),
		])
		source.add_faces(faces, Transform3D())
		floor_cell_count += 1

	if floor_cell_count == 0:
		push_error("no floor/corridor floor placements found for navigation mesh")
		return null

	var nav_mesh: NavigationMesh = NavigationMesh.new()
	NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, source)
	_orient_navigation_polygons_up(nav_mesh)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "GameplayNavigationRegion"
	ship_root.add_child(nav_region)
	nav_region.navigation_mesh = nav_mesh
	NavigationServer3D.region_set_navigation_mesh(nav_region.get_rid(), nav_mesh)
	var navigation_map := nav_region.get_navigation_map()
	if navigation_map.is_valid():
		NavigationServer3D.map_set_active(navigation_map, true)
	return nav_region


func _orient_navigation_polygons_up(nav_mesh: NavigationMesh) -> void:
	var vertices := nav_mesh.get_vertices()
	var polygons: Array[PackedInt32Array] = []
	for index in range(nav_mesh.get_polygon_count()):
		var polygon := nav_mesh.get_polygon(index)
		if polygon.size() >= 3:
			var a: Vector3 = vertices[polygon[0]]
			var b: Vector3 = vertices[polygon[1]]
			var c: Vector3 = vertices[polygon[2]]
			if (b - a).cross(c - a).y < 0.0:
				var reversed := PackedInt32Array()
				for vertex_index in range(polygon.size() - 1, -1, -1):
					reversed.append(polygon[vertex_index])
				polygon = reversed
		polygons.append(polygon)
	nav_mesh.clear_polygons()
	for polygon in polygons:
		nav_mesh.add_polygon(polygon)


func _read_placement_position(placement: Dictionary) -> Array:
	if typeof(placement) != TYPE_DICTIONARY:
		return []
	var raw: Variant = placement.get("position", null)
	if raw == null:
		raw = placement.get("world_position", null)
	if typeof(raw) == TYPE_VECTOR3:
		var vector: Vector3 = raw
		return [vector.x, vector.y, vector.z]
	if typeof(raw) == TYPE_STRING:
		var parsed: Array = _parse_vector_string(str(raw), 3)
		if parsed.size() == 3:
			return parsed
		return []
	if typeof(raw) != TYPE_ARRAY:
		return []
	var arr: Array = raw
	if arr.size() < 3:
		return []
	for i in range(3):
		var v: Variant = arr[i]
		var t: int = typeof(v)
		if t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_STRING:
			return []
		if t == TYPE_STRING and not String(v).is_valid_float():
			return []
	return arr


func _parse_vector_string(value: String, expected: int) -> Array:
	var text: String = value.strip_edges()
	if text.begins_with("(") and text.ends_with(")"):
		text = text.substr(1, text.length() - 2)
	var parts: PackedStringArray = text.split(",")
	if parts.size() != expected:
		return []
	var result: Array = []
	for part in parts:
		var token: String = part.strip_edges()
		if not token.is_valid_float():
			return []
		result.append(float(token))
	return result


func _room_center(_rooms: Array, room_id: String) -> Vector3:
	var structural_plan: Dictionary = layout_doc.get("structural_plan", {})
	var floors_variant: Variant = structural_plan.get("floor_placements", [])
	if typeof(floors_variant) != TYPE_ARRAY:
		return Vector3.INF
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for floor_variant in (floors_variant as Array):
		if typeof(floor_variant) != TYPE_DICTIONARY:
			continue
		var floor: Dictionary = floor_variant
		if str(floor.get("room_id", "")) != room_id:
			continue
		var pos: Array = _read_placement_position(floor)
		if pos.size() < 3:
			continue
		total += Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
		count += 1
	if count == 0:
		return Vector3.INF
	return total / float(count)


# --- Public metadata accessors -------------------------------------------------
# These are read-only views onto the loaded layout_doc. They are intentionally
# defensive: bad inputs (missing key, wrong type, unknown room) return safe
# defaults instead of raising. They never mutate the loader state.


func get_room_center(room_id: String) -> Vector3:
	if room_id.is_empty():
		return Vector3.INF
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	return _room_center(rooms_variant, room_id)


func get_room_role(room_id: String) -> String:
	if room_id.is_empty():
		return ""
	var room: Dictionary = _find_room_in_layout(room_id)
	if room.is_empty():
		return ""
	return str(room.get("room_role", ""))


func get_room_deck(room_id: String) -> int:
	if room_id.is_empty():
		return -1
	var room: Dictionary = _find_room_in_layout(room_id)
	if room.is_empty():
		return -1
	return int(room.get("deck", -1))


func get_critical_path() -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = layout_doc.get("critical_path", [])
	if typeof(raw) != TYPE_ARRAY:
		raw = gameplay_doc.get("critical_path", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in (raw as Array):
		out.append(str(entry))
	return out


func get_room_links() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("room_links", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for link in (raw as Array):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		out.append((link as Dictionary).duplicate(true))
	return out


func get_encounter_markers() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("encounters", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append((entry as Dictionary).duplicate(true))
	return out


func get_blocked_links() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("blocked_links", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for link in (raw as Array):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		out.append((link as Dictionary).duplicate(true))
	return out


func get_landmark_specs() -> Array:
	var out: Array = []
	var raw: Variant = layout_doc.get("landmarks", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for landmark in (raw as Array):
		if typeof(landmark) != TYPE_DICTIONARY:
			continue
		out.append((landmark as Dictionary).duplicate(true))
	return out


func get_landmark_nodes() -> Array[Node3D]:
	return landmark_nodes.duplicate()


func get_blocked_route_nodes() -> Array[Node3D]:
	return blocked_route_nodes.duplicate()


func get_visible_vertical_transition_nodes() -> Array[Node3D]:
	return visible_vertical_transition_nodes.duplicate()


func get_breach_zone_markers() -> Array[Vector3]:
	return breach_zone_markers.duplicate()


func get_breach_zone_specs() -> Array:
	return breach_zone_specs.duplicate(true)


func get_fire_zone_markers() -> Array[Vector3]:
	return fire_zone_markers.duplicate()


func get_room_variant_descriptors() -> Dictionary:
	return room_variant_descriptors.duplicate(true)


## Records the dressing descriptor for each room whose variant carries dressing
## (or a hazard/loot effect). PKG-B5.1 expands this with fog/tint/light/prop_density
## presets so the loader and HUD consume live visual parameters, not bare tags.
func _build_room_variant_descriptors() -> void:
	room_variant_descriptors.clear()
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if not (rooms_variant is Array):
		return
	var selector := RoomVariantSelectorDressScript.new()
	for room_variant in (rooms_variant as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var variant: String = str(room.get("variant", "standard"))
		var effects: Dictionary = selector.effects_for(variant)
		if effects.is_empty():
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		var dressing: String = str(effects.get("dressing", ""))
		var preset: Dictionary = selector.dressing_preset(dressing)
		var entry: Dictionary = {
			"variant": variant,
			"dressing": dressing,
			"prop_density": float(preset.get("prop_density", 1.0)),
			"fog_density": float(preset.get("fog_density", 0.0)),
			"light_energy": float(preset.get("light_energy", 0.5)),
		}
		var tint_v: Variant = preset.get("tint", [1.0, 1.0, 1.0, 1.0])
		if tint_v is Array and (tint_v as Array).size() >= 3:
			entry["tint"] = (tint_v as Array).duplicate()
		var light_v: Variant = preset.get("light_color", [1.0, 1.0, 1.0, 1.0])
		if light_v is Array and (light_v as Array).size() >= 3:
			entry["light_color"] = (light_v as Array).duplicate()
		room_variant_descriptors[rid] = entry


## PKG-B5.1: per-room OmniLight + fog at room centers; REQ-FILL-001 dressing
## props occupy unused wall_slots. Lights/fog stay at the room center.
func _apply_dressing_visuals(layout_doc: Dictionary, ship_root: Node3D) -> void:
	if ship_root == null or room_variant_descriptors.is_empty():
		return
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return
	var dressing_root := Node3D.new()
	dressing_root.name = "DressingVisuals"
	ship_root.add_child(dressing_root)
	var occupied: Dictionary = _dressing_occupied_cells(layout_doc, rooms_variant as Array)
	var seed_value: int = _seed_from_layout_doc(layout_doc)
	var room_index: int = 0
	for room_variant in (rooms_variant as Array):
		if typeof(room_variant) != TYPE_DICTIONARY:
			room_index += 1
			continue
		var room: Dictionary = room_variant
		var rid: String = str(room.get("id", ""))
		if rid.is_empty() or not room_variant_descriptors.has(rid):
			room_index += 1
			continue
		var desc: Dictionary = room_variant_descriptors[rid]
		var dressing: String = str(desc.get("dressing", ""))
		if dressing.is_empty():
			room_index += 1
			continue
		var center: Vector3 = _room_center(rooms_variant as Array, rid)
		if center == Vector3.INF:
			center = _room_center_from_cells(room)
		if center == Vector3.INF:
			room_index += 1
			continue
		var light := OmniLight3D.new()
		light.name = "DressingLight_%s" % rid
		light.position = center + Vector3(0.0, 2.0, 0.0)
		light.light_energy = float(desc.get("light_energy", 0.5))
		light.omni_range = 6.0
		var lc: Variant = desc.get("light_color", [1.0, 1.0, 1.0, 1.0])
		if lc is Array and (lc as Array).size() >= 3:
			light.light_color = Color(float(lc[0]), float(lc[1]), float(lc[2]), 1.0)
		light.set_meta("dressing", dressing)
		light.set_meta("prop_density", float(desc.get("prop_density", 1.0)))
		light.set_meta("fog_density", float(desc.get("fog_density", 0.0)))
		var tint: Variant = desc.get("tint", [])
		if tint is Array:
			light.set_meta("tint", (tint as Array).duplicate())
		dressing_root.add_child(light)
		# Lightweight fog marker mesh (visible volume cue pre-polish).
		var fog_density: float = float(desc.get("fog_density", 0.0))
		if fog_density > 0.001:
			var fog_marker := MeshInstance3D.new()
			fog_marker.name = "DressingFog_%s" % rid
			var sphere := SphereMesh.new()
			sphere.radius = 1.5 + fog_density * 20.0
			sphere.height = sphere.radius * 2.0
			fog_marker.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if tint is Array and (tint as Array).size() >= 3:
				mat.albedo_color = Color(float(tint[0]), float(tint[1]), float(tint[2]), clampf(fog_density * 4.0, 0.05, 0.35))
			else:
				mat.albedo_color = Color(0.5, 0.5, 0.5, 0.12)
			fog_marker.material_override = mat
			fog_marker.position = center + Vector3(0.0, 1.5, 0.0)
			fog_marker.set_meta("dressing", dressing)
			fog_marker.set_meta("fog_density", fog_density)
			dressing_root.add_child(fog_marker)
		_place_dressing_props(
			dressing_root,
			room,
			rid,
			dressing,
			float(desc.get("prop_density", 1.0)),
			occupied,
			seed_value,
			room_index
		)
		room_index += 1


func _room_center_from_cells(room: Dictionary) -> Vector3:
	var cells: Variant = room.get("cells", [])
	if not (cells is Array) or (cells as Array).is_empty():
		return Vector3.INF
	var total := Vector3.ZERO
	var n: int = 0
	var deck: int = int(room.get("deck", 0))
	for cell_v in (cells as Array):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_v)
		if parsed.size() < 2:
			continue
		total += Vector3(float(parsed[0]) * CELL_SIZE, float(deck) * 4.0 + FLOOR_Y_OFFSET, float(parsed[1]) * CELL_SIZE)
		n += 1
	if n <= 0:
		return Vector3.INF
	return total / float(n)


func _seed_from_layout_doc(layout: Dictionary) -> int:
	if layout.has("seed_value"):
		return int(layout.get("seed_value", 0))
	var pid: String = str(layout.get("program_id", ""))
	var idx: int = pid.rfind("seed-")
	if idx < 0:
		return 0
	var tail: String = pid.substr(idx + 5)
	var digits: String = ""
	for i in range(tail.length()):
		var ch: String = tail.substr(i, 1)
		if ch.is_valid_int():
			digits += ch
		else:
			break
	return int(digits) if digits.is_valid_int() else 0


func _dressing_occupied_cells(layout_doc: Dictionary, rooms: Array) -> Dictionary:
	var occupied: Dictionary = {}
	var start_room: String = str(layout_doc.get("prototype", {}).get("start_room", "")) if typeof(layout_doc.get("prototype", {})) == TYPE_DICTIONARY else ""
	if start_room.is_empty():
		start_room = str(gameplay_doc.get("start_room", ""))
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var rid: String = str(room.get("id", ""))
		var interior: Variant = room.get("interior_zones", {})
		if interior is Dictionary:
			var reserved_v: Variant = (interior as Dictionary).get("reserved_cells", [])
			if reserved_v is Array:
				for cell_v in (reserved_v as Array):
					var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_v)
					if parsed.size() >= 2:
						occupied["%s|%d|%d" % [rid, int(parsed[0]), int(parsed[1])]] = true
		if rid == start_room:
			var boarding: Array = GameplaySliceBuilderScript.boarding_cell_xz(room)
			if boarding.size() >= 2:
				occupied["%s|%d|%d" % [rid, int(boarding[0]), int(boarding[1])]] = true
	for loot_variant in loot_container_specs:
		if typeof(loot_variant) != TYPE_DICTIONARY:
			continue
		var loot: Dictionary = loot_variant
		var cell_v: Variant = loot.get("approach_cell", [])
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_v)
		if parsed.size() >= 2:
			occupied["%s|%d|%d" % [str(loot.get("room_id", "")), int(parsed[0]), int(parsed[1])]] = true
	var objectives_v: Variant = gameplay_doc.get("objectives", [])
	if objectives_v is Array:
		for obj_v in (objectives_v as Array):
			if typeof(obj_v) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = obj_v
			_occupy_approach(occupied, str(obj.get("room_id", "")), obj.get("approach_cell", []))
			var steps_v: Variant = obj.get("steps", [])
			if steps_v is Array:
				for step_v in (steps_v as Array):
					if typeof(step_v) != TYPE_DICTIONARY:
						continue
					var step: Dictionary = step_v
					_occupy_approach(
						occupied,
						str(step.get("room_id", obj.get("room_id", ""))),
						step.get("approach_cell", []))
	_reserve_component_slots(rooms, occupied)
	return occupied


func _occupy_approach(occupied: Dictionary, room_id: String, cell_v: Variant) -> void:
	var parsed: Array = LayoutSerializerScript.parse_slot_cell(cell_v)
	if parsed.size() < 2 or room_id.is_empty():
		return
	occupied["%s|%d|%d" % [room_id, int(parsed[0]), int(parsed[1])]] = true


func _reserve_component_slots(rooms: Array, occupied: Dictionary) -> void:
	# Components populate after dressing; hold the same 3 wall + 1 center cap
	# those fills will take so clutter cannot steal machine slots.
	# Small rooms (≤ MAX_WALL_FILLS free walls) keep one wall for dressing.
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		var interior: Variant = room.get("interior_zones", {})
		if not (interior is Dictionary):
			continue
		var walls: Dictionary = interior as Dictionary
		var wall_free: int = _unoccupied_slot_count(rid, walls, "wall_slots", occupied)
		var wall_cap: int = ComponentPlacementStateScript.MAX_WALL_FILLS
		if wall_free > 0 and wall_free <= ComponentPlacementStateScript.MAX_WALL_FILLS:
			wall_cap = maxi(0, wall_free - 1)
		_reserve_slot_kind(rid, walls, "wall_slots", wall_cap, occupied)
		_reserve_slot_kind(rid, walls, "center_slots", ComponentPlacementStateScript.MAX_CENTER_FILLS, occupied)


func _unoccupied_slot_count(rid: String, interior: Dictionary, slot_key: String, occupied: Dictionary) -> int:
	var slots_v: Variant = interior.get(slot_key, [])
	if not (slots_v is Array):
		return 0
	var n: int = 0
	for item in (slots_v as Array):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
		if parsed.size() < 2:
			continue
		var key: String = "%s|%d|%d" % [rid, int(parsed[0]), int(parsed[1])]
		if occupied.has(key):
			continue
		n += 1
	return n


func _reserve_slot_kind(rid: String, interior: Dictionary, slot_key: String, max_count: int, occupied: Dictionary) -> void:
	var slots_v: Variant = interior.get(slot_key, [])
	if not (slots_v is Array):
		return
	var kept: int = 0
	for item in (slots_v as Array):
		if kept >= max_count:
			break
		var parsed: Array = LayoutSerializerScript.parse_slot_cell(item)
		if parsed.size() < 2:
			continue
		var key: String = "%s|%d|%d" % [rid, int(parsed[0]), int(parsed[1])]
		if occupied.has(key):
			continue
		occupied[key] = true
		kept += 1


func _place_dressing_props(
		dressing_root: Node3D,
		room: Dictionary,
		rid: String,
		dressing: String,
		prop_density: float,
		occupied: Dictionary,
		seed_value: int,
		room_index: int) -> void:
	var interior: Variant = room.get("interior_zones", {})
	if not (interior is Dictionary):
		return
	var wall_v: Variant = (interior as Dictionary).get("wall_slots", [])
	if not (wall_v is Array) or (wall_v as Array).is_empty():
		return
	var available: Array = []
	for i in range((wall_v as Array).size()):
		var parsed: Array = LayoutSerializerScript.parse_slot_cell((wall_v as Array)[i])
		if parsed.size() < 2:
			continue
		var key: String = "%s|%d|%d" % [rid, int(parsed[0]), int(parsed[1])]
		if occupied.has(key):
			continue
		available.append({"cell": parsed, "index": i})
	if available.is_empty():
		return
	var count: int = clampi(int(round(float(available.size()) * prop_density)), 0, available.size())
	if prop_density > 0.001 and not available.is_empty():
		count = maxi(1, count)
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ int(room_index)) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var deck: int = int(room.get("deck", 0))
	for p in range(count):
		var slot: Dictionary = available[p]
		var cell: Array = slot.get("cell", [])
		var world: Vector3 = _room_cell_world(room, [int(cell[0]), int(cell[1]), deck])
		if world == Vector3.INF:
			world = Vector3(float(cell[0]) * CELL_SIZE, float(deck) * 4.0 + FLOOR_Y_OFFSET, float(cell[1]) * CELL_SIZE)
		var kind: String = DRESSING_PROP_KINDS[rng.randi_range(0, DRESSING_PROP_KINDS.size() - 1)]
		var prop: Node3D = _create_dressing_prop(rid, p, kind)
		prop.position = world
		prop.set_meta("dressing", dressing)
		prop.set_meta("slot_kind", "wall")
		prop.set_meta("slot_index", int(slot.get("index", p)))
		prop.set_meta("slot_cell", cell.duplicate())
		dressing_root.add_child(prop)
		occupied["%s|%d|%d" % [rid, int(cell[0]), int(cell[1])]] = true


func _create_dressing_prop(room_id: String, index: int, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingProp_%s_%d" % [room_id, index]
	root.set_meta("collision_policy", "none_visual_only")
	root.set_meta("dressing_kind", kind)
	root.set_meta("normal_mode_visual", true)
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "DressingMesh"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match kind:
		"pipe":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.12
			cyl.height = 1.4
			mesh_i.mesh = cyl
			mesh_i.position = Vector3(0.0, 0.7, 0.0)
			mesh_i.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			mat.albedo_color = Color(0.45, 0.48, 0.42)
		"growth":
			var sphere := SphereMesh.new()
			sphere.radius = 0.28
			sphere.height = 0.56
			mesh_i.mesh = sphere
			mesh_i.position = Vector3(0.0, 0.28, 0.0)
			mat.albedo_color = Color(0.42, 0.16, 0.22)
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.45, 0.55)
			mesh_i.mesh = box
			mesh_i.position = Vector3(0.0, 0.225, 0.0)
			mat.albedo_color = Color(0.55, 0.42, 0.28)
	mesh_i.material_override = mat
	root.add_child(mesh_i)
	return root


func _add_fire_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("fire_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		fire_zone_markers.append((from_pos + to_pos) * 0.5)
		fire_zone_specs.append(_normalize_zone_spec(zone))


# REQ-013 / ADR-0005: electrical-arc zone loader. Mirrors
# REQ-013 / ADR-0005 zone key normalization. The ADR names the shared
# zone identifier `zone_id` (docs/game/adr/0005-multi-hazard-architecture.md:63-68)
# so every hazard zone spec exposes a uniform `zone_id` key. The Alpha
# hand-authored layout fixtures use `id` (consistent with the
# `blocked_routes` and `vertical_connections` array entries) so we
# copy `id` -> `zone_id` here when the source spec only carries `id`.
# This preserves the existing fixture contract while aligning the
# loader output with the ADR-0005 HazardStateContract zone key.
# Existing spec fields (to_room, from_room, kind, rationale, etc.) are
# left untouched so consumer code that reads them keeps working.
func _normalize_zone_spec(zone: Dictionary) -> Dictionary:
	var out: Dictionary = zone.duplicate(true)
	if not out.has("zone_id") and out.has("id"):
		var id_value: Variant = out["id"]
		if id_value is String or id_value is StringName:
			var zone_id: String = str(id_value)
			if not zone_id.is_empty():
				out["zone_id"] = zone_id
	return out


# _add_fire_zone_markers() but only emits positions / specs for the
# hand-authored Alpha template markers. No fallback is injected because
# arc placement is template-specific (per hazard_type_3.md).
func _add_arc_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("arc_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		arc_zone_markers.append((from_pos + to_pos) * 0.5)
		arc_zone_specs.append(_normalize_zone_spec(zone))


func _add_radiation_zone_markers(source_layout: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = source_layout.get("radiation_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", source_layout)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", source_layout)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", source_layout)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", source_layout)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var midpoint: Vector3 = (from_pos + to_pos) * 0.5
		radiation_zone_markers.append(midpoint)
		radiation_zone_specs.append(_normalize_zone_spec(zone))
		radiation_zone_segments.append({"from": from_pos, "to": to_pos})
		var length: float = maxf(
			RADIATION_VOLUME_AXIAL_END_PADDING * 2.0,
			from_pos.distance_to(to_pos) + RADIATION_VOLUME_AXIAL_END_PADDING * 2.0)
		ship_root.add_child(_make_oriented_trigger_volume(
			"RadiationZone_%s" % str(zone.get("id", radiation_zone_markers.size() - 1)), midpoint,
			Color(0.65, 0.2, 0.9, 0.3), Vector3(length, 2.5, 2.5), from_pos, to_pos))


func _add_authored_atmosphere_volumes(source_layout: Dictionary, ship_root: Node3D) -> void:
	var rooms_variant: Variant = source_layout.get("rooms", [])
	var plan_variant: Variant = source_layout.get("structural_plan", {})
	if typeof(rooms_variant) != TYPE_ARRAY or typeof(plan_variant) != TYPE_DICTIONARY:
		return
	var floors_variant: Variant = (plan_variant as Dictionary).get("floor_placements", [])
	if typeof(floors_variant) != TYPE_ARRAY:
		return
	for floor_variant in floors_variant:
		if typeof(floor_variant) != TYPE_DICTIONARY:
			continue
		var floor: Dictionary = floor_variant
		var room_id: String = str(floor.get("room_id", ""))
		var room: Dictionary = _find_room(rooms_variant as Array, room_id)
		if room.is_empty() or not _room_has_atmosphere(room):
			continue
		var position_array: Array = _read_placement_position(floor)
		if position_array.size() < 3:
			continue
		var position := Vector3(float(position_array[0]), float(position_array[1]) + FLOOR_Y_OFFSET, float(position_array[2]))
		var spec: Dictionary = {
			"room_id": room_id,
			"position": position,
			"oxygen_bp": int(room.get("atmosphere_bp", room.get("oxygen_bp", 10000))),
			"depressurized": bool(room.get("depressurized", false)),
			"vented": bool(room.get("vented", false)),
			"radiation_bp": int(room.get("radiation_bp", 0)),
		}
		if room.has("temperature_c"):
			spec["temperature_c"] = float(room["temperature_c"])
		authored_atmosphere_specs.append(spec)
		var volume := _make_trigger_volume(
			"AuthoredAtmosphere_%s_%d" % [room_id, authored_atmosphere_specs.size() - 1], position,
			Color(0.15, 0.7, 0.9, 0.08), Vector3(CELL_SIZE, 2.5, CELL_SIZE))
		volume.set_meta("atmosphere", spec.duplicate(true))
		ship_root.add_child(volume)
		authored_atmosphere_volumes.append(volume)


func _room_has_atmosphere(room: Dictionary) -> bool:
	return room.has("atmosphere_bp") or room.has("oxygen_bp") or room.has("depressurized") or room.has("vented") or room.has("radiation_bp") or room.has("temperature_c")


func _runtime_portal_sources(source_layout: Dictionary) -> Array:
	var authored_by_edge: Dictionary = {}
	var authored_variant: Variant = source_layout.get("portals", source_layout.get("connections", []))
	if typeof(authored_variant) == TYPE_ARRAY:
		for raw in authored_variant as Array:
			if raw is Dictionary:
				var authored: Dictionary = raw as Dictionary
				var authored_key: String = str(authored.get("edge_key", ""))
				if not authored_key.is_empty():
					authored_by_edge[authored_key] = authored.duplicate(true)
	var plan_variant: Variant = source_layout.get("structural_plan", {})
	if typeof(plan_variant) != TYPE_DICTIONARY:
		return (authored_variant as Array).duplicate(true) if authored_variant is Array else []
	var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
	if typeof(edges_variant) != TYPE_DICTIONARY:
		return (authored_variant as Array).duplicate(true) if authored_variant is Array else []
	var sources: Array = []
	for edge_raw in (edges_variant as Dictionary).values():
		if not (edge_raw is Dictionary):
			continue
		var edge: Dictionary = edge_raw as Dictionary
		if not bool(edge.get("portal", false)):
			continue
		var edge_key: String = str(edge.get("edge_key", edge.get("key", "")))
		var source: Dictionary = (authored_by_edge.get(edge_key, {}) as Dictionary).duplicate(true)
		source["id"] = str(source.get("id", "edge:%s" % edge_key))
		source["edge_key"] = edge_key
		source["state"] = str(edge.get("kind", source.get("state", "DOOR")))
		source["kind"] = source["state"]
		source["exterior"] = bool(edge.get("exterior", source.get("exterior", false)))
		source["yaw_degrees"] = float(edge.get("yaw_degrees", source.get("yaw_degrees", 0.0)))
		var source_cells: Variant = edge.get("source_cells", [])
		if source_cells is Array and (source_cells as Array).size() >= 2:
			source["from_cell"] = (source_cells as Array)[0]
			source["to_cell"] = (source_cells as Array)[1]
		var room_ids: Variant = edge.get("room_ids", [])
		if room_ids is Array and (room_ids as Array).size() >= 2:
			source["from_room"] = str((room_ids as Array)[0])
			source["to_room"] = str((room_ids as Array)[1])
		sources.append(source)
	return sources


func _add_authored_portal_runtime_nodes(source_layout: Dictionary, ship_root: Node3D) -> void:
	var portal_sources: Array = _runtime_portal_sources(source_layout)
	if ship_root == null:
		return
	for index in range(portal_sources.size()):
		var source: Dictionary = portal_sources[index] as Dictionary
		var from_pos := _cell_world_from_link_endpoint(source, "from_cell", "from_room", source_layout)
		var to_pos := _cell_world_from_link_endpoint(source, "to_cell", "to_room", source_layout)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(source, "from_room", source_layout)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(source, "to_room", source_layout)
		if from_pos == Vector3.INF and to_pos == Vector3.INF:
			continue
		var endpoint_midpoint := to_pos if from_pos == Vector3.INF else from_pos if to_pos == Vector3.INF else (from_pos + to_pos) * 0.5
		var spec := source.duplicate(true)
		spec["runtime_position"] = endpoint_midpoint
		spec["from_position"] = from_pos
		spec["to_position"] = to_pos
		var portal := AuthoredPortalRuntimeScript.new()
		portal.name = "AuthoredPortal_%s" % str(source.get("id", index))
		portal.configure(spec, endpoint_midpoint)
		ship_root.add_child(portal)
		if portal.portal_kind == "LOCKED" or portal.portal_kind == "HATCH":
			var structural_blocker := _find_structural_portal_blocker(
				ship_root, str(spec.get("edge_key", "")), portal.portal_kind)
			if structural_blocker != null:
				portal.bind_structural_blocker(structural_blocker)
		authored_portal_specs.append(spec)
		authored_portal_nodes.append(portal)


func _find_structural_portal_blocker(ship_root: Node3D, edge_key: String, portal_kind: String) -> Node3D:
	if ship_root == null or edge_key.is_empty():
		return null
	var expected_module := "doorway_frame_blocked_1x1" if portal_kind == "LOCKED" else "bulkhead_portal_2x1"
	for child in ship_root.get_children():
		if child is Node3D \
				and str(child.get_meta("structural_edge_key", "")) == edge_key \
				and str(child.get_meta("module_kind", "")) == expected_module:
			return child as Node3D
	return null


## Materialize builder-authored visuals only. Structural doors and vertical
## links are compiled elsewhere and deliberately never become placed props.
## A placement is anchored to its authored room/cell so it follows the same
## compiled floor coordinates as objectives and loot containers.
func _add_authored_placed_props(source_layout: Dictionary, source_gameplay: Dictionary, ship_root: Node3D) -> void:
	var raw_variant: Variant = source_gameplay.get("placed_props", [])
	if typeof(raw_variant) != TYPE_ARRAY or ship_root == null:
		return
	var prop_catalog: Dictionary = GameplayPropFactoryScript.load_catalog().get("props", {}) as Dictionary
	var visual_catalog = PropVisualBindingCatalogScript.new()
	var visual_catalog_loaded: bool = visual_catalog.load_from_path()
	for raw_prop in (raw_variant as Array):
		if typeof(raw_prop) != TYPE_DICTIONARY:
			continue
		var authored: Dictionary = raw_prop as Dictionary
		var prop_id: String = str(authored.get("visual_id", "")).strip_edges()
		if prop_id.is_empty():
			prop_id = str(authored.get("prop_id", authored.get("asset_id", authored.get("proto", "")))).strip_edges()
		if prop_id.is_empty():
			continue
		var room_id: String = str(authored.get("room_id", "")).strip_edges()
		var cell_variant: Variant = authored.get("cell", authored.get("approach_cell", []))
		if room_id.is_empty() or typeof(cell_variant) != TYPE_ARRAY:
			continue
		var cell: Array = cell_variant as Array
		if cell.size() < 2:
			continue
		var room: Dictionary = _find_room(source_layout.get("rooms", []) as Array, room_id)
		if room.is_empty():
			continue
		var position: Vector3 = _room_cell_world(room, cell)
		if position == Vector3.INF:
			continue
		var dressing_binding: Dictionary = visual_catalog.get_dressing_binding(prop_id) \
			if visual_catalog_loaded else {}
		if not prop_catalog.has(prop_id) and dressing_binding.is_empty():
			placed_prop_errors.append("unknown authored placed prop visual_id '%s'" % prop_id)
			continue
		var quarter_turns: int = 0
		if authored.has("quarter_turn"):
			quarter_turns = int(authored.get("quarter_turn", 0))
		elif authored.has("rotation"):
			quarter_turns = int(authored.get("rotation", 0))
		elif authored.has("yaw_degrees"):
			quarter_turns = roundi(float(authored.get("yaw_degrees", 0.0)) / 90.0)
		quarter_turns = posmod(quarter_turns, 4)
		var spec: Dictionary = authored.duplicate(true)
		spec["visual_id"] = prop_id
		spec["room_id"] = room_id
		spec["cell"] = cell.duplicate(true)
		spec["position"] = position
		spec["quarter_turn"] = quarter_turns
		var prop: Node3D
		if not dressing_binding.is_empty():
			var imported_visual: Node3D = RuntimePropVisualBinderScript.create_dressing_visual(dressing_binding)
			if imported_visual == null:
				placed_prop_errors.append("authored placed prop visual_id '%s' could not be materialized" % prop_id)
				continue
			prop = Node3D.new()
			prop.position = position
			prop.add_child(imported_visual)
		else:
			prop = GameplayPropFactoryScript.build(prop_id, position)
		prop.name = "PlacedProp_%s" % str(authored.get("id", placed_prop_specs.size()))
		prop.rotation_degrees.y = float(quarter_turns * 90)
		prop.set_meta("placed_prop", spec.duplicate(true))
		prop.set_meta("placed_prop_id", str(authored.get("id", "")))
		prop.set_meta("authored_position", position)
		ship_root.add_child(prop)
		placed_prop_specs.append(spec)
		placed_prop_nodes.append(prop)


func _make_trigger_volume(node_name: String, world_position: Vector3, color: Color, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = node_name
	area.position = world_position
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 0
	area.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position.y = size.y * 0.5
	area.add_child(shape_node)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.position.y = size.y * 0.5
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_node.material_override = material
	area.add_child(mesh_node)
	return area


func _make_oriented_trigger_volume(
	node_name: String, world_position: Vector3, color: Color, size: Vector3,
	from_pos: Vector3, to_pos: Vector3) -> Area3D:
	var area := _make_trigger_volume(node_name, world_position, color, size)
	var segment := to_pos - from_pos
	if segment.length_squared() > 0.000001:
		area.quaternion = Quaternion(Vector3.RIGHT, segment.normalized())
	return area


func get_fire_zone_specs() -> Array:
	return fire_zone_specs.duplicate(true)


# REQ-013 / ADR-0005: electrical-arc zone contract. Mirror of the
# fire-zone accessors above: a list of world-space arc-zone midpoints
# resolved from the layout's `arc_zones` array, plus the full marker
# dictionaries for callers that need the to_room/cell context.
func get_arc_zone_markers() -> Array[Vector3]:
	return arc_zone_markers.duplicate()


func get_arc_zone_specs() -> Array:
	return arc_zone_specs.duplicate(true)


func get_radiation_zone_markers() -> Array[Vector3]:
	return radiation_zone_markers.duplicate()


func get_radiation_zone_specs() -> Array:
	return radiation_zone_specs.duplicate(true)


func get_radiation_zone_segments() -> Array:
	return radiation_zone_segments.duplicate(true)


func get_radiation_zone_at(local_position: Vector3, radius: float = RADIATION_VOLUME_HALF_WIDTH) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	var half_width := maxf(0.0, radius)
	for index in range(radiation_zone_markers.size()):
		var contains := false
		if index < radiation_zone_segments.size() and radiation_zone_segments[index] is Dictionary:
			var segment: Dictionary = radiation_zone_segments[index]
			var from_pos: Variant = segment.get("from", Vector3.INF)
			var to_pos: Variant = segment.get("to", Vector3.INF)
			if from_pos is Vector3 and to_pos is Vector3:
				contains = _point_in_radiation_box(local_position, from_pos, to_pos, half_width)
		else:
			contains = local_position.distance_to(radiation_zone_markers[index]) <= half_width
		var distance: float = local_position.distance_to(radiation_zone_markers[index])
		if contains and distance <= best_distance:
			best_distance = distance
			if index < radiation_zone_specs.size() and radiation_zone_specs[index] is Dictionary:
				best = (radiation_zone_specs[index] as Dictionary).duplicate(true)
	return best


func _point_in_radiation_box(point: Vector3, from_pos: Vector3, to_pos: Vector3, half_width: float) -> bool:
	var segment := to_pos - from_pos
	var midpoint := (from_pos + to_pos) * 0.5
	var basis := Basis.IDENTITY
	if segment.length_squared() > 0.000001:
		basis = Basis(Quaternion(Vector3.RIGHT, segment.normalized()))
	var box_position := basis.inverse() * (point - midpoint)
	var half_length := maxf(
		RADIATION_VOLUME_AXIAL_END_PADDING,
		segment.length() * 0.5 + RADIATION_VOLUME_AXIAL_END_PADDING)
	return absf(box_position.x) <= half_length \
			and absf(box_position.y) <= half_width \
			and absf(box_position.z) <= half_width


func get_authored_atmosphere_at(local_position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for spec_variant in authored_atmosphere_specs:
		if not (spec_variant is Dictionary):
			continue
		var spec: Dictionary = spec_variant
		var placement_position: Variant = spec.get("position", Vector3.INF)
		if not (placement_position is Vector3):
			continue
		var delta: Vector3 = local_position - placement_position
		var within_box := absf(delta.x) <= ATMOSPHERE_VOLUME_HALF_WIDTH \
			and delta.y >= 0.0 and delta.y <= ATMOSPHERE_VOLUME_HEIGHT \
			and absf(delta.z) <= ATMOSPHERE_VOLUME_HALF_WIDTH
		var distance: float = delta.length_squared()
		if within_box and distance < best_distance:
			best_distance = distance
			best = spec.duplicate(true)
	return best


func get_authored_atmosphere_drain_multiplier_at(local_position: Vector3) -> float:
	var atmosphere: Dictionary = get_authored_atmosphere_at(local_position)
	if atmosphere.is_empty():
		return 1.0
	# A vented compartment is depressurized even when older authored documents
	# omit oxygen_bp and depressurized. Keep this semantic at the loader boundary
	# so every runtime consumer observes the same hostile atmosphere.
	if bool(atmosphere.get("depressurized", false)) or bool(atmosphere.get("vented", false)):
		return 1.0
	var oxygen_bp: float = clampf(float(atmosphere.get("oxygen_bp", 10000)), 0.0, 10000.0)
	return clampf(1.0 - oxygen_bp / 10000.0, 0.0, 1.0)


func _find_room_in_layout(room_id: String) -> Dictionary:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return {}
	return _find_room(rooms_variant, room_id)


# --- Coherence runtime marker nodes --------------------------------------------
# Build visual + (optionally) collidable marker nodes for landmarks, blocked
# routes, and visible vertical transitions. These are added under
# `structural_root` so they live in the same world transform as the structural
# wrappers. Marker names follow the convention
# `Landmark_<id>` / `BlockedRoute_<id>` / `VisibleVerticalTransition_<id>` so
# downstream capture/proof code can locate them by name.

const _LANDMARK_COLOR: Color = Color(0.15, 0.65, 1.0, 1.0)
const _BLOCKED_ROUTE_COLOR: Color = Color(0.85, 0.2, 0.18, 1.0)
const _VERTICAL_TRANSITION_COLOR: Color = Color(0.9, 0.68, 0.25, 1.0)
const _LANDMARK_SIZE: Vector3 = Vector3(0.8, 2.4, 0.8)
const _BLOCKED_ROUTE_SIZE: Vector3 = Vector3(3.8, 2.0, 0.45)
const _VERTICAL_TRANSITION_SIZE: Vector3 = Vector3(4.0, 0.45, 5.5)


func _add_coherence_runtime_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	_add_landmark_nodes(layout_doc, ship_root)
	_add_blocked_route_nodes(layout_doc, ship_root)
	_add_visible_vertical_transition_nodes(layout_doc, ship_root)
	_add_breach_zone_markers(layout_doc, ship_root)
	_add_fire_zone_markers(layout_doc, ship_root)
	_add_arc_zone_markers(layout_doc, ship_root)
	_add_radiation_zone_markers(layout_doc, ship_root)
	_add_authored_atmosphere_volumes(layout_doc, ship_root)


func _add_landmark_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var landmarks_variant: Variant = layout_doc.get("landmarks", [])
	if typeof(landmarks_variant) != TYPE_ARRAY:
		return
	for landmark_variant in landmarks_variant:
		if typeof(landmark_variant) != TYPE_DICTIONARY:
			continue
		var landmark: Dictionary = landmark_variant
		var pos: Vector3 = _vec3_from_array(landmark.get("position", []), Vector3.INF)
		if pos == Vector3.INF:
			continue
		var node: Node3D = _make_marker_node(
			"Landmark_%s" % str(landmark.get("id", landmark_nodes.size())),
			pos,
			_LANDMARK_COLOR,
			_LANDMARK_SIZE,
			true
		)
		ship_root.add_child(node)
		landmark_nodes.append(node)


func _add_blocked_route_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("blocked_links", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		# Cell positions are the precise source of truth, but a coherent
		# fixture may declare blocked links at cells whose structural
		# placements live in another room. Fall back to the room center so
		# the marker still appears at a meaningful position rather than
		# being silently dropped.
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(link, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(link, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node(
			"BlockedRoute_%s" % str(link.get("id", blocked_route_nodes.size())),
			mid,
			_BLOCKED_ROUTE_COLOR,
			_BLOCKED_ROUTE_SIZE,
			true
		)
		ship_root.add_child(node)
		# `look_at` in Godot 4.6.2 prints "Node not inside tree" even after
		# `add_child` in headless script contexts (the deferred enter-tree
		# notification has not yet fired). Use `look_at_from_position` with
		# the current global transform so we get the same visual orientation
		# without the warning. Guard against coincident endpoints (zero-length
		# direction) which would print a transform error.
		if (to_pos - mid).length_squared() > 0.0001:
			node.look_at_from_position(mid, to_pos, Vector3.UP)
		blocked_route_nodes.append(node)


func _add_visible_vertical_transition_nodes(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var links_variant: Variant = layout_doc.get("vertical_connections", [])
	if typeof(links_variant) != TYPE_ARRAY:
		return
	for link_variant in links_variant:
		if typeof(link_variant) != TYPE_DICTIONARY:
			continue
		var link: Dictionary = link_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(link, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(link, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var mid: Vector3 = (from_pos + to_pos) * 0.5
		var node: Node3D = _make_marker_node(
			"VisibleVerticalTransition_%s" % str(link.get("id", visible_vertical_transition_nodes.size())),
			mid,
			_VERTICAL_TRANSITION_COLOR,
			_VERTICAL_TRANSITION_SIZE,
			true
		)
		ship_root.add_child(node)
		if (to_pos - mid).length_squared() > 0.0001:
			var up_vector: Vector3 = Vector3.UP
			# Vertical transitions often run purely along world Y; using
			# Vector3.UP as the up reference would make target/up colinear
			# and produce a warning. Pick a horizontal up reference so the
			# transition marker still orients to the ramp direction.
			if absf((to_pos - mid).normalized().dot(Vector3.UP)) > 0.999:
				up_vector = Vector3.FORWARD
			node.look_at_from_position(mid, to_pos, up_vector)
		visible_vertical_transition_nodes.append(node)


func _add_breach_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("breach_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		var midpoint: Vector3 = (from_pos + to_pos) * 0.5
		breach_zone_markers.append(midpoint)
		var spec: Dictionary = _normalize_zone_spec(zone)
		spec["position"] = midpoint
		breach_zone_specs.append(spec)


func _room_center_for_blocked_link(link: Dictionary, room_key: String, layout_doc: Dictionary) -> Vector3:
	# Fallback when `_cell_world_from_link_endpoint` cannot resolve the cell:
	# a coherent fixture may declare a blocked link at a cell that is the
	# "open end" of one of its rooms (e.g. a z-side cell with no floor
	# placement). Returning the room center keeps the marker inside the room
	# it belongs to so the visual still anchors correctly.
	var room_id: String = str(link.get(room_key, ""))
	if room_id.is_empty():
		return Vector3.INF
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return Vector3.INF
	return _room_center(rooms_variant, room_id)


func _make_marker_node(node_name: String, world_position: Vector3, color: Color, size: Vector3, collidable: bool) -> Node3D:
	# Build the marker using local `position` (not `global_position`) and a
	# pre-computed basis. The caller is going to add this node as a child of
	# `structural_root`, which is at world origin, so local == world space.
	# Using local position + pre-baked basis avoids Godot 4.6.2 warnings about
	# `get_global_transform` / `look_at` on nodes that are not inside the tree.
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.position = world_position
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	mesh_instance.material_override = material
	mesh_instance.position.y = size.y * 0.5
	root.add_child(mesh_instance)
	if collidable:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "CollisionRoot"
		body.collision_layer = 1
		body.collision_mask = 1
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		shape_node.position.y = size.y * 0.5
		body.add_child(shape_node)
		root.add_child(body)
	return root


func _vec3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var array: Array = value
	if array.size() < 3:
		return fallback
	var v0: Variant = array[0]
	var v1: Variant = array[1]
	var v2: Variant = array[2]
	var t0: int = typeof(v0)
	var t1: int = typeof(v1)
	var t2: int = typeof(v2)
	if t0 != TYPE_INT and t0 != TYPE_FLOAT:
		return fallback
	if t1 != TYPE_INT and t1 != TYPE_FLOAT:
		return fallback
	if t2 != TYPE_INT and t2 != TYPE_FLOAT:
		return fallback
	return Vector3(float(v0), float(v1), float(v2))
