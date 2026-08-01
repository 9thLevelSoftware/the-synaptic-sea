extends SceneTree

const PropVisualBindingCatalogScript := preload("res://scripts/systems/prop_visual_binding_catalog.gd")
const RuntimePropVisualBinderScript := preload("res://scripts/procgen/runtime_prop_visual_binder.gd")

func _initialize() -> void:
	var failures: int = 0
	var catalog = PropVisualBindingCatalogScript.new()
	failures += _expect(catalog.load_from_path(), "catalog loads generated index")
	var component_binding: Dictionary = catalog.get_component_binding("reactor_console")
	var objective_binding: Dictionary = catalog.get_objective_binding("reactor_control_panel")
	failures += _expect(not component_binding.is_empty(), "reactor console resolves")
	failures += _expect(not objective_binding.is_empty(), "reactor panel resolves")
	failures += _expect(catalog.get_component_binding("missing_component").is_empty(), "unknown component is empty")
	failures += _expect(catalog.get_objective_binding("bridge_power_distribution").is_empty(), "unmapped objective is empty")
	failures += _expect(catalog.get_dressing_binding("missing_dressing").is_empty(), "unknown dressing is empty")

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
		failures += _expect(_is_visual_only(imported_component), "component visual is visual-only")

	var detached_objective: Node3D = RuntimePropVisualBinderScript.create_objective_visual(objective_binding)
	failures += _expect(detached_objective != null, "objective visual creates")
	if detached_objective != null:
		failures += _expect(detached_objective.get_parent() == null, "objective visual is detached")
		failures += _expect(detached_objective.name == "ImportedVisual", "objective visual has stable name")
		failures += _expect(
			str(detached_objective.get_meta("visual_source", "")) == "imported",
			"objective visual source is imported",
		)
		failures += _expect(_is_visual_only(detached_objective), "objective visual is visual-only")

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

	var missing_marker: Node3D = Node3D.new()
	get_root().add_child(missing_marker)
	failures += _expect(
		not RuntimePropVisualBinderScript.mount_component_visual(missing_marker, {}),
		"missing binding falls back without imported visual",
	)
	failures += _expect(missing_marker.get_child_count() == 0, "fallback marker has no imported visual")
	RuntimePropVisualBinderScript.clear_imported_visuals(marker)
	failures += _expect(marker.get_node_or_null("ImportedVisual") == null, "imported visual clears")

	if detached_objective != null:
		detached_objective.free()
	if transformed != null:
		transformed.free()
	get_root().remove_child(marker)
	marker.free()
	get_root().remove_child(missing_marker)
	missing_marker.free()

	if failures != 0:
		push_error("PROP VISUAL BINDING FAILURES: %d" % failures)
		quit(1)
		return
	print("PROP VISUAL BINDING PASS components=true objectives=true fallback=true")
	quit(0)


func _expect(condition: bool, message: String) -> int:
	if condition:
		return 0
	push_error("PROP VISUAL BINDING FAILURE: %s" % message)
	return 1


func _approx_vector(actual: Vector3, expected: Vector3) -> bool:
	return is_equal_approx(actual.x, expected.x) and is_equal_approx(actual.y, expected.y) and is_equal_approx(actual.z, expected.z)


func _is_visual_only(root: Node) -> bool:
	if root is CollisionObject3D or root.get_script() != null:
		return false
	for child in root.get_children():
		if not _is_visual_only(child as Node):
			return false
	return true
