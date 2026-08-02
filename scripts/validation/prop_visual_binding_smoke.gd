extends SceneTree

const PropVisualBindingCatalogScript := preload("res://scripts/systems/prop_visual_binding_catalog.gd")
const RuntimePropVisualBinderScript := preload("res://scripts/procgen/runtime_prop_visual_binder.gd")
const ProcgenDebugRunnerScript := preload("res://scripts/procgen/procgen_debug_runner.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")

func _initialize() -> void:
	var failures: int = 0
	var catalog = PropVisualBindingCatalogScript.new()
	failures += _expect(catalog.load_from_path(), "catalog loads generated index")
	var component_binding: Dictionary = catalog.get_component_binding("reactor_console")
	var objective_binding: Dictionary = catalog.get_objective_binding("reactor_control_panel")
	var dressing_binding: Dictionary = catalog.get_dressing_binding("cable_tray")
	failures += _expect(not component_binding.is_empty(), "reactor console resolves")
	failures += _expect(not objective_binding.is_empty(), "reactor panel resolves")
	failures += _expect(not dressing_binding.is_empty(), "cable tray dressing resolves")
	var dressing_meta: Dictionary = dressing_binding.get("binding", {}) as Dictionary
	failures += _expect(
		str(dressing_meta.get("namespace", "")) == "visual_prop_id",
		"dressing uses visual_prop_id namespace",
	)
	failures += _expect(catalog.get_component_binding("missing_component").is_empty(), "unknown component is empty")
	failures += _expect(catalog.get_objective_binding("bridge_power_distribution").is_empty(), "unmapped objective is empty")
	failures += _expect(catalog.get_dressing_binding("missing_dressing").is_empty(), "unknown dressing is empty")

	var valid_document: Dictionary = _catalog_document(component_binding, objective_binding, dressing_binding)
	var objective_surface_document: Dictionary = valid_document.duplicate(true)
	var objective_surface_binding: Dictionary = objective_binding.duplicate(true)
	var objective_surface_placement: Dictionary = (objective_surface_binding["placement"] as Dictionary).duplicate(true)
	objective_surface_placement["surface"] = "floor"
	objective_surface_binding["placement"] = objective_surface_placement
	(objective_surface_document["objectives"] as Dictionary)["reactor_control_panel"] = objective_surface_binding
	failures += _expect_catalog_accepted(
		objective_surface_document,
		"user://task5-objective-valid-surface.json",
		"objective surface is optional and valid enum is accepted",
	)
	var objective_surface_visual: Node3D = RuntimePropVisualBinderScript.create_objective_visual(objective_surface_binding)
	failures += _expect(
		objective_surface_visual != null,
		"binder accepts objective binding with valid surface",
	)
	var dressing_without_surface_document: Dictionary = valid_document.duplicate(true)
	var dressing_without_surface_binding: Dictionary = dressing_binding.duplicate(true)
	var dressing_without_surface_placement: Dictionary = (dressing_without_surface_binding["placement"] as Dictionary).duplicate(true)
	dressing_without_surface_placement.erase("surface")
	dressing_without_surface_binding["placement"] = dressing_without_surface_placement
	(dressing_without_surface_document["dressing"] as Dictionary)["cable_tray"] = dressing_without_surface_binding
	failures += _expect_catalog_accepted(
		dressing_without_surface_document,
		"user://task5-dressing-no-surface.json",
		"dressing surface is optional",
	)
	var marker_anchor_document: Dictionary = valid_document.duplicate(true)
	var marker_anchor_objective: Dictionary = objective_binding.duplicate(true)
	var marker_anchor_placement: Dictionary = (marker_anchor_objective["placement"] as Dictionary).duplicate(true)
	marker_anchor_placement["origin"] = "marker_anchor"
	marker_anchor_objective["placement"] = marker_anchor_placement
	(marker_anchor_document["objectives"] as Dictionary)["reactor_control_panel"] = marker_anchor_objective
	failures += _expect_catalog_accepted(
		marker_anchor_document,
		"user://task5-marker-anchor.json",
		"schema-supported marker_anchor origin is accepted",
	)
	var invalid_surface_document: Dictionary = valid_document.duplicate(true)
	var invalid_surface_dressing: Dictionary = dressing_binding.duplicate(true)
	var invalid_surface_placement: Dictionary = (invalid_surface_dressing["placement"] as Dictionary).duplicate(true)
	invalid_surface_placement["surface"] = "deck"
	invalid_surface_dressing["placement"] = invalid_surface_placement
	(invalid_surface_document["dressing"] as Dictionary)["cable_tray"] = invalid_surface_dressing
	failures += _expect_catalog_rejected(
		invalid_surface_document,
		"user://task5-invalid-surface.json",
		"dressing surface is restricted to floor wall or ceiling",
	)
	var invalid_objective_surface_document: Dictionary = valid_document.duplicate(true)
	var invalid_objective_surface: Dictionary = objective_binding.duplicate(true)
	var invalid_objective_placement: Dictionary = (invalid_objective_surface["placement"] as Dictionary).duplicate(true)
	invalid_objective_placement["surface"] = "deck"
	invalid_objective_surface["placement"] = invalid_objective_placement
	(invalid_objective_surface_document["objectives"] as Dictionary)["reactor_control_panel"] = invalid_objective_surface
	failures += _expect_catalog_rejected(
		invalid_objective_surface_document,
		"user://task5-invalid-objective-surface.json",
		"objective surface is restricted to floor wall or ceiling",
	)
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(invalid_objective_surface) == null,
		"binder rejects objective binding with invalid surface",
	)
	var invalid_asset_document: Dictionary = valid_document.duplicate(true)
	var invalid_asset_component: Dictionary = component_binding.duplicate(true)
	invalid_asset_component["asset_id"] = "ReactorConsole"
	invalid_asset_component["visual_scene_path"] = "res://assets/imported/props/components/ReactorConsole.glb"
	var invalid_asset_meta: Dictionary = (invalid_asset_component["binding"] as Dictionary).duplicate(true)
	invalid_asset_meta["ids"] = ["ReactorConsole"]
	invalid_asset_component["binding"] = invalid_asset_meta
	(invalid_asset_document["components"] as Dictionary)["ReactorConsole"] = invalid_asset_component
	failures += _expect_catalog_rejected(
		invalid_asset_document,
		"user://task5-invalid-asset-id.json",
		"asset_id must match the canonical lowercase identifier grammar",
	)
	var extra_root: Dictionary = valid_document.duplicate(true)
	extra_root["unexpected_root_field"] = true
	failures += _expect_catalog_rejected(extra_root, "user://task5-extra-root.json", "extra catalog root field is rejected")
	var malformed_schema: Dictionary = valid_document.duplicate(true)
	malformed_schema["schema_version"] = "1.0"
	failures += _expect_catalog_rejected(malformed_schema, "user://task5-malformed-schema.json", "malformed catalog schema is rejected")
	var malformed_kind: Dictionary = valid_document.duplicate(true)
	malformed_kind["document_kind"] = "prop_visual_binding"
	failures += _expect_catalog_rejected(malformed_kind, "user://task5-malformed-kind.json", "malformed catalog document kind is rejected")
	var malformed_path: Dictionary = valid_document.duplicate(true)
	var malformed_component: Dictionary = component_binding.duplicate(true)
	malformed_component["visual_scene_path"] = "res://assets/imported/props/components/../reactor_console.glb"
	(malformed_path["components"] as Dictionary)["reactor_console"] = malformed_component
	failures += _expect_catalog_rejected(malformed_path, "user://task5-malformed-path.json", "noncanonical catalog scene path is rejected")
	var malformed_namespace: Dictionary = valid_document.duplicate(true)
	var malformed_dressing: Dictionary = dressing_binding.duplicate(true)
	var malformed_dressing_binding: Dictionary = (malformed_dressing["binding"] as Dictionary).duplicate(true)
	malformed_dressing_binding["namespace"] = "component_id"
	malformed_dressing["binding"] = malformed_dressing_binding
	(malformed_namespace["dressing"] as Dictionary)["cable_tray"] = malformed_dressing
	failures += _expect_catalog_rejected(malformed_namespace, "user://task5-malformed-namespace.json", "namespace/map mismatch is rejected")

	var malformed_source: Dictionary = valid_document.duplicate(true)
	var malformed_source_component: Dictionary = component_binding.duplicate(true)
	var malformed_source_meta: Dictionary = (malformed_source_component["source"] as Dictionary).duplicate(true)
	malformed_source_meta["byte_size"] = "not-an-integer"
	malformed_source_component["source"] = malformed_source_meta
	(malformed_source["components"] as Dictionary)["reactor_console"] = malformed_source_component
	failures += _expect_catalog_rejected(malformed_source, "user://task5-malformed-source.json", "invalid source metadata is rejected")

	var malformed_hash: Dictionary = valid_document.duplicate(true)
	var malformed_hash_component: Dictionary = component_binding.duplicate(true)
	var malformed_hash_source: Dictionary = (malformed_hash_component["source"] as Dictionary).duplicate(true)
	malformed_hash_source["sha256"] = "not-a-sha256"
	malformed_hash_component["source"] = malformed_hash_source
	(malformed_hash["components"] as Dictionary)["reactor_console"] = malformed_hash_component
	failures += _expect_catalog_rejected(malformed_hash, "user://task5-malformed-hash.json", "invalid source hash is rejected")
	var zero_hash: Dictionary = valid_document.duplicate(true)
	var zero_hash_component: Dictionary = component_binding.duplicate(true)
	var zero_hash_source: Dictionary = (zero_hash_component["source"] as Dictionary).duplicate(true)
	zero_hash_source["sha256"] = "0".repeat(64)
	zero_hash_component["source"] = zero_hash_source
	(zero_hash["components"] as Dictionary)["reactor_console"] = zero_hash_component
	failures += _expect_catalog_rejected(zero_hash, "user://task5-zero-hash.json", "all-zero source hash is rejected")

	var malformed_bounds: Dictionary = valid_document.duplicate(true)
	var malformed_bounds_component: Dictionary = component_binding.duplicate(true)
	var malformed_bounds_meta: Dictionary = (malformed_bounds_component["bounds"] as Dictionary).duplicate(true)
	malformed_bounds_meta["local_min_m"] = [0.0, 0.0]
	malformed_bounds_component["bounds"] = malformed_bounds_meta
	(malformed_bounds["components"] as Dictionary)["reactor_console"] = malformed_bounds_component
	failures += _expect_catalog_rejected(malformed_bounds, "user://task5-malformed-bounds.json", "invalid bounds metadata is rejected")

	var duplicate_yaw: Dictionary = valid_document.duplicate(true)
	var duplicate_yaw_component: Dictionary = component_binding.duplicate(true)
	var duplicate_yaw_placement: Dictionary = (duplicate_yaw_component["placement"] as Dictionary).duplicate(true)
	duplicate_yaw_placement["allowed_yaw_deg"] = [0.0, 90.0, 90.0]
	duplicate_yaw_component["placement"] = duplicate_yaw_placement
	(duplicate_yaw["components"] as Dictionary)["reactor_console"] = duplicate_yaw_component
	failures += _expect_catalog_rejected(duplicate_yaw, "user://task5-duplicate-yaw.json", "duplicate allowed yaw is rejected")

	var serialized_valid: String = JSON.stringify(valid_document)
	var duplicate_key_token: String = "\"schema_version\":\"1.0.0\","
	var duplicate_key_offset: int = serialized_valid.find(duplicate_key_token)
	var duplicate_key_document: String = serialized_valid
	if duplicate_key_offset >= 0:
		duplicate_key_document = serialized_valid.substr(0, duplicate_key_offset) \
			+ duplicate_key_token + serialized_valid.substr(duplicate_key_offset)
	failures += _expect_catalog_raw_rejected(
		duplicate_key_document,
		"user://task5-duplicate-json-key.json",
		"duplicate JSON object key is rejected",
	)

	var cross_kind_marker: Node3D = Node3D.new()
	get_root().add_child(cross_kind_marker)
	failures += _expect(
		not RuntimePropVisualBinderScript.mount_component_visual(cross_kind_marker, objective_binding),
		"objective binding cannot mount as component visual",
	)
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(component_binding) == null,
		"component binding cannot create objective visual",
	)
	failures += _expect(
		RuntimePropVisualBinderScript.mount_component_visual(cross_kind_marker, dressing_binding) == false,
		"dressing binding cannot mount as component visual",
	)
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(dressing_binding) == null,
		"dressing binding cannot create objective visual",
	)
	var invalid_asset_binding_runtime: Dictionary = component_binding.duplicate(true)
	invalid_asset_binding_runtime["asset_id"] = "ReactorConsole"
	invalid_asset_binding_runtime["visual_scene_path"] = "res://assets/imported/props/components/ReactorConsole.glb"
	var invalid_asset_runtime_meta: Dictionary = (invalid_asset_binding_runtime["binding"] as Dictionary).duplicate(true)
	invalid_asset_runtime_meta["ids"] = ["ReactorConsole"]
	invalid_asset_binding_runtime["binding"] = invalid_asset_runtime_meta
	failures += _expect(
		not RuntimePropVisualBinderScript.mount_component_visual(cross_kind_marker, invalid_asset_binding_runtime),
		"binder rejects asset_id outside the canonical lowercase identifier grammar",
	)

	var marker: Node3D = Node3D.new()
	get_root().add_child(marker)
	var mounted: bool = RuntimePropVisualBinderScript.mount_component_visual(marker, component_binding)
	failures += _expect(mounted, "component visual mounts")
	var imported_component: Node3D = marker.get_node_or_null("ImportedVisual") as Node3D
	failures += _expect(imported_component != null, "component ImportedVisual child exists")
	if imported_component != null:
		failures += _expect(
			str(imported_component.get_meta("visual_source", "")) == "imported",
			"component visual source is imported",
		)
		failures += _expect(
			RuntimePropVisualBinderScript.validate_visual_tree(imported_component),
			"component visual is visual-only",
		)

	var detached_objective: Node3D = RuntimePropVisualBinderScript.create_objective_visual(objective_binding)
	failures += _expect(detached_objective != null, "objective visual creates")
	if detached_objective != null:
		failures += _expect(detached_objective.get_parent() == null, "objective visual is detached")
		failures += _expect(detached_objective.name == "ImportedVisual", "objective visual has stable name")
		failures += _expect(
			str(detached_objective.get_meta("visual_source", "")) == "imported",
			"objective visual source is imported",
		)
		failures += _expect(
			RuntimePropVisualBinderScript.validate_visual_tree(detached_objective),
			"objective visual is visual-only",
		)

	var transformed_binding: Dictionary = objective_binding.duplicate(true)
	var placement: Dictionary = (transformed_binding["placement"] as Dictionary).duplicate(true)
	placement["offset_m"] = [1.0, 2.0, 3.0]
	placement["rotation_degrees"] = [4.0, 5.0, 6.0]
	placement["scale"] = 2.0
	transformed_binding["placement"] = placement
	var transformed: Node3D = RuntimePropVisualBinderScript.create_objective_visual(transformed_binding)
	failures += _expect(transformed != null, "finite transforms are accepted")
	if transformed != null:
		failures += _expect(transformed.position == Vector3(1.0, 2.0, 3.0), "offset transform applied")
		failures += _expect(_approx_vector(transformed.rotation_degrees, Vector3(4.0, 5.0, 6.0)), "rotation transform applied")
		failures += _expect(_approx_vector(transformed.scale, Vector3(2.0, 2.0, 2.0)), "scale transform applied")

	var invalid_binding: Dictionary = objective_binding.duplicate(true)
	var invalid_placement: Dictionary = (invalid_binding["placement"] as Dictionary).duplicate(true)
	invalid_placement["offset_m"] = [0.0, 0.0]
	invalid_binding["placement"] = invalid_placement
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(invalid_binding) == null,
		"invalid transform array is rejected",
	)
	var invalid_scale_binding: Dictionary = objective_binding.duplicate(true)
	var zero_scale_placement: Dictionary = (invalid_scale_binding["placement"] as Dictionary).duplicate(true)
	zero_scale_placement["scale"] = 0.0
	invalid_scale_binding["placement"] = zero_scale_placement
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(invalid_scale_binding) == null,
		"nonpositive scale is rejected",
	)
	var nonnumeric_scale_binding: Dictionary = objective_binding.duplicate(true)
	var nonnumeric_scale_placement: Dictionary = (nonnumeric_scale_binding["placement"] as Dictionary).duplicate(true)
	nonnumeric_scale_placement["scale"] = "not-a-number"
	nonnumeric_scale_binding["placement"] = nonnumeric_scale_placement
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(nonnumeric_scale_binding) == null,
		"nonnumeric scale is rejected",
	)

	var missing_binding: Dictionary = objective_binding.duplicate(true)
	missing_binding["asset_id"] = "missing_task5_visual"
	missing_binding["visual_scene_path"] = "res://assets/imported/props/objectives/missing_task5_visual.glb"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(missing_binding) == null,
		"missing resource is rejected without loading",
	)
	var traversal_binding: Dictionary = objective_binding.duplicate(true)
	traversal_binding["asset_id"] = "reactor_console"
	traversal_binding["visual_scene_path"] = "res://assets/imported/props/objectives/../reactor_console.glb"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(traversal_binding) == null,
		"noncanonical binder path is rejected before loading",
	)
	var malformed_binding_root: Dictionary = objective_binding.duplicate(true)
	malformed_binding_root["unexpected_root_field"] = true
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_root) == null,
		"unexpected binding root field is rejected independently",
	)
	var missing_binding_root: Dictionary = objective_binding.duplicate(true)
	missing_binding_root.erase("source")
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(missing_binding_root) == null,
		"missing binding root field is rejected independently",
	)
	var malformed_binding_schema: Dictionary = objective_binding.duplicate(true)
	malformed_binding_schema["schema_version"] = "1.0"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_schema) == null,
		"malformed binding schema version is rejected independently",
	)
	var malformed_binding_source: Dictionary = objective_binding.duplicate(true)
	var malformed_binding_source_meta: Dictionary = (malformed_binding_source["source"] as Dictionary).duplicate(true)
	malformed_binding_source_meta["byte_size"] = "stale"
	malformed_binding_source["source"] = malformed_binding_source_meta
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_source) == null,
		"malformed binding source metadata is rejected independently",
	)
	var malformed_binding_bounds: Dictionary = objective_binding.duplicate(true)
	var malformed_binding_bounds_meta: Dictionary = (malformed_binding_bounds["bounds"] as Dictionary).duplicate(true)
	malformed_binding_bounds_meta["local_max_m"] = [0.0, 0.0]
	malformed_binding_bounds["bounds"] = malformed_binding_bounds_meta
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_bounds) == null,
		"malformed binding bounds are rejected independently",
	)
	var malformed_binding_collision: Dictionary = objective_binding.duplicate(true)
	malformed_binding_collision["collision_policy"] = "generated_collision"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_collision) == null,
		"non-visual collision policy is rejected independently",
	)
	var malformed_binding_namespace: Dictionary = objective_binding.duplicate(true)
	var malformed_binding_meta: Dictionary = (malformed_binding_namespace["binding"] as Dictionary).duplicate(true)
	malformed_binding_meta["namespace"] = "component_id"
	malformed_binding_namespace["binding"] = malformed_binding_meta
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(malformed_binding_namespace) == null,
		"binding namespace mismatch is rejected independently",
	)
	var zero_binding_hash: Dictionary = objective_binding.duplicate(true)
	var zero_binding_source: Dictionary = (zero_binding_hash["source"] as Dictionary).duplicate(true)
	zero_binding_source["sha256"] = "0".repeat(64)
	zero_binding_hash["source"] = zero_binding_source
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(zero_binding_hash) == null,
		"all-zero binding source hash is rejected independently",
	)
	var duplicate_binding_yaw: Dictionary = objective_binding.duplicate(true)
	var duplicate_binding_placement: Dictionary = (duplicate_binding_yaw["placement"] as Dictionary).duplicate(true)
	duplicate_binding_placement["allowed_yaw_deg"] = [0.0, 90.0, 90.0]
	duplicate_binding_yaw["placement"] = duplicate_binding_placement
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(duplicate_binding_yaw) == null,
		"duplicate binding yaw is rejected independently",
	)

	var collision_root: Node3D = Node3D.new()
	collision_root.add_child(StaticBody3D.new())
	failures += _expect(
		not RuntimePropVisualBinderScript.validate_visual_tree(collision_root),
		"CollisionObject3D visual is rejected",
	)
	var shape_root: Node3D = Node3D.new()
	shape_root.add_child(CollisionShape3D.new())
	failures += _expect(
		not RuntimePropVisualBinderScript.validate_visual_tree(shape_root),
		"CollisionShape3D visual is rejected",
	)
	var area_root: Node3D = Node3D.new()
	area_root.add_child(Area3D.new())
	failures += _expect(
		not RuntimePropVisualBinderScript.validate_visual_tree(area_root),
		"Area3D visual is rejected",
	)
	var physics_query_types: Array = [
		CollisionPolygon3D.new(),
		NavigationRegion3D.new(),
		NavigationObstacle3D.new(),
		NavigationAgent3D.new(),
		NavigationLink3D.new(),
		RayCast3D.new(),
		ShapeCast3D.new(),
		SpringArm3D.new(),
		HingeJoint3D.new(),
	]
	for physics_query_node_variant in physics_query_types:
		var physics_query_node: Node = physics_query_node_variant as Node
		var physics_query_root: Node3D = Node3D.new()
		var nested_physics_parent: Node3D = Node3D.new()
		physics_query_root.add_child(nested_physics_parent)
		nested_physics_parent.add_child(physics_query_node)
		failures += _expect(
			not RuntimePropVisualBinderScript.validate_visual_tree(physics_query_root),
			"%s visual is rejected recursively" % physics_query_node.get_class(),
		)
		physics_query_root.free()
	var scripted_root: Node3D = Node3D.new()
	var scripted_node: Node3D = Node3D.new()
	scripted_node.set_script(ProcgenDebugRunnerScript)
	scripted_node.set_meta("gltf_imported", true)
	scripted_root.add_child(scripted_node)
	failures += _expect(
		not RuntimePropVisualBinderScript.validate_visual_tree(scripted_root),
		"script-attached visual is rejected",
	)
	var interaction_root: Node3D = Node3D.new()
	interaction_root.add_child(InteractableScript.new())
	failures += _expect(
		not RuntimePropVisualBinderScript.validate_visual_tree(interaction_root),
		"interaction visual is rejected",
	)

	var benign_import_root: Node3D = Node3D.new()
	var benign_import_script: GDScript = GDScript.new()
	benign_import_script.source_code = "extends Node3D\n"
	var benign_import_reload: Error = benign_import_script.reload()
	failures += _expect(benign_import_reload == OK, "benign importer script fixture compiles")
	if benign_import_reload == OK:
		benign_import_root.set_script(benign_import_script)
		benign_import_root.set_meta("gltf_imported", true)
	failures += _expect(
		RuntimePropVisualBinderScript.validate_visual_tree(benign_import_root),
		"benign Godot importer script is accepted",
	)
	var benign_mesh_root: Node3D = Node3D.new()
	benign_mesh_root.add_child(MeshInstance3D.new())
	failures += _expect(
		RuntimePropVisualBinderScript.validate_visual_tree(benign_mesh_root),
		"ordinary mesh visual remains accepted",
	)

	var unrelated_direct: Node3D = Node3D.new()
	unrelated_direct.name = "KeepMe"
	marker.add_child(unrelated_direct)
	var nested_root: Node3D = Node3D.new()
	nested_root.name = "Nested"
	marker.add_child(nested_root)
	var nested_unrelated: Node3D = Node3D.new()
	nested_unrelated.name = "KeepNested"
	nested_root.add_child(nested_unrelated)
	var nested_imported: Node3D = Node3D.new()
	nested_imported.name = "ImportedVisual"
	nested_imported.set_meta("visual_source", "imported")
	nested_root.add_child(nested_imported)
	RuntimePropVisualBinderScript.clear_imported_visuals(marker)
	failures += _expect(_count_imported_visuals(marker) == 0, "nested imported visuals clear recursively")
	failures += _expect(marker.get_node_or_null("KeepMe") != null, "unrelated direct child is preserved")
	failures += _expect(marker.get_node_or_null("Nested/KeepNested") != null, "unrelated nested child is preserved")
	failures += _expect(marker.get_node_or_null("Nested/ImportedVisual") == null, "nested imported child is removed")

	var remounted: bool = RuntimePropVisualBinderScript.mount_component_visual(marker, component_binding)
	failures += _expect(remounted, "visual remounts after cleanup")
	var duplicate_mount: bool = RuntimePropVisualBinderScript.mount_component_visual(marker, component_binding)
	failures += _expect(not duplicate_mount, "duplicate ImportedVisual mount is rejected")
	failures += _expect(_count_imported_visuals(marker) == 1, "duplicate mount leaves one ImportedVisual")

	var missing_marker: Node3D = Node3D.new()
	get_root().add_child(missing_marker)
	failures += _expect(
		not RuntimePropVisualBinderScript.mount_component_visual(missing_marker, {}),
		"missing binding falls back without imported visual",
	)
	failures += _expect(missing_marker.get_child_count() == 0, "fallback marker has no imported visual")
	RuntimePropVisualBinderScript.clear_imported_visuals(marker)

	for temporary_path in [
		"user://task5-extra-root.json",
		"user://task5-malformed-schema.json",
		"user://task5-malformed-kind.json",
		"user://task5-malformed-path.json",
		"user://task5-marker-anchor.json",
		"user://task5-objective-valid-surface.json",
		"user://task5-dressing-no-surface.json",
		"user://task5-invalid-surface.json",
		"user://task5-invalid-objective-surface.json",
		"user://task5-invalid-asset-id.json",
		"user://task5-malformed-namespace.json",
		"user://task5-malformed-source.json",
		"user://task5-malformed-hash.json",
		"user://task5-zero-hash.json",
		"user://task5-malformed-bounds.json",
		"user://task5-duplicate-yaw.json",
		"user://task5-duplicate-json-key.json",
	]:
		_remove_user_file(temporary_path)
	if objective_surface_visual != null:
		objective_surface_visual.free()
	if detached_objective != null:
		detached_objective.free()
	if transformed != null:
		transformed.free()
	collision_root.free()
	shape_root.free()
	area_root.free()
	scripted_root.free()
	interaction_root.free()
	benign_import_root.free()
	benign_mesh_root.free()
	get_root().remove_child(cross_kind_marker)
	cross_kind_marker.free()
	get_root().remove_child(marker)
	marker.free()
	get_root().remove_child(missing_marker)
	missing_marker.free()

	if failures != 0:
		push_error("PROP VISUAL BINDING FAILURES: %d" % failures)
		quit(1)
		return
	print("PROP VISUAL BINDING PASS catalog_strict=true dressing=true visual_only=true fallback=true cleanup=true")
	quit(0)


func _expect(condition: bool, message: String) -> int:
	if condition:
		return 0
	push_error("PROP VISUAL BINDING FAILURE: %s" % message)
	return 1


func _expect_catalog_rejected(document: Dictionary, path: String, message: String) -> int:
	if not _write_json(path, document):
		return _expect(false, "%s (fixture write failed)" % message)
	var probe = PropVisualBindingCatalogScript.new()
	var loaded: bool = probe.load_from_path(path)
	var rejected: bool = not loaded and not probe.get_errors().is_empty()
	_remove_user_file(path)
	return _expect(rejected, message)


func _expect_catalog_accepted(document: Dictionary, path: String, message: String) -> int:
	if not _write_json(path, document):
		return _expect(false, "%s (fixture write failed)" % message)
	var probe = PropVisualBindingCatalogScript.new()
	var loaded: bool = probe.load_from_path(path)
	_remove_user_file(path)
	return _expect(loaded, message)


func _expect_catalog_raw_rejected(document: String, path: String, message: String) -> int:
	if not _write_raw_json(path, document):
		return _expect(false, "%s (fixture write failed)" % message)
	var probe = PropVisualBindingCatalogScript.new()
	var loaded: bool = probe.load_from_path(path)
	var errors: Array[String] = probe.get_errors()
	var rejected: bool = not loaded and errors.any(func(error: String) -> bool: return error.contains("duplicate JSON object key"))
	_remove_user_file(path)
	return _expect(rejected, message)


func _catalog_document(component: Dictionary, objective: Dictionary, dressing: Dictionary) -> Dictionary:
	return {
		"schema_version": "1.0.0",
		"document_kind": "prop_visual_binding_index",
		"components": {"reactor_console": component},
		"objectives": {"reactor_control_panel": objective},
		"dressing": {"cable_tray": dressing},
	}


func _write_json(path: String, document: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document))
	file.close()
	return true


func _write_raw_json(path: String, document: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(document)
	file.close()
	return true


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _count_imported_visuals(root: Node) -> int:
	if root == null:
		return 0
	var count: int = 0
	if str(root.get_meta("visual_source", "")) == "imported":
		count += 1
	for child_variant in root.get_children():
		count += _count_imported_visuals(child_variant as Node)
	return count


func _approx_vector(actual: Vector3, expected: Vector3) -> bool:
	return is_equal_approx(actual.x, expected.x) and is_equal_approx(actual.y, expected.y) and is_equal_approx(actual.z, expected.z)
