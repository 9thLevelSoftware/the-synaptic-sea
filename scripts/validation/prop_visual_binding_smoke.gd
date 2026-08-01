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

	var missing_binding: Dictionary = component_binding.duplicate(true)
	missing_binding["visual_scene_path"] = "res://assets/imported/props/components/missing_task5_visual.glb"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(missing_binding) == null,
		"missing resource is rejected without loading",
	)
	var traversal_binding: Dictionary = component_binding.duplicate(true)
	traversal_binding["visual_scene_path"] = "res://assets/imported/props/components/../reactor_console.glb"
	failures += _expect(
		RuntimePropVisualBinderScript.create_objective_visual(traversal_binding) == null,
		"noncanonical binder path is rejected before loading",
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
		"user://task5-malformed-namespace.json",
	]:
		_remove_user_file(temporary_path)
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
