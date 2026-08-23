extends RefCounted
class_name IntegrityVisualResolver

## Maps integrity state to the correct visual child in a structural wrapper scene.
## Does not change module identity, collision, or navigation — only visibility.

const ModuleIntegrityConsequencesScript: GDScript = preload("res://scripts/systems/module_integrity_consequences.gd")

const STATE_INTACT: String = "intact"
const STATE_DAMAGED: String = "damaged"
const STATE_BREACHED: String = "breached"
const STATE_DESTROYED: String = "destroyed"


## Apply visual state to a wrapper node's Visual child group.
## Returns true if a matching visual was found and toggled.
static func apply_visual_state(wrapper_node: Node3D, state: String) -> bool:
	if wrapper_node == null:
		return false
	var visual_group: Node3D = wrapper_node.get_node_or_null("Visual") as Node3D
	if visual_group == null:
		return false

	var intact_node: Node = visual_group.get_node_or_null("VisualInstance_Intact")
	var damaged_node: Node = visual_group.get_node_or_null("VisualInstance_Damaged")
	var breached_node: Node = visual_group.get_node_or_null("VisualInstance_Breached")

	# Legacy single-child fallback.
	var legacy_node: Node = visual_group.get_node_or_null("VisualInstance")

	if intact_node == null and damaged_node == null and breached_node == null:
		if legacy_node == null or not legacy_node is Node3D:
			return false
		var consequence: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(state)
		var tint_v: Variant = consequence.get("modulate", [1.0, 1.0, 1.0, 1.0])
		if tint_v is Array and (tint_v as Array).size() >= 4:
			_apply_legacy_tint(legacy_node as Node3D, Color(
				float((tint_v as Array)[0]),
				float((tint_v as Array)[1]),
				float((tint_v as Array)[2]),
				float((tint_v as Array)[3]),
			))
		(legacy_node as Node3D).visible = state != STATE_DESTROYED
		return true

	# Variant-aware wrapper: hide all, then show the requested variant.
	if intact_node != null and intact_node is Node3D:
		(intact_node as Node3D).visible = false
	if damaged_node != null and damaged_node is Node3D:
		(damaged_node as Node3D).visible = false
	if breached_node != null and breached_node is Node3D:
		(breached_node as Node3D).visible = false

	match state:
		STATE_INTACT:
			if intact_node != null and intact_node is Node3D:
				(intact_node as Node3D).visible = true
				return true
		STATE_DAMAGED:
			if damaged_node != null and damaged_node is Node3D:
				(damaged_node as Node3D).visible = true
				return true
		STATE_BREACHED:
			if breached_node != null and breached_node is Node3D:
				(breached_node as Node3D).visible = true
				return true
		STATE_DESTROYED:
			# All variants hidden means the wrapper has no visible mesh.
			return true
	return false


## Batch-apply integrity visuals to all modules in a ship scene tree.
static func apply_to_ship(ship_root: Node3D, module_map: RefCounted) -> int:
	if ship_root == null or module_map == null or not module_map.has_method("get_state"):
		return 0
	var applied: int = 0
	var modules_container: Node = ship_root.get_node_or_null("StructuralModules")
	if modules_container == null:
		modules_container = ship_root

	for child in modules_container.get_children():
		if not child is Node3D:
			continue
		var module_id: String = child.name
		var state: String = str(module_map.call("get_state", module_id))
		if apply_visual_state(child as Node3D, state):
			applied += 1

	return applied


static func _apply_legacy_tint(node: Node3D, color: Color) -> void:
	var node_ref: Node = node
	if node_ref is CanvasItem:
		(node_ref as CanvasItem).modulate = color
	elif node_ref is GeometryInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		if color.a < 0.99:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(node_ref as GeometryInstance3D).material_override = material
	for child in node.get_children():
		if child is Node3D:
			_apply_legacy_tint(child as Node3D, color)